extends Enemy
class_name EnemyBase

# AiBase + AiThrower: keeps upright and holds its spot until the player gets
# far, then picks a new spot around the player. meanwhile it grabs the bombs
# and small rocks that come near, parks them on its arc and flings them at
# the player

@export var thrower: EnemyThrower
@export var move_speed := 1.0
@export var move_accel := 1.0
@export var goal_interval := 25.0
@export var far_distance := 20.0
@export var align_torque := 0.5
@export var align_damping := 2.0

func _ready() -> void:
	super()
	thrower.threw.connect(func(node: RegolithSprite): threw.emit(node))

func update_ai(delta: float) -> void:
	align_angle(0.0, align_torque, align_damping, delta)

	if player == null:
		return

	var spot := roam_goal(delta, goal_interval, Vector2(16.0, 6.0), pos.distance_to(player_pos) > far_distance)

	if spot != Vector2.INF:
		force_move_to(spot, move_speed, move_accel, delta)

	thrower.update(delta)
