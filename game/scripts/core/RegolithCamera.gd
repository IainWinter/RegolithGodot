extends Camera2D
class_name RegolithCamera

# port of CameraControllerSystem. the view chases the target's center of
# mass pushed ahead by its velocity, framed with the target and any extra
# frame_points inside asymmetric edge padding, and never shows less than
# height_units. position and height ease with a weight of
# 1 - exp(-speed * delta), the target's own speed when it has one. sim
# units for heights, world pixels for points

# the original CameraController kept cam.height = 5 as a HALF height
# (ortho -h..h), so the view is 10 units tall. CAMERA_HEIGHT is that half
# height, which the offscreen spawn bands also use
@export var height_units: float = RegolithWorld.CAMERA_HEIGHT * 2.0
# the easing rate is looked up once here: a move_speed() method, else a
# speed property, else follow_speed
@export var target: Node2D:
	set(value):
		target = value
		speed_of = Callable()

		if target and target.has_method("move_speed"):
			speed_of = target.move_speed
		elif target and "speed" in target:
			speed_of = property_speed
# easing rate when the target has no move_speed of its own
@export var follow_speed := 8.0
@export var lookahead_time := 0.08
# fraction of the half view the framed box may reach on each side: left,
# right, bottom, top
@export var edge_padding := Vector4(0.9 - 0.266666, 0.9, 0.9, 0.9)
@export var frame_margin := 1.0

# world pixel points others want kept in view this frame, cleared after use
var frame_points := PackedVector2Array()
var view_height := 0.0
var speed_of := Callable()
# the viewport size, refreshed when it changes
var view_size := Vector2(16.0, 9.0)

func _ready() -> void:
	get_viewport().size_changed.connect(on_size_changed)
	view_height = height_units
	on_size_changed()

	if target:
		global_position = target_position()

func on_size_changed() -> void:
	view_size = get_viewport_rect().size
	update_zoom()

func update_zoom() -> void:
	var world_pixels := maxf(view_height, 0.01) * RegolithWorld.pixels_per_unit()
	zoom = Vector2.ONE * (view_size.y / world_pixels)

func aspect() -> float:
	return view_size.x / view_size.y if view_size.y > 0.0 else 16.0 / 9.0

func target_velocity() -> Vector2:
	if target is RegolithSprite:
		return target.linear_velocity * RegolithWorld.pixels_per_unit()

	return Vector2.ZERO

func target_position() -> Vector2:
	var center := target.global_position

	if target is RegolithSprite and target.is_loaded():
		center = target.get_center_of_mass()

	return center + target_velocity() * lookahead_time

func target_speed() -> float:
	if not is_instance_valid(target) or not speed_of.is_valid():
		return follow_speed

	return speed_of.call()

func property_speed() -> float:
	return target.speed

func _process(delta: float) -> void:
	if target == null:
		return

	var ppu := RegolithWorld.pixels_per_unit()
	var focus := target_position() / ppu
	var box_min := focus
	var box_max := focus

	for point in frame_points:
		box_min = box_min.min(point / ppu)
		box_max = box_max.max(point / ppu)

	frame_points = PackedVector2Array()

	var box_center := (box_min + box_max) * 0.5
	var box_extents := (box_max - box_min) * 0.5

	var required_width := maxf(box_extents.x / edge_padding.x, box_extents.x / edge_padding.y)
	var required_height := maxf(box_extents.y / edge_padding.z, box_extents.y / edge_padding.w)

	var ratio := aspect()
	var half_height := maxf(height_units * 0.5, maxf(required_height + frame_margin, (required_width + frame_margin) / ratio))
	var half_extents := Vector2(half_height * ratio, half_height)

	var min_center := Vector2(focus.x - half_extents.x * edge_padding.x, focus.y - half_extents.y * edge_padding.z)
	var max_center := Vector2(focus.x + half_extents.x * edge_padding.y, focus.y + half_extents.y * edge_padding.w)
	var target_center := box_center.clamp(min_center, max_center)

	var weight := 1.0 - exp(-target_speed() * delta)

	view_height = lerpf(view_height, half_height * 2.0, weight)
	global_position = (global_position / ppu).lerp(target_center, weight) * ppu
	update_zoom()
