extends Enemy
class_name EnemyFighter

# AiFlocker + AiFighter: follows a squad leader in formation or roams a spot
# near the player, keeps apart from everything close, flocks with the other
# fighters, dodges what is ahead and shoots when the player is in range
# and in sight

@export var weapon_props: WeaponProps
@export var fire_radius := 10.0
@export var separation_radius := 2.0
@export var neighbor_radius := 5.0
@export var cohesion_weight := 0.15
@export var alignment_weight := 0.1
@export var max_followers := 4
@export var formation_spacing := 1.5
@export var roam_distance := 10.0
@export var meander_radius := 3.0

const SQUAD_INTERVAL_MIN := 0.25
const SQUAD_INTERVAL_MAX := 0.5
const TARGET_CHECK_INTERVAL := 0.5
const AVOID_INTERVAL := 0.1

var weapon: Weapon
var leader: EnemyFighter
var followers: Array = []
var target := Vector2.INF
var meander_angle := randf() * TAU
var escape := Vector2.ZERO

var squad_timer := 0.0
var target_timer := 0.0
var avoid_timer := 0.0
var avoid_heading := 0.0
var avoid_found := false

func _ready() -> void:
	super()
	weapon = make_weapon(weapon_props, Vector2.ZERO)

func update_ai(delta: float) -> void:
	update_squad(delta)

	var waypoint := pos
	var meander := false
	var match_speed := -1.0

	if leader:
		var leader_pos: Vector2 = leader.global_position / Steering.ppu()
		var leader_velocity: Vector2 = leader.linear_velocity
		var leader_speed := leader_velocity.length()
		var leader_direction := leader_velocity / leader_speed if leader_speed > 0.0 else Vector2.ZERO

		if leader_speed < 0.1 and player:
			leader_direction = (player_pos - leader_pos).normalized()

		var index := leader.followers.find(self)
		var rank := index / 2 + 1
		var side := 1.0 if index % 2 == 0 else -1.0
		var back := -leader_direction
		var right := Vector2(leader_direction.y, -leader_direction.x)

		waypoint = leader_pos + back * (formation_spacing * rank) + right * (formation_spacing * 0.8 * rank * side)

		if pos.distance_to(waypoint) < 1.5:
			match_speed = leader_speed
	elif player:
		target_timer -= delta

		if target == Vector2.INF or target.distance_to(player_pos) > roam_distance or (target_timer <= 0.0 and point_blocked(target)):
			target_timer = TARGET_CHECK_INTERVAL
			target = pick_target()

		meander = target.distance_to(pos) < meander_radius

		if meander:
			meander_angle = fmod(meander_angle + delta * 0.4, TAU)
			waypoint = target + Vector2.from_angle(meander_angle) * 2.0
		else:
			waypoint = target

	var correction := separation() + flocking()
	escape = escape.lerp(Vector2.ZERO, delta * 4.0)

	steer_to_waypoint(pos + correction + (waypoint - pos) + escape)

	if meander:
		desired_speed = minf(desired_speed, drive_max_speed * 0.35)

	if match_speed >= 0.0:
		desired_speed = minf(desired_speed, match_speed + drive_max_speed * 0.2)

	avoid_obstacles(delta)
	drive(delta)
	update_fire()

func pick_target() -> Vector2:
	var spot := Vector2.INF

	for tries in 16:
		spot = player_pos + Steering.random_outside_box(Vector2(3, 3), Vector2(4, 4))

		if not point_blocked(spot):
			break

	return spot

func point_blocked(point: Vector2) -> bool:
	var world := RegolithWorld.active()

	if world == null:
		return false

	var px := point * Steering.ppu()

	for sprite in world.query_rect(Rect2(px - Vector2.ONE, Vector2.ONE * 2.0)):
		if sprite == player or sprite is Enemy:
			continue

		if sprite.has_cell(sprite.world_to_cell(px)):
			return true

	return false

func update_squad(delta: float) -> void:
	squad_timer -= delta

	if squad_timer > 0.0:
		return

	squad_timer = randf_range(SQUAD_INTERVAL_MIN, SQUAD_INTERVAL_MAX)

	if leader != null or not followers.is_empty():
		return

	var best: EnemyFighter = null
	var best_distance := INF

	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not other is EnemyFighter or other.dead or other.leader != null or other.followers.size() >= max_followers:
			continue

		var d: float = global_position.distance_squared_to(other.global_position)

		if d < best_distance:
			best_distance = d
			best = other

	if best:
		join_squad(best)

func join_squad(new_leader: EnemyFighter) -> void:
	leader = new_leader
	new_leader.followers.append(self)
	new_leader.died.connect(on_leader_died)
	died.connect(new_leader.drop_follower.bind(self))

func on_leader_died() -> void:
	leader = null

func drop_follower(follower: EnemyFighter) -> void:
	followers.erase(follower)

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

func update_fire() -> void:
	var to_player := player_pos - pos
	var pull_trigger := player != null and to_player.length() < fire_radius and has_line_of_sight(pos, player_pos)
	weapon.set_fire_state(pull_trigger, to_player)
