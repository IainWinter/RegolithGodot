extends CanvasLayer
class_name RasterView

# the low resolution pass the raster toggles draw through. a SubViewport that
# shares the root's World2D (same canvas, same nodes, nothing reparented) is
# sized so one world cell is one of its pixels, and a nearest filtered
# TextureRect on this layer blows it back up over the window. what the sub
# draws is picked with visibility layers: the tagged nodes get RASTER_LAYER,
# the sub culls to that layer only, and the root viewport stops drawing it,
# so a node is drawn exactly once. EFFECTS tags projectiles, trails,
# lightning and particles; WORLD tags every canvas item of the root viewport
# that is not under a CanvasLayer, so the UI stays native. nodes added later
# are tagged from the tree's node_added signal. the sub's canvas transform
# mirrors the root's (the Camera2D writes that) scaled to cells and snapped
# to whole pixels, so the RegolithCamera keeps working untouched. leaving the
# tree puts every layer and the root's cull mask back

enum Mode { EFFECTS, WORLD }

const GROUP := "raster_view"
# visibility layer bit the sub renders, bit 1, off by default everywhere
const RASTER_LAYER := 2
const DEFAULT_LAYER := 1
const TAG := "raster_tagged"
# the sub grows in steps of this many cells so a zoom ease does not
# reallocate the target every frame
const SIZE_STEP := 8
const MIN_SIZE := 8
const EFFECTS_LAYER := 1
const WORLD_LAYER := -1
const EFFECT_CLASSES: Array[StringName] = [
	&"Bullet", &"Missile", &"ForceBullet", &"LightningBolt", &"LightningBall",
	&"Trail", &"Lightning", &"ParticleEffect", &"ExplosionSequence", &"WarningLine",
]

var mode := Mode.EFFECTS
var sub: SubViewport
var display: TextureRect
var tagged: Array[int] = []
var saved_cull_mask := 0
# screen pixels per sub pixel this frame
var scale_by := 1.0

func _init(of_mode: Mode = Mode.EFFECTS) -> void:
	mode = of_mode
	name = "RasterView"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	layer = WORLD_LAYER if mode == Mode.WORLD else EFFECTS_LAYER
	add_to_group(GROUP)

func _enter_tree() -> void:
	var root := get_viewport()

	sub = SubViewport.new()
	sub.name = "Sub"
	sub.disable_3d = true
	sub.transparent_bg = mode == Mode.EFFECTS
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_cull_mask = RASTER_LAYER
	sub.snap_2d_transforms_to_pixel = true
	sub.gui_disable_input = true
	sub.handle_input_locally = false
	sub.size = Vector2i(MIN_SIZE, MIN_SIZE)
	# shared before entering the tree, the same canvas seen through a second viewport
	sub.world_2d = root.world_2d
	add_child(sub)

	display = TextureRect.new()
	display.name = "Display"
	display.texture = sub.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.position = Vector2.ZERO

	if mode == Mode.EFFECTS:
		# the sub holds premultiplied color over a clear background
		var blend := CanvasItemMaterial.new()
		blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		display.material = blend

	add_child(display)

	saved_cull_mask = root.canvas_cull_mask
	root.canvas_cull_mask = saved_cull_mask & ~RASTER_LAYER

	tag_tree(get_tree().root)
	get_tree().node_added.connect(on_node_added)

func _exit_tree() -> void:
	var tree := get_tree()

	if tree.node_added.is_connected(on_node_added):
		tree.node_added.disconnect(on_node_added)

	untag_all()
	get_viewport().canvas_cull_mask = saved_cull_mask

func _process(_delta: float) -> void:
	update_view()

# the sub follows the root's view: one cell per pixel, whole pixels only
func update_view() -> void:
	var root := get_viewport()
	var view_size := root.get_visible_rect().size
	var root_transform := root.canvas_transform
	var cell := RegolithWorld.pixels_per_cell()
	scale_by = maxf(root_transform.get_scale().y * cell, 1.0)

	var wanted := (view_size / scale_by).ceil()
	var stepped := Vector2i(step_up(int(wanted.x)), step_up(int(wanted.y)))

	if sub.size != stepped:
		sub.size = stepped

	var to_sub := Transform2D.IDENTITY.scaled(Vector2.ONE / scale_by) * root_transform
	to_sub.origin = to_sub.origin.round()
	sub.canvas_transform = to_sub

	display.size = Vector2(stepped) * scale_by

static func step_up(cells: int) -> int:
	return maxi(MIN_SIZE, int(ceil(float(cells) / SIZE_STEP)) * SIZE_STEP)

# tagging

func on_node_added(node: Node) -> void:
	if node is CanvasItem and wants(node):
		tag(node)

func tag_tree(node: Node) -> void:
	if node is CanvasItem and wants(node):
		tag(node)

	for child in node.get_children():
		tag_tree(child)

func tag(item: CanvasItem) -> void:
	if item.has_meta(TAG):
		return

	item.set_meta(TAG, item.visibility_layer)
	item.visibility_layer = RASTER_LAYER
	tagged.append(item.get_instance_id())

func untag_all() -> void:
	for id in tagged:
		var item := instance_from_id(id) as CanvasItem

		if item != null and item.has_meta(TAG):
			item.visibility_layer = item.get_meta(TAG)
			item.remove_meta(TAG)

	tagged.clear()

func is_tagged(item: CanvasItem) -> bool:
	return item.has_meta(TAG)

func tagged_count() -> int:
	var count := 0

	for id in tagged:
		if instance_from_id(id) != null:
			count += 1

	return count

# whether item draws through the sub in this mode
func wants(item: CanvasItem) -> bool:
	if not in_world_canvas(item):
		return false

	if mode == Mode.WORLD:
		return true

	var node: Node = item

	while node != null and not (node is CanvasLayer) and not (node is Viewport):
		if RasterView.is_effect(node) or (node is CanvasItem and node.has_meta(TAG)):
			return true

		node = node.get_parent()

	return false

# an item on the root viewport's own canvas, not on a CanvasLayer (the UI)
func in_world_canvas(item: CanvasItem) -> bool:
	var node := item.get_parent()

	while node != null:
		if node is CanvasLayer:
			return false

		if node is Viewport:
			return node == get_viewport()

		node = node.get_parent()

	return false

# the projectiles and the effects they leave, the "bullets / effects" set.
# matched on script class names up the inheritance chain so this node never
# depends on the weapon scripts parsing, plus the projectile group for nodes
# already in the tree and every particle node
static func is_effect(node: Node) -> bool:
	if node is GPUParticles2D or node.is_in_group("projectile"):
		return true

	var script := node.get_script() as Script

	while script != null:
		if script.get_global_name() in EFFECT_CLASSES:
			return true

		script = script.get_base_script()

	return false
