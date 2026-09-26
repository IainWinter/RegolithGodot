extends EnemyScripted
class_name EnemyBossCompass

# Boss1: the shell. the body here holds its spot and heading, throws what
# comes near through the EnemyThrower child, shields itself with rocks
# (EnemyBossShield), drags the player in with the trap (EnemyBossTrap),
# fires homing lightning bolts from a hull point and lets the final phase
# out of the hull. which phase it is in, what to spawn from which zone,
# which point to fire from and when the final phase leaves are
# res://game/lua/boss_compass.lua, told by the player and cell sensor
# children. the parts run their mechanics here each physics step, the
# script sets their active flags

@export var rock_props: RockProps
@export var thrower: EnemyThrower
@export var trap: EnemyBossTrap
@export var shield: EnemyBossShield
@export var align_torque := 0.5
@export var align_damping := 2.0
@export var hold_force := 0.5
@export var hold_damping := 2.0
# prefab hull points, -1..1 with y up
@export var fire_points: Array[Vector2] = [Vector2(0.85, -0.3), Vector2(-0.05, -0.55), Vector2(0.25, -0.55), Vector2(-0.45, -0.85)]
@export var fire_cooldown := 4.0
@export var detach_class := 4
@export var detach_local_position := Vector2(0.08, -0.35)

signal detached(final_phase: Node)

var hold_position := Vector2.ZERO
var hold_angle := 0.0

func _init() -> void:
	ai_class = "boss_compass"

func _ready() -> void:
	super()
	hold_position = global_position / Steering.ppu()
	hold_angle = global_rotation

func update_ai(delta: float) -> void:
	super(delta)

	if shield:
		shield.update(self, delta)

	if trap:
		trap.set_hull_box(self)
		trap.update(self, delta)

# the body keeping the spot and heading it spawned with
func hold_station(delta: float) -> void:
	align_angle(hold_angle, align_torque, align_damping, delta)
	align_position(hold_position, hold_force, hold_damping, delta)

# a shot from a prefab hull point, the weapon's origin rides along with it
func fire_from(local: Vector2, direction: Vector2) -> void:
	if weapon == null:
		return

	weapon.local_fire_origin = Vector2(local.x, -local.y) * Steering.half_extent_units(self)
	weapon.set_fire_state(true, direction)

# the final phase leaves: its cells come out of the hull and the stingray
# is placed there (a forced spawn inside the shell), the parts let go and
# the shell is a rock from here on
func detach_final_phase() -> void:
	if dead:
		return

	var count := get_cell_count()

	for y in count.y:
		for x in count.x:
			var cell := Vector2i(x, y)

			if has_cell(cell) and get_cell_class(cell) == detach_class:
				remove_cell(cell)

	var request := spawn(SpawnRequest.Kind.BOSS_STINGRAY, local_point_units(detach_local_position), Vector2.ZERO)
	request.rotation = global_rotation
	request.wait_for_room = false
	request.spawned.connect(func(final_phase: RegolithSprite): detached.emit(final_phase))

	if thrower:
		thrower.active = false
		thrower.step(0.0, pos)

	if trap:
		trap.active = false

	if shield:
		shield.active = false

	fire(false, Vector2.RIGHT)
	dead = true
	remove_from_group("enemy")
	remove_from_group("thrower")
