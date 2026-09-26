extends RefCounted
class_name AimAssist

# PlayerShoot's aim assist: a fan of rays around the aim, alternating sides
# outward, finds the first cell a shot could reach. the aim is then bent
# onto where that cell will be when the shot arrives, solving the intercept
# against the sprite's velocity and refining it a few times with the
# sprite's spin. the shooter's own velocity is not part of it, shots do not
# inherit it. world pixels in and out, returns the given direction when
# nothing is in range. draws the fan under the AIM_ASSIST debug name the
# way the original did: misses as full rays, the hit as a line and a small
# ring, the lead as a line from the hit to a larger ring

const RAYS := 9
const MAX_RANGE := 30.0
const PREDICT_ITERATIONS := 4
const HIT_RING := 0.05
const LEAD_RING := 0.08

static func solve_intercept_time(to_target: Vector2, target_velocity: Vector2, projectile_speed: float) -> float:
	var a := target_velocity.dot(target_velocity) - projectile_speed * projectile_speed
	var b := 2.0 * to_target.dot(target_velocity)
	var c := to_target.dot(to_target)

	if absf(a) < 1e-6:
		if absf(b) < 1e-6:
			return -1.0

		return -c / b

	var disc := b * b - 4.0 * a * c

	if disc < 0.0:
		return -1.0

	var sq := sqrt(disc)
	var t0 := (-b - sq) / (2.0 * a)
	var t1 := (-b + sq) / (2.0 * a)

	if t0 > t1:
		var swap := t0
		t0 = t1
		t1 = swap

	if t0 > 0.0:
		return t0

	return t1

# the fan's ray directions in the order they are tried: the center, then
# one step out on each side, alternating, out to the half angle
static func ray_directions(direction: Vector2, half_angle: float) -> Array[Vector2]:
	var base_angle := direction.angle()
	var step := half_angle / float(RAYS / 2)
	var out: Array[Vector2] = []

	for i in RAYS:
		var steps_out := (i + 1) / 2
		var side := 1.0 if i % 2 == 1 else -1.0
		out.append(Vector2.from_angle(base_angle + side * float(steps_out) * step))

	return out

static func debug_draw(world: RegolithWorld) -> RegolithDebugDraw:
	var tree := world.get_tree()

	if tree == null:
		return null

	return tree.get_first_node_in_group("regolith_debug_draw") as RegolithDebugDraw

static func apply(world: RegolithWorld, shooter: RegolithSprite, props: WeaponProps, origin: Vector2, direction: Vector2) -> Vector2:
	var n_dir := direction.normalized()

	if n_dir.length_squared() == 0.0 or props.speed <= 0.0:
		return direction

	var ppu := RegolithWorld.pixels_per_unit()
	var projectile_speed := props.speed * ppu
	var range := minf(props.speed * props.lifetime, MAX_RANGE) * ppu
	var draw := debug_draw(world)

	for ray_dir in ray_directions(n_dir, deg_to_rad(props.aim_assist_degrees)):
		var hit: Dictionary = world.ray_cast(origin, origin + ray_dir * range, shooter)

		if hit.is_empty():
			if draw:
				draw.add_ray(origin, ray_dir * range, RegolithDebugDraw.AIM_ASSIST)

			continue

		var hit_point: Vector2 = hit["position"]

		if draw:
			draw.add_line(origin, hit_point, RegolithDebugDraw.AIM_ASSIST)
			draw.add_circle(hit_point, HIT_RING * ppu, RegolithDebugDraw.AIM_ASSIST)

		var predicted := hit_point
		var sprite: RegolithSprite = hit["sprite"]

		if is_instance_valid(sprite) and sprite.is_dynamic():
			var com := sprite.get_center_of_mass()
			var r := hit_point - com
			var to_target := hit_point - origin
			var velocity := sprite.linear_velocity * ppu
			var t := solve_intercept_time(to_target, velocity, projectile_speed)

			if t <= 0.0:
				return to_target

			for k in PREDICT_ITERATIONS:
				predicted = com + velocity * t + r.rotated(sprite.angular_velocity * t)
				t = (predicted - origin).length() / projectile_speed

		if draw:
			draw.add_line(hit_point, predicted, RegolithDebugDraw.AIM_ASSIST)
			draw.add_circle(predicted, LEAD_RING * ppu, RegolithDebugDraw.AIM_ASSIST)

		return predicted - origin

	return direction
