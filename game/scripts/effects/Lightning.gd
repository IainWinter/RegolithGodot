extends Node2D
class_name Lightning

# port of the engine's LightningEffect. a strike is a fractal channel from
# begin to end with forked branches: it is revealed from begin at the reveal
# speed, flashed whole for a moment, then only the channel is kept and faded
# out over the lifetime. a strike at a node or a sprite cell tracks it and is
# sustained with restrikes for as long as strike() keeps being called for
# that target. the cells the channel crosses are burned when it lands.
# drawn like the ropes: one multimesh instance per segment, endpoints in
# world cell space, the shader fills whole cells. positions are world pixels

const TRACKING_KEEPALIVE := 0.25
const FLASH_TIME := 0.07
const RESTRIKE_TIME := 0.05
const MAX_BRANCH_DEPTH := 2
const FLOATS_PER_INSTANCE := 16
const MIN_CAPACITY := 16
const SHRINK_FRAMES := 120
const POOL_LIMIT := 256

class Bolt:
	var path := PackedVector2Array()
	var cum := PackedFloat32Array()
	var fork_distance := 0.0
	var parent := -1
	var fork_index := 0
	var is_channel := false
	var is_root := false
	var brightness := 1.0
	var spark_emitted := 0.0

class Strike:
	var props: LightningProps
	var begin := Vector2.ZERO
	var end := Vector2.ZERO
	var end_offset := Vector2.ZERO
	var start_tan := 0.0
	var bias_tan := 0.0
	var target: LightningTarget
	var local_node: Node2D
	var exclude: RegolithSprite
	var bolts: Array[Bolt] = []
	var aim_end := Vector2.ZERO
	var front := 0.0
	var channel_len := 0.0
	var reveal_speed := 1.0
	var struck := false
	var flash_timer := 0.0
	var life := 0.0
	var age := 0.0
	var keepalive := 0.0
	var sustaining := false
	var restrike := 0.0

	func is_fading() -> bool:
		return struck and flash_timer <= 0.0 and not sustaining

class PathGen:
	var generations := 2
	var offset := 0.0
	var split_chance := 0.0
	var branch_len := 0.0
	var head_takeover := 0.0
	var bolts: Array[Bolt]

@export var props: LightningProps

@export var auto_free := true

signal hit(sprite: RegolithSprite, cell: Vector2i, position: Vector2)
signal finished

var strikes: Array[Strike] = []
var multimesh: MultiMesh
var instance: MultiMeshInstance2D
var buffer := PackedFloat32Array()
var capacity := 0
var segment_count := 0
var idle_frames := 0
var struck_any := false
var warned_material := false

var cell := 1.0
var bounds_min := Vector2.ZERO
var bounds_max := Vector2.ZERO

var segment_mesh: ArrayMesh
var free_strikes: Array[Strike] = []
var free_bolts: Array[Bolt] = []

func _init() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _ready() -> void:
	transform = Transform2D.IDENTITY

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = segment_quad()

	instance = MultiMeshInstance2D.new()
	instance.multimesh = multimesh
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(instance)

static func attach(parent: Node, strike_props: LightningProps, draw_material: Material, free_when_done := false) -> Lightning:
	var lightning := Lightning.new()
	lightning.props = strike_props
	lightning.material = draw_material
	lightning.auto_free = free_when_done
	parent.add_child(lightning)
	return lightning

func segment_quad() -> ArrayMesh:
	if segment_mesh != null:
		return segment_mesh

	var quad := PackedVector2Array([
		Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1),
		Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1),
	])
	var ends := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 0),
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 0),
	])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = quad
	arrays[Mesh.ARRAY_TEX_UV] = ends

	segment_mesh = ArrayMesh.new()
	segment_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return segment_mesh

func strike(from, to, exclude: RegolithSprite = null, strike_props: LightningProps = null, local_node: Node2D = null) -> void:
	var use_props := strike_props if strike_props != null else props

	if use_props == null:
		push_warning("Lightning: no props, nothing to strike with")
		return

	var from_target := LightningTarget.make(from)
	var to_target := LightningTarget.make(to)

	if from_target == null or to_target == null:
		return

	var begin = from_target.position()
	var end = to_target.position()

	if begin == null or end == null:
		return

	var tracked: LightningTarget = to_target if to_target.tracks() and local_node == null else null

	if tracked != null:
		for existing in strikes:
			if existing.target != null and existing.target.equals(tracked):
				var keep_end := existing.end
				fill_spawn(existing, use_props, begin, end)
				existing.end = keep_end
				existing.keepalive = 0.0
				return

	var s := take_strike()
	fill_spawn(s, use_props, begin, end)
	s.target = tracked
	s.local_node = local_node
	s.exclude = exclude
	generate(s)
	strikes.append(s)
	struck_any = true

func get_strike_count() -> int:
	return strikes.size()

func get_segment_count() -> int:
	return segment_count

func take_strike() -> Strike:
	return free_strikes.pop_back() if not free_strikes.is_empty() else Strike.new()

func take_bolt() -> Bolt:
	return free_bolts.pop_back() if not free_bolts.is_empty() else Bolt.new()

func recycle_bolts(bolts: Array[Bolt]) -> void:
	for bolt in bolts:
		if free_bolts.size() < POOL_LIMIT:
			free_bolts.append(bolt)

	bolts.clear()

func recycle_strike(s: Strike) -> void:
	recycle_bolts(s.bolts)
	s.target = null
	s.local_node = null
	s.exclude = null
	s.keepalive = 0.0

	if free_strikes.size() < POOL_LIMIT:
		free_strikes.append(s)

func fill_spawn(s: Strike, p: LightningProps, begin: Vector2, end: Vector2) -> void:
	var pixels_per_unit := RegolithWorld.pixels_per_unit()
	var angle := (end - begin).angle() if end != begin else 0.0

	s.props = p
	s.end_offset = p.end_offset.rotated(angle) * pixels_per_unit
	s.begin = begin + p.begin_offset.rotated(angle) * pixels_per_unit
	s.end = end + s.end_offset
	s.start_tan = tan(randf_range(p.start_angle_min, p.start_angle_max))
	s.bias_tan = tan(randf_range(p.bias_angle_min, p.bias_angle_max))

func to_world(s: Strike, point: Vector2) -> Vector2:
	if s.local_node != null:
		return s.local_node.global_transform * point
	return point

func fractalize(gen: PathGen, a: Vector2, b: Vector2, depth: int, seeds: Array) -> PackedVector2Array:
	var pts := PackedVector2Array([a, b])
	var shrink := pow(0.6, depth)
	var off := gen.offset * shrink
	var branch_len := gen.branch_len * shrink

	for g in maxi(1, gen.generations - 2 * depth):
		var next := PackedVector2Array()

		for i in pts.size() - 1:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var dir := p1 - p0
			var len := dir.length()
			var perp := Vector2(-dir.y, dir.x) / len if len > 1e-6 else Vector2(0.0, 1.0)
			var mid := (p0 + p1) * 0.5 + perp * randf_range(-off, off)

			next.append(p0)
			next.append(mid)

			if depth < MAX_BRANCH_DEPTH and g >= 1 and randf() < gen.split_chance:
				var bdir := mid - p0
				var bl := bdir.length()

				if bl > 1e-5:
					var n := bdir / bl
					var ang := randf_range(-0.7, 0.7)
					var bend := mid + n.rotated(ang) * (branch_len * randf_range(0.4, 1.0))
					seeds.append({"a": mid, "b": bend, "depth": depth + 1})

		next.append(pts[pts.size() - 1])
		pts = next
		off *= 0.5

	return pts

static func cumulative(path: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(path.size())
	cum[0] = 0.0

	for i in range(1, path.size()):
		cum[i] = cum[i - 1] + path[i - 1].distance_to(path[i])

	return cum

func build_paths(gen: PathGen, a: Vector2, b: Vector2, depth: int, parent := -1, fork_index := 0, fork_distance := 0.0, brightness := 1.0, takeover := false) -> void:
	var seeds := []
	var pts := fractalize(gen, a, b, depth, seeds)

	var bolt := take_bolt()
	bolt.path = pts
	bolt.cum = cumulative(pts)
	bolt.fork_distance = fork_distance
	bolt.parent = parent
	bolt.fork_index = fork_index
	bolt.is_channel = depth == 0 or takeover
	bolt.is_root = depth == 0
	bolt.brightness = brightness
	bolt.spark_emitted = 0.0

	var my_index := gen.bolts.size()
	gen.bolts.append(bolt)

	for branch_seed in seeds:
		var seed_a: Vector2 = branch_seed["a"]
		var best := INF
		var bi := 0

		for i in pts.size():
			var d := pts[i].distance_to(seed_a)

			if d < best:
				best = d
				bi = i

		var child_takeover := depth == 0 and randf() < gen.head_takeover
		var child_brightness := 1.0 if child_takeover else brightness * 0.55
		build_paths(gen, seed_a, branch_seed["b"], branch_seed["depth"], my_index, bi, fork_distance + bolt.cum[bi], child_brightness, child_takeover)

static func warp_point(p: Vector2, begin: Vector2, forward: Vector2, side: Vector2, len: float, start_tan: float, bias_tan: float) -> Vector2:
	var u := clampf((p - begin).dot(forward), 0.0, len)
	var r := u / len if len > 1e-5 else 0.0
	var bow := bias_tan * u * (1.0 - r)
	var launch := start_tan * u * (1.0 - r) * (1.0 - r)

	return p + side * (bow + launch)

func generate(s: Strike) -> void:
	var p := s.props

	recycle_bolts(s.bolts)
	s.front = 0.0
	s.struck = false
	s.flash_timer = 0.0
	s.life = 0.0
	s.age = 0.0
	s.sustaining = false
	s.restrike = 0.0

	var total_len := maxf(1e-4, s.begin.distance_to(s.end))
	var gen := PathGen.new()
	gen.generations = clampi(roundi(log(float(maxi(2, p.point_count))) / log(2.0)), 2, 7)
	gen.offset = p.jitter_step_size * total_len * 0.04
	gen.split_chance = clampf(p.expected_splits_per_bolt * 0.18, 0.0, 0.95)
	gen.branch_len = p.branch_scale * total_len
	gen.head_takeover = p.head_takeover_chance
	gen.bolts = s.bolts

	build_paths(gen, s.begin, s.end, 0)

	if s.start_tan != 0.0 or s.bias_tan != 0.0:
		var d := s.end - s.begin
		var len := d.length()

		if len > 1e-5:
			var forward := d / len
			var side := Vector2(-forward.y, forward.x)

			for bolt in s.bolts:
				var path := bolt.path

				for i in path.size():
					path[i] = warp_point(path[i], s.begin, forward, side, len, s.start_tan, s.bias_tan)

				bolt.path = path
				bolt.cum = cumulative(path)

	s.channel_len = total_len if s.bolts.is_empty() else s.bolts[0].cum[s.bolts[0].cum.size() - 1]
	s.reveal_speed = maxf(0.001, p.speed * RegolithWorld.pixels_per_unit())
	s.aim_end = s.end

	burn_path(s)

func burn_path(s: Strike) -> void:
	var p := s.props

	if (p.burn_strength <= 0 and p.burn_damage <= 0) or s.bolts.is_empty():
		return

	var world := RegolithWorld.active()

	if world == null:
		return

	var path := s.bolts[0].path
	var points := PackedVector2Array()
	points.resize(path.size())
	var bounds := Rect2(to_world(s, path[0]), Vector2.ZERO)

	for i in path.size():
		points[i] = to_world(s, path[i])
		bounds = bounds.expand(points[i])

	for found in world.query_rect(bounds):
		var sprite: RegolithSprite = found

		if sprite == s.exclude:
			continue

		var burned := {}

		for i in range(1, points.size()):
			for c in sprite.trace_cells(points[i - 1], points[i], 64):
				var cell_index: Vector2i = c
				var key := cell_index.y * 65536 + cell_index.x

				if burned.has(key):
					continue

				burned[key] = true
				var cell_position: Vector2 = sprite.cell_to_world(cell_index)
				sprite.burn_cell(cell_index, p.burn_strength, p.burn_damage)
				hit.emit(sprite, cell_index, cell_position)

static func point_at_distance(bolt: Bolt, d: float) -> Vector2:
	var cum := bolt.cum

	if d <= 0.0 or cum.size() < 2:
		return bolt.path[0]

	if d >= cum[cum.size() - 1]:
		return bolt.path[bolt.path.size() - 1]

	for i in range(1, cum.size()):
		if cum[i] >= d:
			var seg := cum[i] - cum[i - 1]
			var t := (d - cum[i - 1]) / seg if seg > 1e-6 else 0.0
			return bolt.path[i - 1].lerp(bolt.path[i], t)

	return bolt.path[bolt.path.size() - 1]

func _process(delta: float) -> void:
	var world := RegolithWorld.active()

	for i in range(strikes.size() - 1, -1, -1):
		if update_strike(strikes[i], delta, world):
			recycle_strike(strikes[i])
			strikes.remove_at(i)

	draw_strikes()

	if struck_any and strikes.is_empty():
		struck_any = false
		finished.emit()

		if auto_free:
			queue_free()

func update_strike(s: Strike, delta: float, world: RegolithWorld) -> bool:
	track_target(s, delta)
	follow_end(s)
	advance_phase(s, delta)
	s.age += delta

	if world != null and s.props.emit_spark:
		emit_sparks(s, world, delta)

	return s.is_fading() and s.life <= 0.0

func track_target(s: Strike, delta: float) -> void:
	if s.target == null:
		return

	s.keepalive += delta
	var goal = s.target.position() if s.keepalive <= TRACKING_KEEPALIVE else null

	if goal == null:
		s.target = null
	else:
		s.end = goal + s.end_offset

func follow_end(s: Strike) -> void:
	if (s.struck and not s.sustaining) or s.bolts.is_empty() or s.end == s.aim_end:
		return

	var shift_end := s.end - s.aim_end
	var ch := s.bolts[0]
	var base := 0.0 if s.sustaining else s.front
	var denom := maxf(1e-4, s.channel_len) if s.sustaining else maxf(1e-4, s.channel_len - s.front)
	var channel_path := ch.path

	for i in channel_path.size():
		var w := clampf((ch.cum[i] - base) / denom, 0.0, 1.0)
		channel_path[i] += shift_end * w

	ch.path = channel_path
	ch.cum = cumulative(channel_path)

	for bi in range(1, s.bolts.size()):
		var br := s.bolts[bi]
		var root := s.bolts[br.parent].path[br.fork_index]
		var shift := root - br.path[0]
		var branch_path := br.path

		for i in branch_path.size():
			branch_path[i] += shift

		br.path = branch_path

	s.aim_end = s.end
	s.channel_len = ch.cum[ch.cum.size() - 1]

	if s.sustaining:
		s.front = s.channel_len

func advance_phase(s: Strike, delta: float) -> void:
	if not s.struck:
		s.front += s.reveal_speed * delta

		if s.front >= s.channel_len:
			s.front = s.channel_len
			s.struck = true

			if s.target != null:
				s.sustaining = true
				s.restrike = RESTRIKE_TIME
			else:
				s.flash_timer = FLASH_TIME

	elif s.sustaining:
		if s.target == null:
			s.sustaining = false
			s.flash_timer = FLASH_TIME
		else:
			s.restrike -= delta

			if s.restrike <= 0.0:
				generate(s)
				s.struck = true
				s.sustaining = true
				s.front = s.channel_len
				s.restrike = RESTRIKE_TIME

	elif s.flash_timer > 0.0:
		s.flash_timer -= delta

		if s.flash_timer <= 0.0:
			var channel: Array[Bolt] = []
			var branches: Array[Bolt] = []

			for b in s.bolts:
				if b.is_root:
					channel.append(b)
				else:
					branches.append(b)

			recycle_bolts(branches)
			s.bolts = channel
			s.life = s.props.lifetime

	else:
		s.life -= delta

func emit_sparks(s: Strike, world: RegolithWorld, delta: float) -> void:
	var p := s.props
	var pixels_per_unit := RegolithWorld.pixels_per_unit()

	if p.particle_density > 0.0:
		var spacing := pixels_per_unit / p.particle_density
		var target := minf(s.front, s.channel_len)

		for bolt in s.bolts:
			if not bolt.is_channel:
				continue

			while bolt.spark_emitted < target:
				spawn_spark(world, to_world(s, point_at_distance(bolt, bolt.spark_emitted)), p, pixels_per_unit)
				bolt.spark_emitted += spacing

	if delta > 0.0 and s.is_fading() and not s.bolts.is_empty() and randf() < 0.3:
		spawn_spark(world, to_world(s, point_at_distance(s.bolts[0], randf() * s.channel_len)), p, pixels_per_unit)

static func spawn_spark(world: RegolithWorld, position: Vector2, p: LightningProps, pixels_per_unit: float) -> void:
	var velocity := Vector2.from_angle(randf() * TAU) * randf_range(0.0, p.spark_speed) * pixels_per_unit
	world.spawn_cell_particle(position, velocity, p.spark_color, 0.0)

func draw_strikes() -> void:
	if material == null:
		if not warned_material:
			warned_material = true
			push_warning("Lightning: material is null, nothing is drawn")

		instance.visible = false
		segment_count = 0
		return

	if instance.material != material:
		instance.material = material

	instance.visible = true

	cell = RegolithWorld.pixels_per_cell()
	bounds_min = Vector2(INF, INF)
	bounds_max = Vector2(-INF, -INF)
	var count := 0

	for s in strikes:
		var p := s.props
		var fading := s.is_fading()
		var life_t := clampf(1.0 - s.life / maxf(1e-4, p.lifetime), 0.0, 1.0) if fading else 0.0
		var base_color := p.color.lerp(p.fade_color, life_t) if fading else p.color

		for bolt in s.bolts:
			count = write_bolt(s, bolt, base_color, fading, count)

	upload(count)

func write_bolt(s: Strike, bolt: Bolt, base_color: Color, fading: bool, index: int) -> int:
	var reach := s.front - bolt.fork_distance
	var revealed := bolt.path.size()

	if not fading:
		revealed = 0

		while revealed < bolt.path.size() and bolt.cum[revealed] <= reach:
			revealed += 1

	var glow := bolt.brightness * (1.0 + s.props.emission)
	var color := Color(base_color.r * glow, base_color.g * glow, base_color.b * glow, base_color.a * bolt.brightness)
	var previous := to_world(s, bolt.path[0])

	for i in range(1, revealed):
		var point := to_world(s, bolt.path[i])
		write_segment(index, previous, point, color)
		index += 1
		previous = point

	if not fading and revealed > 0 and revealed < bolt.path.size() and reach > bolt.cum[revealed - 1]:
		write_segment(index, previous, to_world(s, point_at_distance(bolt, reach)), color)
		index += 1

	return index

func upload(count: int) -> void:
	segment_count = count

	if count * 4 < capacity and capacity > MIN_CAPACITY:
		idle_frames += 1

		if idle_frames >= SHRINK_FRAMES:
			set_capacity(maxi(count * 2, MIN_CAPACITY))
	else:
		idle_frames = 0

	if count == 0:
		if multimesh.instance_count > 0:
			multimesh.visible_instance_count = 0
		return

	if multimesh.instance_count != capacity:
		multimesh.instance_count = capacity

	multimesh.buffer = buffer
	multimesh.visible_instance_count = count

	var pad := 4.0 * cell
	var rect := Rect2(bounds_min - Vector2(pad, pad), bounds_max - bounds_min + Vector2(pad, pad) * 2.0)
	RenderingServer.canvas_item_set_custom_rect(instance.get_canvas_item(), true, rect)

func set_capacity(size: int) -> void:
	capacity = size
	buffer.resize(capacity * FLOATS_PER_INSTANCE)
	idle_frames = 0

func write_segment(index: int, a: Vector2, b: Vector2, color: Color) -> void:
	if index >= capacity:
		set_capacity(maxi(index + 1, capacity * 2))

	bounds_min = bounds_min.min(a).min(b)
	bounds_max = bounds_max.max(a).max(b)

	var inv_cell := 1.0 / cell
	var o := index * FLOATS_PER_INSTANCE

	buffer[o] = cell
	buffer[o + 1] = 0.0
	buffer[o + 2] = 0.0
	buffer[o + 3] = 0.0
	buffer[o + 4] = 0.0
	buffer[o + 5] = cell
	buffer[o + 6] = 0.0
	buffer[o + 7] = 0.0

	buffer[o + 8] = color.r
	buffer[o + 9] = color.g
	buffer[o + 10] = color.b
	buffer[o + 11] = color.a

	buffer[o + 12] = a.x * inv_cell
	buffer[o + 13] = a.y * inv_cell
	buffer[o + 14] = b.x * inv_cell
	buffer[o + 15] = b.y * inv_cell
