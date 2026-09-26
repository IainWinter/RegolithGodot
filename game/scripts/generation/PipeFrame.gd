@tool
extends TextureRect
class_name PipeFrame

# a TextureRect whose texture is a generated pipe plate, strip or menu border
# (PipeGenerator). the node's own rect is the zone the pipes generate inside:
# drag the Control handles in the 2D editor and the texture regenerates to
# the new size. every exported property regenerates too. changes made in one
# frame collapse into a single generate, and while the mouse is held in the
# editor (a handle drag, a slider, a paint stroke) the generate waits for the
# release. the texture is not saved with the scene, it is rebuilt from the
# parameters and the layout, so scenes stay small.
#
# modes: PLATE is the plain generator over the zone, the STRIP modes generate
# the zone as one edge of a border (seeded like PipeGenerator.make_border, the
# bottom and right ones flipped like PipeBorderUI drew them) and BORDER
# composes a hollow frame of the zone with `thickness`.
#
# flow biases the WFC runs along an axis. placement (Control already owns
# the name layout_mode): AUTO is plain WFC,
# MANUAL renders only the cells painted into `layout` (a PipeLayout on a
# lattice of `cell_size` pixels over the zone, two layers back/front, drawn
# in the 2D editor by the Regolith Pipes plugin), MIXED keeps the painted
# cells and WFC fills the rest of that lattice. in the STRIP and BORDER modes
# the painted cells draw over the strips, MIXED there is the same as MANUAL

signal regenerated

enum Mode { PLATE, STRIP_TOP, STRIP_BOTTOM, STRIP_LEFT, STRIP_RIGHT, BORDER }
enum LayoutMode { AUTO, MANUAL, MIXED }

# the styles the hand layout's layers render with, back then front
const LAYOUT_STYLES := [PipeGenerator.LAYERS[2], PipeGenerator.LAYERS[4]]
const DEFAULT_SIZE := Vector2(320, 180)
# frames the editor waits for a held mouse before generating anyway
const DRAG_WAIT_FRAMES := 240

@export var mode := Mode.BORDER:
	set(value):
		mode = value
		_queue_regenerate()

@export var flow: PipeGenerator.Flow = PipeGenerator.Flow.AUTO:
	set(value):
		flow = value
		_queue_regenerate()

@export var placement := LayoutMode.AUTO:
	set(value):
		placement = value
		_queue_regenerate()

@export_range(4, 128) var thickness := PipeGenerator.MENU_THICKNESS:
	set(value):
		thickness = value
		_queue_regenerate()

@export var seed := PipeGenerator.MENU_SEED:
	set(value):
		seed = value
		_queue_regenerate()

@export_group("Layout")
@export_range(4, 64) var cell_size := 12:
	set(value):
		cell_size = maxi(value, 1)
		_queue_regenerate()

@export var layout: PipeLayout:
	set(value):
		if layout != null and layout.changed.is_connected(_on_layout_changed):
			layout.changed.disconnect(_on_layout_changed)

		layout = value
		if layout != null:
			layout.changed.connect(_on_layout_changed)

		_queue_regenerate()

@export_group("Light")
@export var light_dir := Vector3(-0.62, -0.66, 0.42):
	set(value):
		light_dir = value
		_queue_regenerate()

@export var sun := Color.WHITE:
	set(value):
		sun = value
		_queue_regenerate()

@export var normal_map := false:
	set(value):
		normal_map = value
		_queue_regenerate()

@export_group("Wear")
@export_range(0.0, 1.0) var erosion := PipeGenerator.MENU_EROSION:
	set(value):
		erosion = value
		_queue_regenerate()

@export_range(0.0, 2.0) var rust := PipeGenerator.MENU_RUST:
	set(value):
		rust = value
		_queue_regenerate()

@export_group("Tuning")
@export_range(0.2, 2.0) var radius_scale: float = PipeGenerator.MENU_TUNING["radius"]:
	set(value):
		radius_scale = value
		_queue_regenerate()

@export_range(0.0, 4.0) var empty_scale: float = PipeGenerator.MENU_TUNING["empty"]:
	set(value):
		empty_scale = value
		_queue_regenerate()

@export_range(0.0, 4.0) var run_scale: float = PipeGenerator.MENU_TUNING["run"]:
	set(value):
		run_scale = value
		_queue_regenerate()

@export_range(0.0, 8.0) var brass_scale: float = PipeGenerator.MENU_TUNING["brass"]:
	set(value):
		brass_scale = value
		_queue_regenerate()

@export_group("")
@export_tool_button("Regenerate") var regenerate_action: Callable = regenerate

# milliseconds the last generate took, for the report
var last_generate_ms := 0.0
var _pending := false
var _wait_frames := 0
var _generating := false

func _init() -> void:
	# the texture is always the zone's size, so the rect must be free to
	# shrink below it and the picture draws 1:1
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if size == Vector2.ZERO:
		size = DEFAULT_SIZE

func _validate_property(property: Dictionary) -> void:
	if property.name == "texture":
		property.usage &= ~PROPERTY_USAGE_STORAGE

func _ready() -> void:
	set_process(false)
	regenerate()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_queue_regenerate()

# --- the zone ------------------------------------------------------------

# the generation area in pixels, the node's rect
func zone_size() -> Vector2i:
	return Vector2i(maxi(roundi(size.x), 1), maxi(roundi(size.y), 1))

# layout cells across and down the zone, the last column/row may hang over
func grid_size() -> Vector2i:
	var zone := zone_size()
	return Vector2i(ceili(float(zone.x) / cell_size), ceili(float(zone.y) / cell_size))

# the layout cell under a point in the node's local pixels, or (-1, -1)
func cell_at(local: Vector2) -> Vector2i:
	var zone := zone_size()
	if local.x < 0.0 or local.y < 0.0 or local.x >= zone.x or local.y >= zone.y:
		return Vector2i(-1, -1)

	return Vector2i(int(local.x / cell_size), int(local.y / cell_size))

func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * cell_size, Vector2(cell_size, cell_size))

# the layout, created and fitted to the current lattice on demand
func ensure_layout() -> PipeLayout:
	if layout == null:
		layout = PipeLayout.new()

	var g := grid_size()
	layout.resize(g.x, g.y, LAYOUT_STYLES.size())
	return layout

func has_painted_cells() -> bool:
	return layout != null and not layout.is_empty() and layout.painted_count() > 0

# --- generation -------------------------------------------------------------

func make_generator() -> PipeGenerator:
	var gen := PipeGenerator.new()
	gen.seed = seed
	gen.flow = flow
	gen.light = light_dir
	gen.sun = sun
	gen.erosion = erosion
	gen.rust = rust
	gen.normals = normal_map
	gen.tuning["radius"] = radius_scale
	gen.tuning["empty"] = empty_scale
	gen.tuning["run"] = run_scale
	gen.tuning["brass"] = brass_scale
	return gen

# the hand layout as generator layer dicts on the zone lattice, back first.
# fill marks them for WFC around the painted cells (MIXED)
func layout_layers(fill: bool) -> Array:
	var lay := ensure_layout()
	var g := grid_size()
	var out := []
	for i in lay.layer_count:
		var layer := PipeGenerator.uniform_layer(lay.layer_grid(i), g.x, g.y, float(cell_size),
			LAYOUT_STYLES[mini(i, LAYOUT_STYLES.size() - 1)], Vector2.ZERO, lay.layer_sizes(i))
		layer["fill"] = fill
		out.append(layer)

	return out

# WFC the free cells of one layout layer and bake the result into the layout
# as painted cells, the old editor's fill. the next regenerate draws them
func auto_fill(layer: int) -> void:
	var lay := ensure_layout()
	var g := grid_size()
	var gen := make_generator()
	var style: Dictionary = LAYOUT_STYLES[mini(layer, LAYOUT_STYLES.size() - 1)]
	lay.apply_grid(layer, gen.fill_grid(lay.layer_grid(layer), g.x, g.y, style, layer))

func generate_image() -> Image:
	var zone := zone_size()
	var gen := make_generator()
	match mode:
		Mode.PLATE:
			gen.width = zone.x
			gen.height = zone.y
			if placement != LayoutMode.AUTO:
				gen.layout = layout_layers(placement == LayoutMode.MIXED)
			return gen.generate()
		Mode.STRIP_TOP, Mode.STRIP_BOTTOM, Mode.STRIP_LEFT, Mode.STRIP_RIGHT:
			gen.width = zone.x
			gen.height = zone.y
			gen.seed = PipeGenerator.strip_seed(seed, zone.x, zone.y)
			var image := gen.generate()
			if mode == Mode.STRIP_BOTTOM or mode == Mode.STRIP_RIGHT:
				image.flip_x()
				image.flip_y()
			return _overlay_layout(image)

	var t := clampi(thickness, 1, mini(zone.x, zone.y))
	return _overlay_layout(gen.make_border(zone, t))

# strips and borders draw the painted cells over the WFC picture
func _overlay_layout(image: Image) -> Image:
	if placement == LayoutMode.AUTO or not has_painted_cells():
		return image

	var zone := zone_size()
	var gen := make_generator()
	gen.width = zone.x
	gen.height = zone.y
	gen.layout = layout_layers(false)
	image.blend_rect(gen.generate(), Rect2i(Vector2i.ZERO, zone), Vector2i.ZERO)
	return image

func regenerate() -> void:
	_pending = false
	_wait_frames = 0
	set_process(false)
	var start := Time.get_ticks_usec()
	# fitting the layout to the lattice inside generate_image must not queue
	# another generate
	_generating = true
	var image := generate_image()
	_generating = false
	last_generate_ms = (Time.get_ticks_usec() - start) / 1000.0
	texture = ImageTexture.create_from_image(image)
	regenerated.emit()

# regenerate once, at the end of the frame, or after the mouse is released
# when it is being held in the editor
func queue_regenerate() -> void:
	_queue_regenerate()

func _queue_regenerate() -> void:
	if _pending or _generating or not is_inside_tree():
		return

	_pending = true
	_regenerate_deferred.call_deferred()

func _regenerate_deferred() -> void:
	if not _pending:
		return

	if _mouse_held():
		_wait_frames = 0
		set_process(true)
		return

	regenerate()

# polling while the mouse is held, so a drag ends with one generate
func _process(_delta: float) -> void:
	if not _pending:
		set_process(false)
		return

	_wait_frames += 1
	if _mouse_held() and _wait_frames < DRAG_WAIT_FRAMES:
		return

	regenerate()

func _mouse_held() -> bool:
	return Engine.is_editor_hint() and (Controls.held(Controls.PIPES_PAINT) or Controls.held(Controls.PIPES_ERASE))

func _on_layout_changed() -> void:
	_queue_regenerate()
