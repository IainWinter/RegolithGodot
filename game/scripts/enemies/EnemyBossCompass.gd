extends Enemy
class_name EnemyBossCompass

# Boss1: the shell. holds its spot and heading, throws what comes near,
# shields itself with rocks, drags the player in with the trap and fires
# homing lightning bolts from a hull point facing the player. the
# EnemyBossCompassController child runs the phases and spawns, and detaches the final
# phase once the weakpoints are gone

@export var rock_props: RockProps
@export var weapon_props: WeaponProps
@export var controller: EnemyBossCompassController
@export var thrower: EnemyThrower
@export var trap: EnemyBossTrap
@export var shield: EnemyBossShield
@export var align_torque := 0.5
@export var align_damping := 2.0
@export var hold_force := 0.5
@export var hold_damping := 2.0
@export var fire_points: Array[Vector2] = [Vector2(0.85, -0.3), Vector2(-0.05, -0.55), Vector2(0.25, -0.55), Vector2(-0.45, -0.85)]
@export var fire_cooldown := 4.0
@export var detach_class := 4
@export var detach_local_position := Vector2(0.08, -0.35)

signal detached(final_phase: Node)

var weapon: Weapon
var weapon_enabled := true
var hold_position := Vector2.ZERO
var hold_angle := 0.0
var fire_timer := 0.0
var fire_point_current := Vector2.ZERO

func _ready() -> void:
	super()
	hold_position = global_position / Steering.ppu()
	hold_angle = global_rotation
	weapon = make_weapon(weapon_props, Vector2.ZERO)

	if not fire_points.is_empty():
		fire_point_current = fire_points[0]

	if controller:
		controller.phase_changed.connect(on_phase_changed)
		controller.phases_finished.connect(detach_final_phase, CONNECT_DEFERRED)

	thrower.threw.connect(func(node: RegolithSprite): threw.emit(node))

func on_phase_changed(_phase: int) -> void:
	thrower.active = controller.thrower_active()
	weapon_enabled = controller.weapon_active()

func update_ai(delta: float) -> void:
	align_angle(hold_angle, align_torque, align_damping, delta)
	align_position(hold_position, hold_force, hold_damping, delta)

	if controller:
		controller.update(self, delta)

	thrower.update(delta)

	if shield:
		shield.update(self, delta)

	if trap:
		trap.set_hull_box(self)
		trap.update(self, delta)

	update_fire(delta)

func update_fire(delta: float) -> void:
	var can_fire := player != null and weapon_enabled and not fire_points.is_empty()

	if not can_fire:
		weapon.set_fire_state(false, Vector2.RIGHT)
		return

	fire_timer -= delta

	if fire_timer <= 0.0:
		fire_timer = fire_cooldown
		pick_fire_point()

	var from_units := local_point_units(fire_point_current)
	weapon.local_fire_origin = Vector2(fire_point_current.x, -fire_point_current.y) * Steering.half_extent_units(self)
	weapon.set_fire_state(true, player_pos - from_units)

func pick_fire_point() -> void:
	var to_player := player_pos - pos
	var front: Array = []

	for local in fire_points:
		if (local_point_units(local) - pos).dot(to_player) > 0.0:
			front.append(local)

	if not front.is_empty():
		fire_point_current = front[randi() % front.size()]

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

	thrower.active = false
	thrower.update(0.0)

	if trap:
		trap.active = false

	if shield:
		shield.active = false

	dead = true
	remove_from_group("enemy")
	remove_from_group("thrower")
