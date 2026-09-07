extends RegolithSprite
class_name Enemy

# shared enemy plumbing: the player as target, the steering models of the
# original ai systems, death when the core is gone. subclasses implement
# update_ai, which runs on the physics step. sim units, one unit is one chunk

@export var drive_max_speed := 4.0
@export var drive_max_acceleration := 4.0
@export var drive_max_turn_rate := 0.4

signal died
signal threw(node: RegolithSprite)

var dead := false
var had_core := false
var core_checked := false

var player: RegolithSprite
var pos := Vector2.ZERO
var player_pos := Vector2.ZERO

var desired_speed := 0.0
var desired_heading := 0.0

var goal := Vector2.INF
var goal_timer := 0.0

func _ready() -> void:
	add_to_group("regolith")
	add_to_group("enemy")
	watch_world()

func watch_world() -> void:
	var world := RegolithWorld.active()

	if world == null:
		return

	world.cells_removed.connect(on_cells_removed)
	world.sprite_split.connect(on_sprite_split)
	world.sprite_destroyed.connect(on_sprite_destroyed)

func on_cells_removed(sprite: RegolithSprite, _count: int) -> void:
	if sprite == self:
		check_core()

func on_sprite_split(source: RegolithSprite, _piece: RegolithSprite) -> void:
	if source == self:
		check_core()

func on_sprite_destroyed(sprite: RegolithSprite) -> void:
	if sprite == self:
		die()

func check_core() -> void:
	if dead or not had_core:
		return

	if count_cells_of_type(RegolithSprite.CELL_CORE) == 0:
		die()

func _physics_process(delta: float) -> void:
	if dead or not is_loaded():
		return

	if not core_checked:
		core_checked = true
		had_core = count_cells_of_type(RegolithSprite.CELL_CORE) > 0

	if not is_instance_valid(player) or player.is_queued_for_deletion():
		player = Steering.find_player(get_tree())

	pos = global_position / Steering.ppu()

	if player:
		player_pos = player.global_position / Steering.ppu()

	update_ai(delta)

func update_ai(_delta: float) -> void:
	pass

func die() -> void:
	if dead:
		return

	dead = true
	died.emit()
	queue_free()

func local_point(p: Vector2) -> Vector2:
	if not is_loaded():
		return global_position

	return to_global(Vector2(p.x, -p.y) * Vector2(get_cell_count()) * 0.5 * Steering.cell_pixels())

func local_point_units(p: Vector2) -> Vector2:
	return local_point(p) / Steering.ppu()

func forward() -> Vector2:
	return Vector2.UP.rotated(global_rotation)

func steer_to_waypoint(waypoint: Vector2) -> void:
	var velocity := linear_velocity
	var speed := velocity.length()
	var direction := velocity / speed if speed > 0.0 else Vector2.ZERO
	var turn_radius := speed / sqrt(drive_max_turn_rate)
	var stopping_distance := speed * speed / (2.0 * drive_max_acceleration)
	var left := Vector2(direction.y, -direction.x)
	var left_center := pos + left * turn_radius
	var right_center := pos - left * turn_radius

	desired_speed = drive_max_speed
	desired_heading = (waypoint - pos).angle()

	if left_center.distance_to(waypoint) < turn_radius or right_center.distance_to(waypoint) < turn_radius:
		desired_speed = 0.0
	elif pos.distance_to(waypoint) < stopping_distance:
		desired_speed = 0.0

func drive(delta: float) -> void:
	var velocity := linear_velocity
	var speed := velocity.length()
	var heading := velocity.angle()
	var turning_hardness := 100000.0 if is_zero_approx(speed) else 1.0 / (speed / drive_max_speed)
	var max_delta_speed := drive_max_acceleration * delta
	var max_delta_heading := turning_hardness * drive_max_turn_rate * delta
	var try_delta_heading := Steering.wrap_angle(desired_heading - heading)
	var sharpness := clampf(1.0 - absf(try_delta_heading) / PI, 0.0, 1.0)
	var delta_speed := clampf(desired_speed * sharpness - speed, -max_delta_speed, max_delta_speed)
	var delta_heading := clampf(try_delta_heading, -max_delta_heading, max_delta_heading)

	speed = clampf(speed + delta_speed, 0.0, drive_max_speed)
	heading = fposmod(heading + delta_heading, TAU)
	linear_velocity = Vector2.from_angle(heading) * speed

func force_move_to(target: Vector2, max_speed: float, max_accel: float, delta: float) -> void:
	var to_goal := target - pos
	var distance := to_goal.length()
	var direction := to_goal / distance if distance > 0.0 else Vector2.ZERO
	var speed := linear_velocity.length()
	var stop_distance := speed * speed / (2.0 * max_accel + 0.0001)
	var desired := max_speed

	if distance < stop_distance:
		desired = max_speed * (distance / stop_distance)

	var error := direction * clampf(desired, 0.0, max_speed) - linear_velocity
	linear_velocity += error.limit_length(max_accel * delta)

func align_angle(target_angle: float, torque: float, damping: float, delta: float) -> void:
	var delta_angle := Steering.wrap_angle(target_angle - global_rotation)
	angular_velocity += delta_angle * torque * delta
	angular_velocity -= angular_velocity * damping * delta

func align_position(target: Vector2, force: float, damping: float, delta: float) -> void:
	linear_velocity += (target - pos) * force * delta
	linear_velocity -= linear_velocity * damping * delta

func turn_forward_toward(target: Vector2, turn_speed: float, delta: float) -> void:
	var to_target := target - pos

	if to_target.length_squared() <= 0.0001:
		angular_velocity = 0.0
		return

	var want := to_target.angle() + PI * 0.5
	var diff := Steering.wrap_angle(want - global_rotation)
	angular_velocity = clampf(diff / delta, -turn_speed, turn_speed)

func roam_goal(delta: float, interval: float, ellipse := Vector2(16.0, 6.0), allow := true) -> Vector2:
	goal_timer -= delta

	if goal_timer <= 0.0 and allow:
		goal_timer = interval
		goal = player_pos + Vector2.from_angle(randf() * TAU) * ellipse

	return goal

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var world := RegolithWorld.active()

	if world == null:
		return true

	var hit: Dictionary = world.ray_cast(from * Steering.ppu(), to * Steering.ppu(), self)
	return hit.is_empty() or hit["sprite"] == player

func nearest_thrower(from: Vector2, max_distance_squared: float) -> EnemyThrower:
	var best: EnemyThrower = null
	var best_distance := max_distance_squared

	for host in get_tree().get_nodes_in_group("thrower"):
		if host == self or host.dead:
			continue

		var thrower: EnemyThrower = host.thrower

		if thrower == null or not thrower.can_hold_more():
			continue

		var d := from.distance_squared_to(thrower.center)

		if d < best_distance:
			best_distance = d
			best = thrower

	return best

func spawn(kind: SpawnRequest.Kind, at: Vector2, velocity: Vector2, offscreen_only := false, lifetime := 10.0) -> SpawnRequest:
	var request := SpawnRequest.enemy(kind, at, velocity, offscreen_only, lifetime)
	request.ignore = [self]
	return SpawnBus.send(request)

func spawn_rock(props: RockProps, at: Vector2, velocity: Vector2, offscreen_only := false, lifetime := 10.0) -> SpawnRequest:
	var request := SpawnRequest.rock(props, at, velocity, offscreen_only, lifetime)
	request.ignore = [self]
	return SpawnBus.send(request)

func make_weapon(props: WeaponProps, origin: Vector2) -> Weapon:
	var weapon := Weapon.new()
	weapon.name = "Weapon"
	weapon.props = props
	weapon.local_fire_origin = origin
	add_child(weapon)
	return weapon
