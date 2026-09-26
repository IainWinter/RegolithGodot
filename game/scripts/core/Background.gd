extends Node2D
class_name Background

# a star and dust field that follows the camera. each depth layer is one
# MultiMeshInstance2D slid by its parallax factor, and its items live in a
# grid of cells around the camera's view in that layer's space: cells that
# enter the padded view are generated from a hash of their coordinates and
# the seed, cells that leave it are dropped, so scrolling back shows the same
# sky and the item count stays bounded. an item is uploaded while its own
# bounds (its half size turned to its widest, plus its drift) touch the view
# grown by the margin, never by which cell it sits in, so a wash wider than
# the screen cannot pop while any of it shows. sizes and densities are in
# sim units like the original SpaceBackgroundRenderSystem: 4000 stars and
# 40 dust clouds over 128 x 72 units, stars 0.001..0.01 units, dust 10..20
# units, parallax 2 / depth for stars and 0.5 / depth for dust. a near cloud
# layer with screen sized clouds is added on top so cloud shapes read, and
# clouds wander slowly around their spot

@export var star_texture: Texture2D
@export var dust_texture: Texture2D
@export var space_color := Color(0.02, 0.02, 0.04, 1.0)
@export var seed := 7

@export_group("Density")
# multiplies every layer, 1.0 is the original's field
@export_range(0.0, 10.0, 0.05) var density := 1.5
# items per square unit summed over a kind's depth layers. the dust washes
# are the original's screen filling clouds, the clouds are the near layer
@export var star_density := 0.434
@export var dust_density := 0.00434
@export var cloud_density := 0.02
@export var cloud_alpha := 0.35

@export_group("Layers")
@export_range(1, 16) var star_layers := 6
@export_range(1, 16) var dust_layers := 4
@export_range(1, 16) var cloud_layers := 2

@export_group("Drift")
# how far a cloud wanders from its spot, in units, and how long a wander takes
@export var drift_amplitude := 1.0
@export var drift_period := 45.0
# extra field around the view, in units, an item is kept uploaded in once
# its bounds reach it, so a pan never shows a bare edge
@export var window_margin := 2.0

# smallest half size a star quad is drawn at, in world pixels
const MIN_STAR_HALF_PIXELS := 0.75
# a quad of half size h turned to 45 degrees reaches h * sqrt(2) from its center
const ROTATION_REACH := 1.4142135623730951
# floats per multimesh instance: a 2d transform (8) and a color (4)
const FLOATS_PER_INSTANCE := 12
# instances kept spare when a layer's buffer grows, so entering items rarely
# reallocate it
const SPARE_INSTANCES := 8

var layers: Array[FieldLayer] = []
var time := 0.0
var view_center := Vector2.ZERO
var view_extents := Vector2.ZERO
# the process frame the layers were last uploaded in, one upload per frame
var uploaded_frame := -1

# one depth layer: a cell grid in this layer's parallax space feeding a
# multimesh. an item is [position, half size, angle, color, drift phase,
# spin], positions and sizes in world pixels. the multimesh keeps a buffer
# of capacity instances that only grows, the live items fill its front and
# visible_instance_count says how many draw, so no frame sees an empty or
# half written buffer
class FieldLayer:
	var kind: String
	var parallax: float
	var density: float
	var cell_size: float
	# how far past its resting position an item of this layer can reach:
	# the largest half size turned to its widest, plus its drift
	var reach: float
	# how far outside the view an item stays uploaded
	var margin: float
	var half_min: float
	var half_max: float
	var half_floor: float
	var drifts: bool
	var drift_amplitude: float
	var drift_period: float
	var pick_color: Callable
	var seed: int
	var instance: MultiMeshInstance2D
	var window := Rect2i()
	var cells := {}
	# the uploaded items by id, Vector3i(cell x, cell y, index in cell), in
	# buffer order. a fresh dictionary every update, so a reference taken
	# earlier stays a snapshot
	var live := {}
	var live_ids: Array = []
	var view := Rect2()
	var capacity := 0
	var upload_count := 0

	# the camera's view in this layer's space: the layer slides by parallax
	# of the camera, so its own view center is what is left over
	func view_rect(center: Vector2, extents: Vector2) -> Rect2:
		var local := center * (1.0 - parallax)
		return Rect2(local - extents, extents * 2.0)

	# an item whose bounds touch this rect is uploaded
	func keep_rect() -> Rect2:
		return view.grow(margin)

	# every item that could touch the keep rect rests inside this, so the
	# cells covering it are the ones generated
	func padded_view() -> Rect2:
		return view.grow(margin + reach)

	func cell_range(rect: Rect2) -> Rect2i:
		var lo := Vector2i((rect.position / cell_size).floor())
		var hi := Vector2i((rect.end / cell_size).floor())
		return Rect2i(lo, hi - lo + Vector2i.ONE)

	func window_rect() -> Rect2:
		return Rect2(Vector2(window.position) * cell_size, Vector2(window.size) * cell_size)

	# how far an item's quad can reach from its resting position at any
	# angle and drift
	func item_reach(item: Array) -> float:
		return item[1] * Background.ROTATION_REACH + drift_amplitude

	# the rect an item's quad stays inside whatever its angle and drift
	func item_aabb(item: Array) -> Rect2:
		var r := item_reach(item)
		return Rect2(item[0] - Vector2.ONE * r, Vector2.ONE * (2.0 * r))

	func update(center: Vector2, extents: Vector2, now: float) -> bool:
		instance.position = center * parallax
		view = view_rect(center, extents)
		var wanted := cell_range(padded_view())
		var window_changed := wanted != window

		if window_changed:
			for key in cells.keys():
				if not wanted.has_point(key):
					cells.erase(key)

			for y in range(wanted.position.y, wanted.end.y):
				for x in range(wanted.position.x, wanted.end.x):
					var key := Vector2i(x, y)

					if not cells.has(key):
						cells[key] = make_cell(key)

			window = wanted

			# the canvas item is culled by this rect, in the instance's own
			# space like the buffer, so it spans every cell and their reach
			var bounds := window_rect().grow(reach)
			instance.multimesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, -1.0), Vector3(bounds.size.x, bounds.size.y, 2.0))

		# the live set is a pure function of the view: an item is in it while
		# its bounds touch the keep rect. cells go in sorted so the draw
		# order, and with it how overlapping washes blend, does not depend
		# on the direction the camera came from
		var keep := keep_rect()
		var next := {}
		var keys := cells.keys()
		keys.sort()

		for key in keys:
			var items: Array = cells[key]

			for i in items.size():
				var item: Array = items[i]

				if keep.grow(item_reach(item)).has_point(item[0]):
					next[Vector3i(key.x, key.y, i)] = item

		var ids := next.keys()
		var set_changed := ids != live_ids
		live = next
		live_ids = ids

		if set_changed or drifts:
			upload(now)

		return set_changed

	func make_cell(key: Vector2i) -> Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(key.x, key.y, seed))

		var expected := density * cell_size * cell_size
		var count := int(floor(expected))

		if rng.randf() < expected - float(count):
			count += 1

		var origin := Vector2(key) * cell_size
		var items := []

		for i in count:
			var position := origin + Vector2(rng.randf(), rng.randf()) * cell_size
			var half := maxf(rng.randf_range(half_min, half_max), half_floor)
			var angle := rng.randf_range(0.0, TAU)
			var color: Color = pick_color.call(rng)
			var phase := Vector2(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
			var spin := rng.randf_range(-1.0, 1.0)
			items.append([position, half, angle, color, phase, spin])

		return items

	# writes the live items to the front of the buffer. the buffer only
	# grows, and grows before it is filled, so instance_count never drops
	# under the drawn items and the draw count moves once the data is in
	func upload(now: float) -> void:
		var multimesh := instance.multimesh
		var count := live_ids.size()

		if count > capacity:
			capacity = count + count / 2 + SPARE_INSTANCES
			multimesh.instance_count = capacity

		if capacity == 0:
			return

		var buffer := PackedFloat32Array()
		buffer.resize(capacity * FLOATS_PER_INSTANCE)
		var w := TAU * now / drift_period if drifts else 0.0
		var i := 0

		for id in live_ids:
			var item: Array = live[id]
			var position: Vector2 = item[0]
			var angle: float = item[2]

			if drifts:
				var phase: Vector2 = item[4]
				position += Vector2(sin(w + phase.x), cos(w * 0.7 + phase.y)) * drift_amplitude
				angle += w * item[5] * 0.1

			var t := Transform2D(angle, Vector2.ONE * item[1], 0.0, position)
			var color: Color = item[3]
			buffer[i] = t.x.x
			buffer[i + 1] = t.y.x
			buffer[i + 2] = 0.0
			buffer[i + 3] = t.origin.x
			buffer[i + 4] = t.x.y
			buffer[i + 5] = t.y.y
			buffer[i + 6] = 0.0
			buffer[i + 7] = t.origin.y
			buffer[i + 8] = color.r
			buffer[i + 9] = color.g
			buffer[i + 10] = color.b
			buffer[i + 11] = color.a
			i += FLOATS_PER_INSTANCE

		multimesh.buffer = buffer
		multimesh.visible_instance_count = count
		# the canvas item recomputes its cull rect from the custom aabb on redraw
		instance.queue_redraw()
		upload_count += 1

	# the uploaded items
	func item_count() -> int:
		return live_ids.size()

	# resting positions of the generated items inside a layer space rect,
	# sorted so the same sky compares equal whatever order its cells came
	# back in
	func items_in_rect(rect: Rect2) -> PackedVector2Array:
		var found := PackedVector2Array()

		for key in cells:
			for item in cells[key]:
				if rect.has_point(item[0]):
					found.append(item[0])

		found.sort()
		return found

func _ready() -> void:
	z_index = -100
	z_as_relative = false
	# the layers are placed every frame in _process, so the renderer must not
	# interpolate them between physics ticks or they wobble under the camera
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	add_kind("Dust", dust_texture, dust_layers, dust_density, 0.5, 4.0, 10.0, 20.0, 0.0, 32.0, true, pick_dust_color)
	add_kind("Star", star_texture, star_layers, star_density, 2.0, 3.0, 0.001, 0.01, MIN_STAR_HALF_PIXELS, 8.0, false, pick_star_color)
	add_kind("Cloud", dust_texture, cloud_layers, cloud_density, 0.5, 2.0, 1.5, 4.0, 0.0, 16.0, true, pick_cloud_color)

	refresh()

# depth layers of one kind. the field density is items per square unit over
# all the kind's layers, half sizes are in units, the half floor in world
# pixels, cell size in units. depth runs base_depth .. base_depth + 10 like
# the original and the parallax is factor / depth
func add_kind(kind: String, texture: Texture2D, count: int, field_density: float, factor: float, base_depth: float, half_min: float, half_max: float, half_floor: float, cell_units: float, drifts: bool, pick_color: Callable) -> void:
	var ppu := RegolithWorld.pixels_per_unit()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)

	for i in count:
		var layer := FieldLayer.new()
		layer.kind = kind
		layer.parallax = factor / (base_depth + (float(i) + 0.5) / float(count) * 10.0)
		layer.density = density * field_density / float(count) / (ppu * ppu)
		layer.cell_size = cell_units * ppu
		layer.half_min = half_min * ppu
		layer.half_max = half_max * ppu
		layer.half_floor = half_floor
		layer.drifts = drifts
		layer.drift_amplitude = drift_amplitude * ppu if drifts else 0.0
		layer.drift_period = maxf(drift_period, 0.01)
		layer.reach = maxf(layer.half_max, half_floor) * ROTATION_REACH + layer.drift_amplitude
		layer.margin = window_margin * ppu
		layer.pick_color = pick_color
		layer.seed = hash(Vector2i(seed, layers.size()))

		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_colors = true
		multimesh.mesh = mesh

		var instance := MultiMeshInstance2D.new()
		instance.name = "%s%d" % [kind, i]
		instance.multimesh = multimesh
		instance.texture = texture
		add_child(instance)

		layer.instance = instance
		layers.append(layer)

func pick_dust_color(rng: RandomNumberGenerator) -> Color:
	return Color8(100, rng.randi_range(0, 200), 200, 100)

func pick_star_color(rng: RandomNumberGenerator) -> Color:
	return Color8(rng.randi_range(64, 128), 140, 140, 255)

func pick_cloud_color(rng: RandomNumberGenerator) -> Color:
	var color := Color8(100, rng.randi_range(0, 200), 200, 255)
	color.a = cloud_alpha
	return color

func layers_of(kind: String) -> Array[FieldLayer]:
	var found: Array[FieldLayer] = []

	for layer in layers:
		if layer.kind == kind:
			found.append(layer)

	return found

# the camera's view in world pixels as [center, half extents]
func camera_view() -> Array:
	var camera := get_viewport().get_camera_2d()
	var extents := get_viewport_rect().size * 0.5

	if camera == null:
		return [Vector2.ZERO, extents]

	return [camera.get_screen_center_position(), extents / camera.zoom]

# slides every layer under the camera and uploads the items its view now
# reaches, once per process frame
func refresh() -> void:
	var frame := Engine.get_process_frames()

	if frame == uploaded_frame:
		return

	uploaded_frame = frame
	var view := camera_view()
	view_center = view[0]
	view_extents = view[1]

	for layer in layers:
		layer.update(view_center, view_extents, time)

func _process(delta: float) -> void:
	time += delta
	refresh()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(to_local(view_center) - view_extents, view_extents * 2.0), space_color)
