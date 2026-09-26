extends Node2D
class_name WarningLine

# port of WarningLineSystem: a telegraph line drawn from begin to end for
# lifetime seconds. one node serves the whole scene, another warn() while
# it is up moves and restarts it. the original drew three lines through
# LinePass: an additive glow band of the config width with round caps and
# a per point alpha that pulses along the line, and two thin additive edge
# lines on the band's borders. everything fades over the last fade_time.
# positions are world pixels, drawn on the render cadence

const CAP_STEPS := 8

@export var props: WarningLineProps

var begin := Vector2.ZERO
var end := Vector2.ZERO
var lifetime := 2.0
var age := 0.0
var active := false

# the one warning line of the scene, made under the world's parent on first
# use. named warn because CanvasItem already has show()
static func warn(from: Vector2, to: Vector2, for_seconds := 2.0) -> WarningLine:
	var tree := Engine.get_main_loop() as SceneTree
	var line := tree.get_first_node_in_group("warning_line") as WarningLine if tree else null

	if line == null:
		var world := RegolithWorld.active()

		if world == null or world.get_parent() == null:
			return null

		line = WarningLine.new()
		line.name = "WarningLine"
		world.get_parent().add_child(line)

	line.start(from, to, for_seconds)
	return line

func _enter_tree() -> void:
	add_to_group("warning_line")
	top_level = true
	z_index = 10

	if props == null:
		props = WarningLineProps.new()

	# both line configs of the original are additive
	if material == null:
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = additive

func start(from: Vector2, to: Vector2, for_seconds: float) -> void:
	begin = from
	end = to
	lifetime = for_seconds
	age = 0.0
	active = true
	visible = true
	queue_redraw()

func remaining() -> float:
	return lifetime - age

func _process(delta: float) -> void:
	if not active:
		return

	age += delta

	if age >= lifetime:
		active = false
		visible = false

	queue_redraw()

func fade_of(fade_time: float) -> float:
	var left := remaining()
	return left / maxf(fade_time, 0.001) if left < fade_time else 1.0

func glow_alpha(t: float, length_units: float, fade: float) -> float:
	var phase := (t * length_units - age * props.glow_pulse_speed) * TAU / maxf(props.glow_pulse_length, 0.01)
	var wave := 0.5 + 0.5 * sin(phase)
	return (props.glow_base_alpha + props.glow_pulse_alpha * wave) * fade

func glow_color(alpha: float) -> Color:
	var color := props.glow_color
	color.a = props.glow_color.a * alpha
	return color

# the glow band, max_points / 2 samples along the line like the original,
# per vertex color so the pulse blends smoothly between samples
func draw_glow(direction: Vector2, perpendicular: Vector2, length: float, half_width: float, fade: float) -> void:
	var count := maxi(props.glow_max_points / 2, 2)
	var length_units := length / RegolithWorld.pixels_per_unit()
	var offset := perpendicular * half_width

	var points := PackedVector2Array()
	var colors := PackedColorArray()

	for i in count:
		var t := float(i) / float(count - 1)
		points.append(begin + direction * (t * length))
		colors.append(glow_color(glow_alpha(t, length_units, fade)))

	for i in range(1, count):
		var quad := PackedVector2Array([points[i - 1] + offset, points[i] + offset, points[i] - offset, points[i - 1] - offset])
		var quad_colors := PackedColorArray([colors[i - 1], colors[i], colors[i], colors[i - 1]])
		draw_polygon(quad, quad_colors)

	draw_cap(points[0], -direction, half_width, colors[0])
	draw_cap(points[count - 1], direction, half_width, colors[count - 1])

# the round cap of the original's capsule quad, a half disc past the end
func draw_cap(at: Vector2, outward: Vector2, radius: float, color: Color) -> void:
	if radius < 1.0:
		return

	var base := outward.angle()
	var fan := PackedVector2Array()

	for i in CAP_STEPS + 1:
		var angle := base - PI * 0.5 + PI * float(i) / float(CAP_STEPS)
		fan.append(at + Vector2.from_angle(angle) * radius)

	draw_colored_polygon(fan, color)

func _draw() -> void:
	if not active or props == null:
		return

	var ppu := RegolithWorld.pixels_per_unit()
	var axis := end - begin
	var length := axis.length()
	var direction := axis / length if length > 0.001 else Vector2.RIGHT
	var perpendicular := Vector2(-direction.y, direction.x)

	var glow_fade := fade_of(props.glow_fade_time)
	var edge_fade := fade_of(props.edge_fade_time)
	var glow_width := props.glow_width * ppu

	draw_glow(direction, perpendicular, length, glow_width * 0.5, glow_fade)

	var edge_color := props.edge_color
	edge_color.a = props.edge_color.a * props.edge_base_alpha * edge_fade
	var offset := perpendicular * glow_width * 0.5
	var edge_width := maxf(props.edge_width * ppu, 1.0)

	draw_line(begin + offset, end + offset, edge_color, edge_width)
	draw_line(begin - offset, end - offset, edge_color, edge_width)
