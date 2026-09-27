extends Node
class_name StingrayBehavior

# a component under the boss stingray's AiScript scene. owns its two
# weapons (homing arc + burst ring), the fight rock props, the trap and
# shield refs, and the rope-stiffness plumbing. boss_stingray.lua reads
# self.parts = self.node:get_node("StingrayBehavior") and calls fire_arc,
# fire_burst, watch_player, fight_rock_props, space_is_free, and the trap
# and shield accessors on it. the host's AiScript stays generic

@export var rock_props: RockProps
@export var arc_props: WeaponProps
@export var burst_props: WeaponProps
@export var trap: EnemyBossTrap
@export var shield: EnemyBossShield
@export var default_rope_stiffness := 0.02

# what the body tells its script, mirrors message_types.lua
const PLAYER_ENTERED_CLOUD := "player_entered_cloud"

var host: AiScript
var arc_weapon: Weapon
var burst_weapon: Weapon
var rope_stiffness_current := -1.0
var watched_player: RegolithSprite

func _ready() -> void:
	host = get_parent() as AiScript

	if host == null:
		push_warning("StingrayBehavior: parent is not an AiScript")
		return

	# make_weapon does add_child on host; deferred because when this
	# runs the host is still processing its scene children and add_child
	# fires "parent is busy setting up children"
	call_deferred("_build_weapons")
	set_rope_stiffness(default_rope_stiffness)

func _build_weapons() -> void:
	if host == null or arc_weapon != null:
		return

	arc_weapon = host.make_weapon(arc_props, Vector2.ZERO)
	burst_weapon = host.make_weapon(burst_props, Vector2.ZERO)

# SpriteRopeSet.angle_stiffness of the original, exposed by RegolithSprite
# as rope_angle_stiffness
func set_rope_stiffness(value: float) -> void:
	if host == null or rope_stiffness_current == value:
		return

	rope_stiffness_current = value
	host.rope_angle_stiffness = value

# PlayerEnteredCloudStateEvent: the player turning to cloud lands in the
# host's inbox, the script decides what it means
func watch_player() -> void:
	if host == null or host.player == null or host.player == watched_player:
		return

	watched_player = host.player
	var cloud: Object = host.player.get("cloud")

	if cloud and cloud.has_signal(&"entered"):
		cloud.entered.connect(func(): host.receive({"kind": PLAYER_ENTERED_CLOUD}))

# the original steers from the centers of mass, the node origin sits at
# the padded grid center. this per-tick hook keeps pos/player_pos on the
# center-of-mass instead of the grid origin the AiScript uses
func _physics_process(_delta: float) -> void:
	if host == null or host.dead or not host.is_loaded():
		return

	var ppu := Steering.ppu()
	host.pos = host.get_center_of_mass() / ppu

	if host.player and host.player.is_loaded():
		host.player_pos = host.player.get_center_of_mass() / ppu

	watch_player()

	if host.player == null:
		return

	if trap:
		trap.update(host, _delta)

	if shield:
		shield.update(host, _delta)

func fire_arc(pull_trigger: bool, direction: Vector2) -> void:
	if arc_weapon:
		arc_weapon.set_fire_state(pull_trigger, direction)

func fire_burst(direction: Vector2, count: int) -> void:
	if burst_weapon == null:
		return

	burst_weapon.set_fire_state(false, direction)
	burst_weapon.fire(count, TAU)

# one chunk rocks of the given cells, biased small like the original's
# t cubed, plain shape and no ore
func fight_rock_props(cells: int) -> RockProps:
	var props: RockProps = rock_props.duplicate()
	props.min_chunks = 1
	props.max_chunks = 1
	props.shape_variants = false
	props.ore_chance = 0.0
	props.radius_scale = sqrt(float(cells) / PI) / float(RockGenerator.CELLS)
	return props

# flying: turn the nose to a target and pull the velocity toward it, the
# ropes go limp. reads accel and turn_speed off the host's ai_config /
# settings so boss_stingray.lua can keep the old three-arg call shape
func steer_toward_target(target: Vector2, speed: float, delta: float) -> void:
	set_rope_stiffness(default_rope_stiffness)
	var accel: float = host.get_setting(&"accel", 4.05)
	var turn_speed: float = host.get_setting(&"turn_speed", 1.5)
	host.steer_toward_target(target, speed, accel, turn_speed, delta)

# anchored: hold the fight heading and slide to the target, ropes stiff
func steer_fight(target: Vector2, speed: float, delta: float) -> void:
	var fight_stiffness: float = host.get_setting(&"fight_rope_stiffness", 0.3)
	set_rope_stiffness(fight_stiffness)
	var accel: float = host.get_setting(&"accel", 4.05)
	var plant_angle: float = host.get_setting(&"fight_angle", 0.0)
	var align_torque: float = host.get_setting(&"fight_align_torque", 1.5)
	var align_damping: float = host.get_setting(&"fight_align_damping", 2.0)
	host.steer_planted(target, speed, accel, plant_angle, align_torque, align_damping, delta)

# nothing but the player and the host within clearance of the point
func space_is_free(point: Vector2, clearance: float) -> bool:
	var world := RegolithWorld.active()

	if world == null or host == null:
		return true

	var scale := Steering.ppu()

	for sprite in Steering.sprites_near(world, point, clearance + 4.0):
		if sprite == host or sprite == host.player:
			continue

		if point.distance_to(sprite.global_position / scale) < clearance + Steering.sprite_radius_units(sprite):
			return false

	return true
