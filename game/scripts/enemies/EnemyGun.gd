extends EnemyScripted
class_name EnemyGun

# a gun in two parts, built from a MultiSprite document (multisprite, the
# json the Sprites tab's MultiSpriteEditor opens): the "mount" entry is
# this node, GunArt's hex ring plate with the core pods in its wall, the
# enemy proper: it carries the sensors, the weapon, the drop table and
# dies with its core. the "barrel" entry, a cannon whose tube reaches well
# past the ring, becomes a RegolithSprite child, pinned on the ring's
# center by the document's joint. that joint does not collide connected,
# so the barrel's hub sits over the mount without the two pushing apart,
# and it spins freely to aim while the mount holds still (the pin sits on
# the mount's center of mass). gun.lua and turret.lua turn the barrel
# through aim_angle and align_aim and pull the trigger with fire. the
# weapon stays on the mount (a bullet skips only its shooter), its fire
# origin follows the document's muzzle point on the barrel every step.
#
# the document is built at the size its mount art is. a scenario
# placement's size hint reaches here as scale_cells meta, copied onto the
# node by the StableSpawner before it enters the tree (or the scale_cells
# export); a size other than the document's regenerates the document with
# GunArt.document at that size, painted in memory, and scales the player
# sensors with it. an editor only MultiSpritePreview child draws the
# barrel over the mount in the scene

const META_SCALE_CELLS := &"scale_cells"
const BARREL_GROUPS := ["regolith", "gun"]
const MOUNT := "mount"
const BARREL := "barrel"

@export_file("*.json") var multisprite: String
# cells across to build the parts at, zero keeps the document's own size
@export var scale_cells := 0
@export var barrel_angular_damping := 1.0

var barrel: RegolithSprite
var joint_id := -1
# cells across the parts were built at
var art_cells := 0
var layout := {}
# the pin's point in the mount's local pixels, the barrel's pivot
var pivot_local := Vector2.ZERO
# where shots leave, in the barrel's local pixels
var muzzle_local := Vector2.ZERO

func _ready() -> void:
	build_parts(wanted_cells())
	super()
	sync_muzzle()

# the meta hint, then the export, then the document's art
func wanted_cells() -> int:
	var hint := int(get_meta(META_SCALE_CELLS, 0))

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

# builds the document around this node: loads the mount, makes the barrel
# and the pin. the mount loads itself here, before the sprite's own ready,
# so the joint can be made at once and a regenerated size wins over the
# scene texture
func build_parts(cells: int) -> void:
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

	data["root"] = MultiSprite.index_of(data, MOUNT)
	layout = GunArt.layout(art_cells)

	var built := MultiSprite.spawn_parts(data, self, images)
	var barrel_index := MultiSprite.index_of(data, BARREL)

	if barrel_index < 0 or barrel_index >= built["sprites"].size():
		return

	barrel = built["sprites"][barrel_index]
	barrel.name = "Barrel"
	barrel.angular_damping = barrel_angular_damping
	barrel.tree_exited.connect(on_barrel_gone)

	for group in BARREL_GROUPS:
		barrel.add_to_group(group)

	var ppu := RegolithWorld.pixels_per_unit()
	var root_from_document: Transform2D = built["root_from_document"]
	var pin := pin_entry(data, barrel_index)

	if not built["joints"].is_empty():
		joint_id = built["joints"][0]

	if not pin.is_empty():
		pivot_local = root_from_document * MultiSprite.entry_vector(pin, "point", ppu)

	if data.has("muzzle"):
		var muzzle_document := Vector2(data["muzzle"][0], data["muzzle"][1]) * ppu
		var barrel_from_document := MultiSprite.entry_transform(data["sprites"][barrel_index], ppu).affine_inverse()
		muzzle_local = barrel_from_document * muzzle_document

# the joint between the mount and the barrel, {} when there is none
static func pin_entry(data: Dictionary, barrel_index: int) -> Dictionary:
	for entry in data.get("joints", []):
		if int(entry["a"]) == barrel_index or int(entry["b"]) == barrel_index:
			return entry

	return {}

func scale_sensors(ratio: float) -> void:
	for child in get_children():
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
	return barrel.global_rotation if has_barrel() else global_rotation

func aim_direction() -> Vector2:
	return Vector2.from_angle(aim_angle())

# the spring of AiAngleAlignment on the barrel, max_rate above zero caps
# its spin, the turret's slow traverse
func align_aim(target_angle: float, torque: float, damping: float, delta: float, max_rate := 0.0) -> void:
	if not has_barrel():
		align_angle(target_angle, torque, damping, delta)
		return

	var delta_angle := Steering.wrap_angle(target_angle - barrel.global_rotation)
	var spin := barrel.angular_velocity + delta_angle * torque * delta
	spin -= spin * damping * delta

	if max_rate > 0.0:
		spin = clampf(spin, -max_rate, max_rate)

	barrel.angular_velocity = spin

# the pin, units
func pivot_position() -> Vector2:
	return to_global(pivot_local) / Steering.ppu()

# where the shots leave, units
func muzzle_position() -> Vector2:
	if weapon and is_instance_valid(weapon):
		return weapon.fire_origin() / Steering.ppu()

	return pivot_position() + aim_direction() * layout.get("muzzle_x", 0.0) / RegolithWorld.CELLS_PER_CHUNK

# the weapon fires from the barrel's muzzle, in the mount's frame
func sync_muzzle() -> void:
	if weapon == null or not is_instance_valid(weapon) or not has_barrel():
		return

	weapon.local_fire_origin = to_local(barrel.to_global(muzzle_local)) / Steering.ppu()

func update_ai(delta: float) -> void:
	sync_muzzle()
	super(delta)

# no barrel, no shots
func fire(pull_trigger: bool, direction: Vector2) -> void:
	super(pull_trigger and has_barrel(), direction)
