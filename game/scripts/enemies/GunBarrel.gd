extends Node
class_name GunBarrel

# a component under an AiScript "gun mount": at ready it reads a
# MultiSprite json ("mount" + "barrel" entries + a pin joint), builds the
# barrel as a RegolithSprite child of the mount, wires the joint, and
# keeps the host's weapon fire origin over the barrel's muzzle each step.
# the lua accesses this component with self.node:get_node("GunBarrel") in
# its init to call align_aim, aim_angle, muzzle_position, has_barrel and
# is_part. the mount is any AiScript (an "enemy_gun" or a "turret" or
# whatever a scene author calls it) — this is scene-only glue, no host
# subclass involved

const META_SCALE_CELLS := &"scale_cells"
const BARREL_GROUPS := ["regolith", "gun"]
const MOUNT := "mount"
const BARREL := "barrel"

@export_file("*.json") var multisprite: String
# cells across to build the parts at, zero keeps the document's own size
@export var scale_cells := 0
@export var barrel_angular_damping := 1.0

var host: AiScript
var barrel: RegolithSprite
var joint_id := -1
# cells across the parts were built at
var art_cells := 0
var layout := {}
# the pin's point in the mount's local pixels, the barrel's pivot
var pivot_local := Vector2.ZERO
# where shots leave, in the barrel's local pixels
var muzzle_local := Vector2.ZERO
# true from the frame build_children ran onward, whether or not the
# barrel still lives. tells align_aim to fall back to spinning the mount
# only after a barrel was really lost, not while it is still loading
var built := false

var pending_data := {}
var pending_images := {}
var pending_cells := 0

func _ready() -> void:
	host = get_parent() as AiScript

	if host == null:
		push_warning("GunBarrel: parent is not an AiScript")
		return

	# split the work: prepare the document and force-load the mount
	# synchronously so the mount grid is the right size on first frame,
	# then defer the barrel add_child + joint since the parent is still
	# processing its own children in the current scene-load frame
	prepare_mount(wanted_cells())
	call_deferred("build_children")

# the meta hint, then the export, then the document's art
func wanted_cells() -> int:
	var hint := int(host.get_meta(META_SCALE_CELLS, 0))

	if hint > 0:
		return hint

	if scale_cells > 0:
		return scale_cells

	return document_cells(MultiSprite.read_file(multisprite))

# the width of the document's mount art, zero without one
static func document_cells(data: Dictionary) -> int:
	var index := MultiSprite.index_of(data, MOUNT)

	if index < 0:
		return 0

	var image: Image = MultiSprite.entry_images(data["sprites"][index], {})["color"]
	return image.get_width() if image else 0

# reads the document (or regenerates it at the requested cells), loads
# the mount art onto the host synchronously so the mount grid matches
# from frame one, and caches the data / images for build_children to
# spawn the barrel on the next idle
func prepare_mount(cells: int) -> void:
	if RegolithWorld.active() == null:
		return

	var data := MultiSprite.read_file(multisprite)
	var art := document_cells(data)
	var images := {}
	art_cells = cells if cells > 0 else art

	if art_cells <= 0:
		return

	if data.is_empty() or art_cells != art:
		var generated := GunArt.document(art_cells)
		data = generated["data"]
		images = generated["images"]

		if art > 0:
			scale_sensors(float(art_cells) / float(art))

		# force the mount to reload from the regenerated art. the scene's
		# default texture already loaded in RegolithSprite's own ready,
		# spawn_parts skips loaded roots, so a bigger size wins here
		var mount_index := MultiSprite.index_of(data, MOUNT)
		if mount_index >= 0:
			var pair := MultiSprite.entry_images(data["sprites"][mount_index], images)
			if pair["color"] != null:
				host.load_from_images(pair["color"], pair["mask"])

	data["root"] = MultiSprite.index_of(data, MOUNT)
	layout = GunArt.layout(art_cells)
	pending_data = data
	pending_images = images
	pending_cells = art_cells

# runs on the idle after ready: adds the barrel + pin. deferred because
# the parent is still setting up children when GunBarrel's ready fires,
# and root.add_child would throw "busy setting up children"
func build_children() -> void:
	if pending_data.is_empty():
		return

	var data: Dictionary = pending_data
	var images: Dictionary = pending_images
	var result := MultiSprite.spawn_parts(data, host, images)
	var barrel_index := MultiSprite.index_of(data, BARREL)

	if barrel_index < 0 or barrel_index >= result["sprites"].size():
		return

	barrel = result["sprites"][barrel_index]
	barrel.name = "Barrel"
	barrel.angular_damping = barrel_angular_damping
	barrel.tree_exited.connect(on_barrel_gone)

	for group in BARREL_GROUPS:
		barrel.add_to_group(group)

	var ppu := RegolithWorld.pixels_per_unit()
	var root_from_document: Transform2D = result["root_from_document"]
	var pin := pin_entry(data, barrel_index)

	if not result["joints"].is_empty():
		joint_id = result["joints"][0]

	if not pin.is_empty():
		pivot_local = root_from_document * MultiSprite.entry_vector(pin, "point", ppu)

	if data.has("muzzle"):
		var muzzle_document := Vector2(data["muzzle"][0], data["muzzle"][1]) * ppu
		var barrel_from_document := MultiSprite.entry_transform(data["sprites"][barrel_index], ppu).affine_inverse()
		muzzle_local = barrel_from_document * muzzle_document

	sync_muzzle()
	built = true

	pending_data = {}
	pending_images = {}

# the joint between the mount and the barrel, {} when there is none
static func pin_entry(data: Dictionary, barrel_index: int) -> Dictionary:
	for entry in data.get("joints", []):
		if int(entry["a"]) == barrel_index or int(entry["b"]) == barrel_index:
			return entry

	return {}

func scale_sensors(ratio: float) -> void:
	for child in host.get_children():
		if child is PlayerSensor:
			child.radius *= ratio

func on_barrel_gone() -> void:
	barrel = null
	joint_id = -1

func has_barrel() -> bool:
	return barrel != null and is_instance_valid(barrel) and barrel.is_loaded()

func is_part(node: Object) -> bool:
	return node != null and node == barrel

func parts() -> Array:
	return [barrel] if has_barrel() else []

# the barrel's facing, the mount's own when it has none
func aim_angle() -> float:
	return barrel.global_rotation if has_barrel() else host.global_rotation

func aim_direction() -> Vector2:
	return Vector2.from_angle(aim_angle())

# the spring of AiAngleAlignment on the barrel, max_rate above zero caps
# its spin, the turret's slow traverse
func align_aim(target_angle: float, torque: float, damping: float, delta: float, max_rate := 0.0) -> void:
	# barrel not built yet: do nothing this frame, come back next tick.
	# without this the mount would take the alignment force and rotate
	if not has_barrel():
		# only fall back to spinning the mount if the barrel was there
		# and got shot off, not while it is still loading in
		if built:
			host.align_angle(target_angle, torque, damping, delta)
		return

	var delta_angle := Steering.wrap_angle(target_angle - barrel.global_rotation)
	var spin := barrel.angular_velocity + delta_angle * torque * delta
	spin -= spin * damping * delta

	if max_rate > 0.0:
		spin = clampf(spin, -max_rate, max_rate)

	barrel.angular_velocity = spin

# the pin, units
func pivot_position() -> Vector2:
	return host.to_global(pivot_local) / Steering.ppu()

# where the shots leave, units
func muzzle_position() -> Vector2:
	if host.weapon and is_instance_valid(host.weapon):
		return host.weapon.fire_origin() / Steering.ppu()

	return pivot_position() + aim_direction() * layout.get("muzzle_x", 0.0) / RegolithWorld.CELLS_PER_CHUNK

# the weapon fires from the barrel's muzzle, in the mount's frame
func sync_muzzle() -> void:
	if host == null or host.weapon == null or not is_instance_valid(host.weapon) or not has_barrel():
		return

	host.weapon.local_fire_origin = host.to_local(barrel.to_global(muzzle_local)) / Steering.ppu()

# each physics step: keep the fire origin under the barrel's muzzle
func _physics_process(_delta: float) -> void:
	if has_barrel():
		sync_muzzle()
