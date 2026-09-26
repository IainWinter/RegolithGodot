extends EnemyScripted
class_name EnemyFighter

# the fighter's body: separation, flocking, obstacle dodging, the drive
# model from Enemy and the weapon EnemyScripted makes from weapon_props.
# the decisions (formation, roaming, squads, when to shoot) are in
# res://game/lua/fighter.lua, which reads the exports below and calls the
# helpers here. the player sensor child is how it learns where the player is

@export var fire_radius := 10.0
@export var separation_radius := 2.0
@export var neighbor_radius := 5.0
@export var cohesion_weight := 0.15
@export var alignment_weight := 0.1
@export var max_followers := 4
@export var formation_spacing := 1.5
@export var roam_distance := 10.0
@export var meander_radius := 3.0

const AVOID_INTERVAL := 0.1

var escape := Vector2.ZERO

var avoid_timer := 0.0
var avoid_heading := 0.0
var avoid_found := false

func _init() -> void:
	ai_class = "fighter"

# a spot near the player that is not inside a rock
func pick_target(around: Vector2) -> Vector2:
	var spot := Vector2.INF

	for tries in 16:
		spot = around + Steering.random_outside_box(Vector2(3, 3), Vector2(4, 4))

		if not point_blocked(spot):
			break

	return spot

# inside a cell of anything but the player or another enemy
func point_blocked(point: Vector2) -> bool:
	var world := RegolithWorld.active()
	return world != null and world.is_point_blocked(point * Steering.ppu(), self, path_ignore_groups)

# separation plus flocking plus the fading escape from the last dodge,
# added to the waypoint each step
func steer_correction(delta: float) -> Vector2:
	escape = escape.lerp(Vector2.ZERO, delta * 4.0)
	return separation() + flocking() + escape

func separation() -> Vector2:
	var world := RegolithWorld.active()

	if world == null:
		return Vector2.ZERO

	var s := separation_radius
	var scale := Steering.ppu()
	var correction := Vector2.ZERO
	var count := 0

	for other in Steering.sprites_near(world, pos, s * sqrt(2.0)):
		if other == self:
			continue

		var diff: Vector2 = pos - other.global_position / scale
		var length := diff.length()

		if length <= s and length > 0.0001:
			correction += diff / length * (s / (length * length) - 1.0 / s)

		count += 1

	if count > 0:
		correction /= count

	return correction

func flocking() -> Vector2:
	var world := RegolithWorld.active()

	if world == null:
		return Vector2.ZERO

	var scale := Steering.ppu()
	var center := Vector2.ZERO
	var velocity := Vector2.ZERO
	var count := 0

	for other in Steering.sprites_near(world, pos, neighbor_radius):
		if other == self or not other is EnemyFighter or other.dead:
			continue

		var other_pos: Vector2 = other.global_position / scale

		if pos.distance_to(other_pos) > neighbor_radius:
			continue

		center += other_pos
		velocity += other.linear_velocity
		count += 1

	if count == 0:
		return Vector2.ZERO

	return (center / count - pos) * cohesion_weight + velocity / count * alignment_weight

func avoid_obstacles(delta: float) -> void:
	var world := RegolithWorld.active()

	if world == null:
		return

	var scale := Steering.ppu()
	var from := pos * scale
	var speed := linear_velocity.length()
	var look_ahead := speed * speed / (2.0 * drive_max_acceleration) + 0.5
	var hit_distance := cast_obstacle(world, from, desired_heading, look_ahead * scale) / scale

	if hit_distance < 0.0:
		return

	avoid_timer -= delta

	if avoid_timer <= 0.0:
		avoid_timer = AVOID_INTERVAL
		avoid_heading = desired_heading
		avoid_found = false

		for i in range(1, 9):
			for side: float in [-1.0, 1.0]:
				var heading := desired_heading + side * i * PI / 8.0

				if cast_obstacle(world, from, heading, look_ahead * scale) < 0.0:
					avoid_heading = heading
					avoid_found = true
					break

			if avoid_found:
				break

	var stopping_distance := speed * speed / (2.0 * drive_max_acceleration)
	var urgency := clampf(1.0 - hit_distance / (look_ahead + 0.5), 0.0, 1.0)

	desired_heading = avoid_heading

	if not avoid_found or hit_distance < stopping_distance:
		desired_speed = 0.0
	else:
		desired_speed *= 1.0 - urgency * 0.5

	escape = escape.lerp(Vector2.from_angle(avoid_heading) * urgency * 2.0, delta * 8.0)

func cast_obstacle(world: RegolithWorld, from: Vector2, heading: float, length: float) -> float:
	var hit: Dictionary = world.ray_cast(from, from + Vector2.from_angle(heading) * length, self)

	if hit.is_empty() or hit["sprite"] is Enemy:
		return -1.0

	return float(hit["distance"])
