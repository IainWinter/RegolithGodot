extends EnemyScripted
class_name EnemyBossStingray

# AiBoss1FinalPhase: the core that leaves the shell. the body here: the
# two weapons (homing arcs and the burst ring), steering that hangs the
# ropes limp in flight and holds them in the fight, the ram, the fight
# rock sizing, the watch on the player's cloud and the trap and shield
# parts. the states (orbit, prepare_dive, dive, aggress, fight,
# reposition) and every decision are res://game/lua/boss_stingray.lua,
# fed by the player sensor child and the cloud message from watch_player.
# the numbers stay as exports the script reads

@export var rock_props: RockProps
@export var arc_props: WeaponProps
@export var burst_props: WeaponProps
@export var trap: EnemyBossTrap
@export var shield: EnemyBossShield

@export var accel := 4.05
@export var turn_speed := 1.5
@export var roam_speed := 6.0
@export var roam_radius := 25.0
# the ropes hang limp while it flies and hold their shape in the fight
@export var rope_stiffness := 0.02

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
@export var dive_warning_time := 2.5

@export_group("Fight")
@export var fight_time := 16.0
@export var fight_offset_ratio := 1.0
@export var fight_angle := 0.0
@export var fight_arrive_radius := 3.0
@export var fight_trap_camera_scale := 1.5
@export var fight_return_time := 5.0
@export var fight_align_torque := 1.5
@export var fight_align_damping := 2.0
@export var fight_rope_stiffness := 0.3
@export var fight_rock_count_min := 5
@export var fight_rock_count_max := 10
@export var fight_rock_cells_min := 100
@export var fight_rock_cells_max := 300
@export var fight_rock_speed := 2.0
@export var fight_push_speed := 3.0
@export var fight_spawn_band := 0.5
@export var fight_spawn_behind := 2.0
@export var fight_bomb_speed := 4.0
@export var fight_bomb_interval := 3.0
@export var fight_fighter_interval := 8.0
@export var fight_max_fighters := 4
@export var fight_kills_player_bullet_ring_count := 8

@export_group("Aggress")
@export var aggress_speed := 14.0
@export var aggress_engage_radius := 8.0
@export var aggress_give_up_time := 12.0

@export_group("Reposition")
@export var reposition_clearance := 2.5

# what the body tells its script, mirrors message_types.lua
const PLAYER_ENTERED_CLOUD := "player_entered_cloud"

var arc_weapon: Weapon
var burst_weapon: Weapon
var rope_stiffness_current := -1.0
var watched_player: RegolithSprite

func _init() -> void:
	ai_class = "boss_stingray"

func _ready() -> void:
	super()
	arc_weapon = make_weapon(arc_props, Vector2.ZERO)
	burst_weapon = make_weapon(burst_props, Vector2.ZERO)
	set_rope_stiffness(rope_stiffness)

static func camera_size() -> float:
	return float(RegolithWorld.CAMERA_HEIGHT)

# SpriteRopeSet.angle_stiffness of the original, exposed by RegolithSprite
# as rope_angle_stiffness
func set_rope_stiffness(value: float) -> void:
	if rope_stiffness_current == value:
		return

	rope_stiffness_current = value
	rope_angle_stiffness = value

# PlayerEnteredCloudStateEvent: the player turning to cloud lands in the
# inbox, the script decides what it means
func watch_player() -> void:
	if player == null or player == watched_player:
		return

	watched_player = player
	var cloud: Object = player.get("cloud")

	if cloud and cloud.has_signal(&"entered"):
		cloud.entered.connect(func(): receive({"kind": PLAYER_ENTERED_CLOUD}))

# the original steers from the centers of mass, the node origin sits at
# the padded grid center
func update_ai(delta: float) -> void:
	var ppu := Steering.ppu()
	pos = get_center_of_mass() / ppu

	if player and player.is_loaded():
		player_pos = player.get_center_of_mass() / ppu

	watch_player()
	super(delta)

	if player == null:
		return

	if trap:
		trap.update(self, delta)

	if shield:
		shield.update(self, delta)

# flying: turn the nose to the target and pull the velocity toward it,
# ropes limp
func steer_toward_target(target: Vector2, speed: float, delta: float) -> void:
	set_rope_stiffness(rope_stiffness)
	turn_forward_toward(target, turn_speed, delta)
	linear_velocity = linear_velocity.lerp(forward() * speed, clampf(accel * delta, 0.0, 1.0))

# anchored: hold the fight angle and slide to the target, ropes stiff
func steer_fight(target: Vector2, speed: float, delta: float) -> void:
	set_rope_stiffness(fight_rope_stiffness)
	align_angle(fight_angle, fight_align_torque, fight_align_damping, delta)
	linear_velocity = linear_velocity.lerp((target - pos).normalized() * speed, clampf(accel * delta, 0.0, 1.0))

func fire_arc(pull_trigger: bool, direction: Vector2) -> void:
	arc_weapon.set_fire_state(pull_trigger, direction)

func fire_burst(direction: Vector2, count: int) -> void:
	burst_weapon.set_fire_state(false, direction)
	burst_weapon.fire(count, TAU)

# the dive touches the player when the centers come within half this
# body's radius plus theirs
func touching(target: RegolithSprite) -> bool:
	if not is_instance_valid(target):
		return false

	return pos.distance_to(player_pos) < Steering.sprite_radius_units(self) * 0.5 + Steering.sprite_radius_units(target)

# the ContactEvent of the original: an explosion at the hit and a shove
func ram(target: RegolithSprite) -> void:
	if not is_instance_valid(target):
		return

	var direction := (player_pos - pos).normalized()
	var effects := EffectSpawner.active()

	if effects:
		effects.explosion((pos + direction * Steering.sprite_radius_units(self) * 0.5) * Steering.ppu())

	target.apply_impulse(direction * dive_hit_impulse, target.get_center_of_mass())

# one chunk rocks of fight_rock_cells_min..max cells, biased small like the
# original's t cubed, plain shape and no ore
func fight_rock_props(cells: int) -> RockProps:
	var props: RockProps = rock_props.duplicate()
	props.min_chunks = 1
	props.max_chunks = 1
	props.shape_variants = false
	props.ore_chance = 0.0
	props.radius_scale = sqrt(float(cells) / PI) / float(RockGenerator.CELLS)
	return props

func fight_rock_cells() -> int:
	var t := randf()
	return fight_rock_cells_min + int((fight_rock_cells_max - fight_rock_cells_min) * t * t * t)

# nothing but the player and this body within clearance of the point
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
