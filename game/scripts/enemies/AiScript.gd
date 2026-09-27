extends RegolithSprite
class_name AiScript

# the generic ai host for any regolith sprite that thinks. no per-kind
# gdscript subclass: everything the game calls "an enemy" or "a friendly"
# or "a boss" is a scene instancing AiScript with a different .lua and
# maybe a few scene-tree component nodes listening on ai_event. this class
# holds the body plumbing (steering, weapons, death, throwers, sensors,
# pathfinding), the lua runtime binding, the state machine, and a curated
# generic verb set the scripts call.
#
# every tick, in order:
#   1. sensors poll and drop messages in the inbox
#   2. the lua on_message(msg) runs for each message, transitions are held
#   3. the lua update(dt) runs
#   4. held transitions release, the state machine ticks the current state
# the script gets the messages, decides, and asks the body to do things
# through the verbs on self.node. anything scene-specific goes over
# ai_event(name, args) so a small gdscript node in the scene can pick it
# up without adding a subclass here.
#
# hostility is a scene-level concern, not a class one. scenes that are
# hostile add themselves to the "enemy" group in the .tscn, friendlies
# to whatever fits. the framework does not add either automatically

# steering model, sim units, one unit is one chunk
@export var drive_max_speed := 4.0
@export var drive_max_acceleration := 4.0
@export var drive_max_turn_rate := 0.4

# the name of the lua class in res://game/lua that runs this instance
@export var ai_class := ""
@export var weapon_props: WeaponProps
@export var drop_table: ItemDropTable
# tunables the scene or a test override on top of the lua class's
# settings() defaults. the lua reads self.cfg[key] at runtime
@export var ai_config := {}

signal died
signal threw(node: RegolithSprite)
# lua-driven escape hatch: any scene-specific behavior a script needs
# outside the generic verb set. listeners filter on name
signal ai_event(name: StringName, args: Dictionary)

# body state
var dead := false
var had_core := false
var core_checked := false
var player: RegolithSprite
var pos := Vector2.ZERO
var player_pos := Vector2.ZERO
var desired_speed := 0.0
var desired_heading := 0.0
var thrower_part: EnemyThrower

# ai state
var ai_id := 0
var state_machine := AiStateMachine.new()
var inbox: Array[Dictionary] = []
var sensors: Array[Sensor] = []
var weapon: Weapon
# the tunables the lua class declared through settings(), {key = default}.
# ai_config wins over this for anything a scene or test overrode. this is
# the schema view for tooling, not the runtime state
var settings: Dictionary = {}

# pathfinding fallback: a goal out of sight is reached over an a* path on
# a grid one body wide, advanced as waypoints fall behind, rechecked every
# half second and rebuilt when a leg is blocked. other enemies and the
# player never block. units in and out, path_blocked tells a caller no
# path was found this step
const PATH_CHECK_INTERVAL := 0.5
const NO_PATH_INTERVAL := 0.5
var path_ignore_groups := PackedStringArray(["enemy", "player"])
var path := PackedVector2Array()
var path_timer := 0.0
var no_path_timer := 0.0
var path_blocked := false

# generic obstacle avoidance state, used by avoid_obstacles / steer_correction
const AVOID_INTERVAL := 0.1
var avoid_escape := Vector2.ZERO
var avoid_timer := 0.0
var avoid_heading := 0.0
var avoid_found := false

func _ready() -> void:
	add_to_group("regolith")
	watch_world()
	hold_position = global_position / Steering.ppu()
	hold_angle = global_rotation

	for child in get_children():
		if child is Sensor:
			sensors.append(child)
			child.message.connect(receive)

	if weapon_props:
		weapon = make_weapon(weapon_props, Vector2.ZERO)

	var thrower := get_thrower()

	if thrower:
		thrower.threw.connect(func(node: RegolithSprite): threw.emit(node))

	state_machine.label = "%s (%s)" % [name, ai_class]

	if ai_class != "":
		ai_id = Ai.create(ai_class, self)
		state_machine.bind(Ai.lua, ai_id)
		read_settings()

func _exit_tree() -> void:
	state_machine.unbind()

	if ai_id != 0:
		Ai.destroy(ai_id)
		ai_id = 0

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

func die() -> void:
	if dead:
		return

	dead = true
	died.emit()
	queue_free()

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

# runs the script and the state machine each tick. sensors first, so
# messages the script gets are the fresh reading
func update_ai(delta: float) -> void:
	for sensor in sensors:
		sensor.poll(delta)

	if ai_id == 0:
		return

	var pending := inbox
	inbox = []

	# transitions asked for in here wait for the tick
	state_machine.hold()

	for message in pending:
		Ai.invoke(ai_id, "on_message", [message])

	Ai.invoke(ai_id, "update", [delta])
	state_machine.release()
	state_machine.tick(delta)

# anything with a receive can be a message target
func receive(message: Dictionary) -> void:
	inbox.append(message)

# changes tunables on the scene and, once the script runs, on its cfg
func configure(overrides: Dictionary) -> void:
	ai_config.merge(overrides, true)

	if ai_id != 0:
		Ai.invoke(ai_id, "configure", [overrides])

# the schema the .lua class declared through settings(). ai_config still
# wins for anything a scene or a test set
func read_settings() -> void:
	if ai_id == 0:
		return

	var declared = Ai.invoke(ai_id, "settings", [])

	if declared is Dictionary:
		settings = declared

# the current value of a script tunable, ai_config first (scene/test
# override) then settings (the lua class's declared default), else the
# supplied fallback. useful when another script wants to read a value a
# lua class declared on itself, e.g. boss.reading a bomb's speed
func get_setting(key: StringName, fallback: Variant = null) -> Variant:
	if ai_config.has(key):
		return ai_config[key]

	if settings.has(key):
		return settings[key]

	return fallback

# the escape hatch: lua fires self:emit_event("kind", {...}), scene
# nodes listening on ai_event pick it up. args is copied so the listener
# can hold on to it without the script clobbering it next tick
func emit_event(event: StringName, args: Dictionary = {}) -> void:
	ai_event.emit(event, args.duplicate())

# geometry

# a prefab point on the hull, -1..1 spanning the grid with y up as the
# original prefabs were authored, through Transform::ToWorldPoint
func local_point(p: Vector2) -> Vector2:
	if not is_loaded():
		return global_position

	return local_to_world(Vector2(p.x, -p.y))

func local_point_units(p: Vector2) -> Vector2:
	return local_point(p) / Steering.ppu()

func forward() -> Vector2:
	return Vector2.UP.rotated(global_rotation)

# the body as the script measures it: half extents and radius of the grid
# in units, and where effects come from (the core, else the center of mass)
func half_extent_units() -> Vector2:
	return Steering.half_extent_units(self)

func radius_units() -> float:
	return Steering.sprite_radius_units(self)

func effect_origin_units() -> Vector2:
	return EffectSpawner.effect_origin(self) / Steering.ppu()

func is_thrown() -> bool:
	var throwable := Throwable.of(self)
	return throwable != null and throwable.thrown

# true while a thrower is holding this node in its ring, before the swing
# lets go. scripts skip their steering while held so the thrower's applied
# velocity isn't fought
func is_held() -> bool:
	var throwable := Throwable.of(self)
	return throwable != null and throwable.held_by != null

# steering

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

# the EnemyThrower child, when the ai has one. a friendly or a boss with
# no throw arm returns null
func get_thrower() -> EnemyThrower:
	if thrower_part == null or not is_instance_valid(thrower_part):
		thrower_part = null

		for child in get_children():
			if child is EnemyThrower:
				thrower_part = child
				break

	return thrower_part

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var world := RegolithWorld.active()

	if world == null:
		return true

	var hit: Dictionary = world.ray_cast(from * Steering.ppu(), to * Steering.ppu(), self)
	return hit.is_empty() or hit["sprite"] == player

# the nearest thrower host with room, ignoring self and dead hosts. the
# thrower group is scene-level, any AiScript that carries an EnemyThrower
# child is a valid host regardless of hostility
func nearest_thrower(from: Vector2, max_distance_squared: float) -> EnemyThrower:
	var best: EnemyThrower = null
	var best_distance := max_distance_squared

	for host in get_tree().get_nodes_in_group("thrower"):
		# split pieces inherit the group without the script
		if host == self or not host is AiScript or (host as AiScript).dead:
			continue

		var thrower: EnemyThrower = host.get_thrower()

		if thrower == null or not thrower.can_hold_more():
			continue

		var d := from.distance_squared_to(thrower.center)

		if d < best_distance:
			best_distance = d
			best = thrower

	return best

# spawn requests through the bus, ignoring self so the placement never
# collides with the requester

func spawn(kind: SpawnRequest.Kind, at: Vector2, velocity: Vector2, offscreen_only := false, lifetime := 10.0) -> SpawnRequest:
	var request := SpawnRequest.enemy(kind, at, velocity, offscreen_only, lifetime)
	request.ignore = [self]
	return SpawnBus.send(request)

func spawn_rock(props: RockProps, at: Vector2, velocity: Vector2, offscreen_only := false, lifetime := 10.0) -> SpawnRequest:
	var request := SpawnRequest.rock(props, at, velocity, offscreen_only, lifetime)
	request.ignore = [self]
	return SpawnBus.send(request)

# pathfinding

func path_cell_size() -> float:
	var cells := Steering.cell_count(self)
	return maxf(maxf(cells.x, cells.y) * Steering.cell_pixels(), Steering.cell_pixels())

func path_steer_target(goal: Vector2, delta: float) -> Vector2:
	var world := RegolithWorld.active()
	path_blocked = false

	if world == null:
		return goal

	var ppu := Steering.ppu()
	var from := pos * ppu
	var to := goal * ppu

	if world.has_line_of_sight(from, to, self, path_ignore_groups):
		path = PackedVector2Array()
		return goal

	var cell := path_cell_size()
	path = RegolithWorld.advance_waypoints(path, from, cell * 0.75)

	var recompute := false

	if path.is_empty():
		no_path_timer -= delta

		if no_path_timer <= 0.0:
			no_path_timer = NO_PATH_INTERVAL
			recompute = true
	else:
		path_timer -= delta

		if path_timer <= 0.0:
			path_timer = PATH_CHECK_INTERVAL
			recompute = not world.is_path_clear(from, path, to, self, path_ignore_groups)

	if recompute:
		path = world.find_path(from, to, cell, self, path_ignore_groups)
		path = RegolithWorld.advance_waypoints(path, from, cell * 0.75)

	if path.is_empty():
		path_blocked = true
		return goal

	world.draw_path(from, path, to)
	return path[0] / ppu

# weapons

func make_weapon(props: WeaponProps, origin: Vector2) -> Weapon:
	var w := Weapon.new()
	w.name = "Weapon"
	w.props = props
	w.local_fire_origin = origin
	add_child(w)
	return w

func fire(pull_trigger: bool, direction: Vector2) -> void:
	if weapon:
		weapon.set_fire_state(pull_trigger, direction)

# a bounded turn toward to_goal while keeping the speed inside a band. the
# body commits to a turn direction until the diff shrinks below
# commit_angle. useful for slow drifters that must not oscillate.
# turn_strength rad/s, speed units/s. the commit direction persists in
# turn_bias across ticks
var turn_bias := 0

func steer_bounded_turn(to_goal: Vector2, speed: float, turn_strength: float, commit_angle: float, delta: float) -> void:
	var velocity := linear_velocity
	var current_speed := velocity.length()

	if current_speed > 0.0001:
		var diff := velocity.angle_to(to_goal)
		var max_turn := turn_strength * delta
		var step: float

		if absf(diff) < commit_angle:
			turn_bias = 0
			step = clampf(diff, -max_turn, max_turn)
		else:
			if turn_bias == 0:
				turn_bias = 1 if diff > 0.0 else -1

			var agree := (diff > 0.0) == (turn_bias > 0)
			step = turn_bias * (minf(absf(diff), max_turn) if agree else max_turn)

		velocity = velocity.rotated(step)

	if current_speed > 25.0 or current_speed < speed:
		if current_speed == 0.0:
			velocity = Vector2.RIGHT

		velocity = velocity.lerp(velocity.normalized() * speed, turn_strength * delta)

	linear_velocity = velocity

# the ring spot on the nearest thrower host with room, null when there is
# none. wrap of nearest_thrower + ring_goal
func thrower_goal(around: Vector2) -> Variant:
	var thrower := nearest_thrower(pos, pos.distance_squared_to(around))

	if thrower == null:
		return null

	return thrower.ring_goal(around)

# an AI holds its spawn spot and heading through this call each tick.
# hold_position and hold_angle are seeded on _ready, scripts can rewrite
# them to change what "still" means
var hold_position := Vector2.ZERO
var hold_angle := 0.0

func hold_station(align_torque: float, align_damping: float, hold_force: float, hold_damping: float, delta: float) -> void:
	align_angle(hold_angle, align_torque, align_damping, delta)
	align_position(hold_position, hold_force, hold_damping, delta)

# fires the weapon from a specific hull point in the original -1..1 space
# with y up (as the original prefabs authored their fire points), the
# weapon's origin rides along so bullets leave the point in world space
func fire_from(local: Vector2, direction: Vector2) -> void:
	if weapon == null:
		return

	weapon.local_fire_origin = Vector2(local.x, -local.y) * Steering.half_extent_units(self)
	weapon.set_fire_state(true, direction)

# turn the nose to a target and pull the velocity toward it. flyers use
# this while flying free. turn_speed rad/s, accel and speed in units
func steer_toward_target(target: Vector2, speed: float, accel: float, turn_speed: float, delta: float) -> void:
	turn_forward_toward(target, turn_speed, delta)
	linear_velocity = linear_velocity.lerp(forward() * speed, clampf(accel * delta, 0.0, 1.0))

# hold a fixed heading and slide the body to the target. used when a
# flyer commits to a "planted" attack pose where the ropes go stiff.
# align_torque/damping tune the heading spring
func steer_planted(target: Vector2, speed: float, accel: float, plant_angle: float, align_torque: float, align_damping: float, delta: float) -> void:
	align_angle(plant_angle, align_torque, align_damping, delta)
	linear_velocity = linear_velocity.lerp((target - pos).normalized() * speed, clampf(accel * delta, 0.0, 1.0))

# the dive touches a target when the centers come within half this body's
# radius plus theirs
func touching(target: RegolithSprite) -> bool:
	if not is_instance_valid(target):
		return false

	return pos.distance_to(target.global_position / Steering.ppu()) < Steering.sprite_radius_units(self) * 0.5 + Steering.sprite_radius_units(target)

# the ContactEvent of the original: an explosion at the hit and a shove
func ram(target: RegolithSprite, impulse: float) -> void:
	if not is_instance_valid(target):
		return

	var target_pos: Vector2 = target.global_position / Steering.ppu()
	var direction := (target_pos - pos).normalized()
	var effects := EffectSpawner.active()

	if effects:
		effects.explosion((pos + direction * Steering.sprite_radius_units(self) * 0.5) * Steering.ppu())

	target.apply_impulse(direction * impulse, target.get_center_of_mass())

# generic steering verbs: parameterized so any lua class can use them
# without knowing what host it's on. they read the body's state (pos,
# linear_velocity, desired_*) and never touch class-specific fields

# a spot near around that is not blocked. offset is picked in the ring
# [inner, outer] halved on each axis. reads path_ignore_groups for what
# does not count as blocking
func pick_target(around: Vector2, inner: Vector2, outer: Vector2, tries := 16) -> Vector2:
	var spot := Vector2.INF

	for _i in tries:
		spot = around + Steering.random_outside_box(inner, outer)

		if not point_blocked(spot):
			break

	return spot

# inside a cell of anything not in path_ignore_groups
func point_blocked(point: Vector2) -> bool:
	var world := RegolithWorld.active()
	return world != null and world.is_point_blocked(point * Steering.ppu(), self, path_ignore_groups)

# repulsion from nearby sprites, in units. drops with distance and the
# radius. counts only what is within radius, not what shares it
func separation(radius: float) -> Vector2:
	var world := RegolithWorld.active()

	if world == null:
		return Vector2.ZERO

	var scale := Steering.ppu()
	var correction := Vector2.ZERO
	var count := 0

	for other in Steering.sprites_near(world, pos, radius * sqrt(2.0)):
		if other == self:
			continue

		var diff: Vector2 = pos - other.global_position / scale
		var length := diff.length()

		if length <= radius and length > 0.0001:
			correction += diff / length * (radius / (length * length) - 1.0 / radius)

		count += 1

	if count > 0:
		correction /= count

	return correction

# cohesion + alignment with other AiScript nodes sharing the given ai_class
# within radius, so squads flock with their own kind without needing a scene
# group set
func flocking(radius: float, cohesion_weight: float, alignment_weight: float, kind: String) -> Vector2:
	var world := RegolithWorld.active()

	if world == null:
		return Vector2.ZERO

	var scale := Steering.ppu()
	var center := Vector2.ZERO
	var velocity := Vector2.ZERO
	var count := 0

	for other in Steering.sprites_near(world, pos, radius):
		if other == self or not other is AiScript:
			continue

		var other_ai := other as AiScript

		if other_ai.ai_class != kind or other_ai.dead:
			continue

		var other_pos: Vector2 = other.global_position / scale

		if pos.distance_to(other_pos) > radius:
			continue

		center += other_pos
		velocity += other.linear_velocity
		count += 1

	if count == 0:
		return Vector2.ZERO

	return (center / count - pos) * cohesion_weight + velocity / count * alignment_weight

# separation + flocking + fading escape, added to the waypoint each step
func steer_correction(delta: float, sep_radius: float, flock_radius: float, cohesion_weight: float, alignment_weight: float, flock_kind: String) -> Vector2:
	avoid_escape = avoid_escape.lerp(Vector2.ZERO, delta * 4.0)
	return separation(sep_radius) + flocking(flock_radius, cohesion_weight, alignment_weight, flock_kind) + avoid_escape

# turns desired_heading / desired_speed around what is ahead. call after
# steer_to_waypoint, before drive
func avoid_obstacles(delta: float) -> void:
	var world := RegolithWorld.active()

	if world == null:
		return

	var scale := Steering.ppu()
	var from := pos * scale
	var speed := linear_velocity.length()
	var look_ahead := speed * speed / (2.0 * drive_max_acceleration) + 0.5
	var hit_distance := _cast_obstacle(world, from, desired_heading, look_ahead * scale) / scale

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

				if _cast_obstacle(world, from, heading, look_ahead * scale) < 0.0:
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

	avoid_escape = avoid_escape.lerp(Vector2.from_angle(avoid_heading) * urgency * 2.0, delta * 8.0)

# other AiScript nodes never block a raycast used for obstacle avoidance
func _cast_obstacle(world: RegolithWorld, from: Vector2, heading: float, length: float) -> float:
	var hit: Dictionary = world.ray_cast(from, from + Vector2.from_angle(heading) * length, self)

	if hit.is_empty() or hit["sprite"] is AiScript:
		return -1.0

	return float(hit["distance"])
