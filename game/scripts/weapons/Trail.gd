extends Line2D
class_name Trail

# the streak behind a projectile, a gradient line whose last point is the
# tip, tapered from nothing at the tail to full width there like the
# engine's length scaled lines. the points live script side and go to the
# line once per frame, a remove_point loop would shift the whole line each
# time. pixels in

var path := PackedVector2Array()

# the extended Reinhard of the original's rc_composite.hlsl, exposure 1 and
# white point 2, that its RGBA16F scene went through on the way to the
# screen: the cannon's 0.9 gray trail showed as 0.58. the particle shader
# runs the same curve, the world here is not tonemapped
static func tonemapped(color: Color) -> Color:
	var out := color

	for i in 3:
		var hdr: float = color[i]
		out[i] = hdr * (1.0 + hdr / 4.0) / (1.0 + hdr)

	return out

# width_px is the original's line width in pixels as the callers reckon it,
# one cell for C.cell_local_scale. that constant is 1 / 64 unit, half a
# cell, and the original's line quad spans -0.5..0.5 of the width, so the
# cannon's trail was half a cell across and the missile's one cell
func setup(props: WeaponProps, width_px: float, start: Vector2) -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	width = width_px * 0.5
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	antialiased = false

	var fade_gradient := Gradient.new()
	fade_gradient.set_color(0, tonemapped(props.color_back))
	fade_gradient.set_color(1, tonemapped(props.color_front))
	gradient = fade_gradient

	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.0))
	taper.add_point(Vector2(1.0, 1.0))
	width_curve = taper

	path.append(start)
	points = path

func push(point: Vector2) -> void:
	path.append(point)

func tip() -> Vector2:
	return path[path.size() - 1]

func set_tip(point: Vector2) -> void:
	path[path.size() - 1] = point

# keep only the last length_px of the path and show it
func trim(length_px: float) -> void:
	var length := 0.0

	for i in range(path.size() - 1, 0, -1):
		var a := path[i]
		var b := path[i - 1]
		var segment := a.distance_to(b)

		if length + segment > length_px:
			path[i - 1] = a.move_toward(b, length_px - length)
			path = path.slice(i - 1)
			break

		length += segment

	points = path

# the projectile is gone, the tail flows travel_px on into where it stopped.
# true once nothing is left to show
func fade(travel_px: float) -> bool:
	var first := 0
	var travel := travel_px

	while first < path.size() - 1 and travel > 0.0:
		var a := path[first]
		var b := path[first + 1]
		var segment := a.distance_to(b)

		if segment <= travel:
			travel -= segment
			first += 1
		else:
			path[first] = a.move_toward(b, travel)
			travel = 0.0

	if first > 0:
		path = path.slice(first)

	points = path
	return path.size() <= 1
