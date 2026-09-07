extends Enemy
class_name EnemyBossStingray

# AiBoss1FinalPhase: the core that leaves the shell. it orbits the player at
# a distance, lines up and dives past, dropping bombs and fighters or
# spraying volleys, rams the player when it can. a close pass starts a
# fight: it parks a screen away, cages the player with the trap, shields
# itself with rocks and pushes them out, sprays arcs, and spawns bombs and
# fighters, then swings around to orbit again

enum Mode { ORBIT, PREPARE_DIVE, DIVE, REPOSITION, FIGHT, AGGRESS }

@export var rock_props: RockProps
@export var arc_props: WeaponProps
@export var burst_props: WeaponProps
@export var trap: EnemyBossTrap
@export var shield: EnemyBossShield

@export var accel := 4.05
@export var turn_speed := 1.5
@export var roam_speed := 6.0
@export var roam_radius := 25.0

@export_group("Orbit")
@export var orbit_speed := 0.7
@export var orbit_roam_time := 12.0

@export_group("Dive")
@export var dive_speed := 16.0
@export var dive_overshoot := 15.0
@export var dive_tangent := 6.0
@export var dive_hit_impulse := 20.0
@export var dive_near_radius := 10.0
@export var dive_max_misses := 2
@export var dive_barrage_interval := 0.35
@export var dive_volley_small := 2
@export var dive_volley_big := 8
@export var dive_bomb_interval := 0.12
@export var dive_bombs_per_dive := 10

@export_group("Fight")
@export var fight_time := 16.0
@export var fight_offset_ratio := 1.0
@export var fight_angle := 0.0
@export var fight_arrive_radius := 3.0
@export var fight_trap_camera_scale := 1.5
@export var fight_return_time := 5.0
@export var fight_align_torque := 1.5
@export var fight_align_damping := 2.0
@export var fight_rock_count_min := 5
@export var fight_rock_count_max := 10
@export var fight_rock_speed := 2.0
@export var fight_push_speed := 3.0
@export var fight_spawn_band := 0.5
@export var fight_spawn_behind := 2.0
@export var fight_bomb_speed := 4.0
@export var fight_bomb_interval := 3.0
@export var fight_fighter_interval := 8.0
@export var fight_max_fighters := 4

@export_group("Aggress")
@export var aggress_speed := 14.0
@export var aggress_engage_radius := 8.0
@export var aggress_give_up_time := 12.0

@export_group("Reposition")
@export var reposition_clearance := 2.5

var mode := Mode.ORBIT
var arc_weapon: Weapon
var burst_weapon: Weapon
var fight_rock_props: RockProps

var active_zone := Vector2.ZERO
var camera_pos := Vector2.ZERO

var orbit_angle := 0.0
var roam_timer := 0.0

var dive_index := 0
var dive_miss_count := 0
var dive_closest := 0.0
var dive_point := Vector2.ZERO
var dive_mix_fighters := false
var dive_big_volley := false
var dive_volley_fired := false
var dive_barrage_timer := 0.0
var dive_bomb_timer := 0.0
var dive_bombs_dropped := 0
var dive_dropping_bombs := false

var fight_timer := 0.0
var fight_side := 1.0
var fight_position := Vector2.ZERO
var fight_rocks_spawned := false
var fight_rocks_pushed := false
var fight_bomb_timer := 0.0
var fight_fighter_timer := 0.0
var fight_spawned: Array = []
var fight_pending := 0

var aggress_timer := 0.0

var reposition_dir := 1.0
var reposition_target_angle := 0.0

func _ready() -> void:
	super()
	arc_weapon = make_weapon(arc_props, Vector2.ZERO)
	burst_weapon = make_weapon(burst_props, Vector2.ZERO)

	if rock_props:
		fight_rock_props = rock_props.duplicate()
		fight_rock_props.min_chunks = 1
		fight_rock_props.max_chunks = 1

static func camera_size() -> float:
	return float(RegolithWorld.CAMERA_HEIGHT)

func update_ai(delta: float) -> void:
	if player == null:
		return

	active_zone = Steering.camera_half_extents(self)
	camera_pos = Steering.camera_center(self, player_pos)

	arc_weapon.set_fire_state(false, Vector2.ZERO)

	match mode:
		Mode.PREPARE_DIVE:
			update_prepare_dive(delta)
		Mode.DIVE:
			update_dive(delta)
		Mode.FIGHT:
			update_fight(delta)
		Mode.REPOSITION:
			update_reposition(delta)
		Mode.AGGRESS:
			update_aggress(delta)
		_:
			update_orbit(delta)

	if trap:
		trap.update(self, delta)

	if shield:
		shield.update(self, delta)

func steer_toward_target(target: Vector2, speed: float, delta: float) -> void:
	turn_forward_toward(target, turn_speed, delta)
	linear_velocity = linear_velocity.lerp(forward() * speed, clampf(accel * delta, 0.0, 1.0))

func steer_fight(target: Vector2, speed: float, delta: float) -> void:
	align_angle(fight_angle, fight_align_torque, fight_align_damping, delta)
	linear_velocity = linear_velocity.lerp((target - pos).normalized() * speed, clampf(accel * delta, 0.0, 1.0))

func fire_burst(direction: Vector2, count: int) -> void:
	burst_weapon.set_fire_state(false, direction)

	for i in count:
		burst_weapon.fire()

func update_orbit(delta: float) -> void:
	orbit_angle = (pos - player_pos).angle() + orbit_speed
	roam_timer += delta

	if roam_timer >= orbit_roam_time:
		roam_timer = 0.0
		dive_miss_count = 0
		start_prepare_dive(pos + linear_velocity / maxf(accel, 0.01))

	steer_toward_target(player_pos + Vector2.from_angle(orbit_angle) * roam_radius, roam_speed, delta)

func start_prepare_dive(from: Vector2) -> void:
	mode = Mode.PREPARE_DIVE
	dive_index += 1
	dive_dropping_bombs = dive_index % 2 == 0
	dive_mix_fighters = randf() < 0.5
	dive_bombs_dropped = 0

	var direction := (player_pos - from).normalized()
	var tangent := Vector2(-direction.y, direction.x) * (1.0 if randf() < 0.5 else -1.0)
	var pass_point := player_pos + tangent * dive_tangent
	var dive_direction := (pass_point - from).normalized()

	dive_point = pass_point + dive_direction * dive_overshoot
	dive_big_volley = randf() < 0.5
	dive_volley_fired = false
	dive_closest = from.distance_to(player_pos)

func update_prepare_dive(delta: float) -> void:
	var want := (dive_point - pos).angle() + PI * 0.5
	var diff := Steering.wrap_angle(want - global_rotation)

	if absf(diff) < 0.1:
		dive_bomb_timer = 0.0
		dive_barrage_timer = 0.0
		mode = Mode.DIVE

	steer_toward_target(dive_point, 0.0, delta)

func update_dive(delta: float) -> void:
	dive_closest = minf(dive_closest, pos.distance_to(player_pos))

	var inside_camera := absf(pos.x - player_pos.x) < active_zone.x and absf(pos.y - player_pos.y) < active_zone.y

	if inside_camera and dive_dropping_bombs:
		dive_bomb_timer += delta

		if dive_bombs_dropped < dive_bombs_per_dive and dive_bomb_timer >= dive_bomb_interval:
			dive_bomb_timer = 0.0
			dive_bombs_dropped += 1

			var back := -linear_velocity.normalized()
			var spawn_pos := pos + back * (Steering.sprite_radius_units(self) + 0.2)
			var fighter := dive_mix_fighters and randf() < 0.5
			spawn(SpawnRequest.Kind.FIGHTER if fighter else SpawnRequest.Kind.BOMB, spawn_pos, back * 2.0)
	elif inside_camera:
		if dive_big_volley:
			if not dive_volley_fired:
				dive_volley_fired = true
				fire_burst(Vector2.RIGHT, dive_volley_big)
		else:
			dive_barrage_timer += delta

			if dive_barrage_timer >= dive_barrage_interval:
				dive_barrage_timer = 0.0
				fire_burst(Vector2.RIGHT, dive_volley_small)

	if pos.distance_to(player_pos) < Steering.sprite_radius_units(self) * 0.5 + Steering.sprite_radius_units(player):
		player.apply_impulse((player_pos - pos).normalized() * dive_hit_impulse, player.global_position)
		start_fight()
	elif (dive_point - pos).dot(forward()) < 0.0 or pos.distance_to(dive_point) < 1.5:
		if dive_closest > dive_near_radius:
			dive_miss_count += 1

			if dive_miss_count >= dive_max_misses:
				start_aggress()
			else:
				start_prepare_dive(pos)
		else:
			start_fight()

	steer_toward_target(dive_point, dive_speed, delta)

func start_aggress() -> void:
	mode = Mode.AGGRESS
	aggress_timer = 0.0

func update_aggress(delta: float) -> void:
	aggress_timer += delta

	if pos.distance_to(player_pos) < aggress_engage_radius or aggress_timer >= aggress_give_up_time:
		start_fight()
		return

	steer_toward_target(player_pos, aggress_speed, delta)

func start_fight() -> void:
	mode = Mode.FIGHT
	dive_miss_count = 0
	fight_side = 1.0 if pos.x >= player_pos.x else -1.0
	fight_timer = 0.0
	fight_bomb_timer = 0.0
	fight_fighter_timer = 0.0
	fight_position = player_pos + Vector2(fight_side * camera_size() * fight_offset_ratio, 0.0)
	fight_rocks_spawned = false
	fight_rocks_pushed = false

	if shield:
		shield.active = true

func end_fight() -> void:
	if trap:
		trap.active = false

	if shield:
		shield.active = false

	start_reposition()

func fight_offscreen_zone() -> Dictionary:
	var band := maxf(active_zone.x * fight_spawn_band, 0.5)
	return {
		"center": Vector2(camera_pos.x + fight_side * (active_zone.x + band), camera_pos.y),
		"half": Vector2(band, active_zone.y),
	}

func spawn_fight_rocks() -> void:
	if fight_rock_props == null:
		return

	var zone := fight_offscreen_zone()
	var count := randi_range(fight_rock_count_min, fight_rock_count_max)

	for i in count:
		var spawn_pos: Vector2 = Steering.random_in_box(zone["center"], zone["half"], 0.0)
		spawn_rock(fight_rock_props, spawn_pos, (fight_position - spawn_pos).normalized() * fight_rock_speed, true)

func on_fighter_spawned(fighter: RegolithSprite) -> void:
	fight_pending -= 1
	fight_spawned.append(fighter)
	fighter.died.connect(func(): fight_spawned.erase(fighter))

func update_fight(delta: float) -> void:
	var distance := pos.distance_to(fight_position)
	var trap_zone := active_zone * fight_trap_camera_scale
	var near_camera := absf(pos.x - camera_pos.x) < trap_zone.x and absf(pos.y - camera_pos.y) < trap_zone.y

	if trap:
		var size := camera_size()
		trap.active = near_camera and distance < fight_arrive_radius
		trap.set_box(Vector2(pos.x - fight_side * size, pos.y), Vector2.ONE * size * 0.8, 0.0)

	if distance >= fight_arrive_radius:
		steer_fight(fight_position, maxf(roam_speed, distance / maxf(fight_return_time, 0.1)), delta)
		return

	if not fight_rocks_spawned:
		fight_rocks_spawned = true
		spawn_fight_rocks()

	if not fight_rocks_pushed and fight_timer / fight_time >= 0.5:
		fight_rocks_pushed = true

		if shield:
			shield.push_rocks(pos, fight_push_speed)

	arc_weapon.set_fire_state(true, player_pos - pos)

	var zone := fight_offscreen_zone()

	fight_bomb_timer += delta

	if fight_bomb_timer >= fight_bomb_interval:
		fight_bomb_timer = 0.0
		var spawn_pos: Vector2 = Steering.random_in_box(zone["center"], zone["half"], 0.0)
		spawn(SpawnRequest.Kind.BOMB, spawn_pos, (player_pos - spawn_pos).normalized() * fight_bomb_speed, true)

	fight_fighter_timer += delta

	if fight_fighter_timer >= fight_fighter_interval:
		if fight_spawned.size() + fight_pending < fight_max_fighters:
			fight_fighter_timer = 0.0
			var behind := Steering.sprite_radius_units(self) + fight_spawn_behind
			var spawn_pos := pos + Vector2(fight_side * behind, 0.0) + Steering.random_in_circle(fight_spawn_behind)
			var request := spawn(SpawnRequest.Kind.FIGHTER, spawn_pos, Vector2.ZERO)
			fight_pending += 1
			request.spawned.connect(on_fighter_spawned)
			request.expired.connect(func(): fight_pending -= 1)

	fight_timer += delta

	if fight_timer >= fight_time:
		end_fight()

	steer_fight(fight_position, 0.0, delta)

func start_reposition() -> void:
	mode = Mode.REPOSITION
	orbit_angle = (pos - player_pos).angle()

	var radial := Vector2.from_angle(orbit_angle)
	reposition_dir = 1.0 if radial.cross(linear_velocity) >= 0.0 else -1.0

	var min_arc := PI * 0.5
	var step := TAU / 12.0
	var arc := min_arc + step * 11.0

	for i in 12:
		var candidate := min_arc + step * i
		var point := player_pos + Vector2.from_angle(orbit_angle + reposition_dir * candidate) * roam_radius

		if space_is_free(point, reposition_clearance):
			arc = candidate
			break

	reposition_target_angle = orbit_angle + reposition_dir * arc

func space_is_free(point: Vector2, clearance: float) -> bool:
	var world := RegolithWorld.active()

	if world == null:
		return true

	var scale := Steering.ppu()

	for sprite in Steering.sprites_near(world, point, clearance + 4.0):
		if sprite == self or sprite == player:
			continue

		if point.distance_to(sprite.global_position / scale) < clearance + Steering.sprite_radius_units(sprite):
			return false

	return true

func update_reposition(delta: float) -> void:
	var radius := maxf(roam_radius, 1.0)
	orbit_angle += reposition_dir * roam_speed / radius * delta

	if reposition_dir * (reposition_target_angle - orbit_angle) <= 0.0:
		roam_timer = 0.0
		mode = Mode.ORBIT

	steer_toward_target(player_pos + Vector2.from_angle(orbit_angle) * radius, roam_speed, delta)
