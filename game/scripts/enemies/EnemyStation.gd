extends Enemy
class_name EnemyStation

# AiStation: drifts to the nearest base with room for more, standing off on
# the far side from the player, else to a spot around the player. every few
# seconds it lets out a fighter or a bomb, and it shoots at the player in range

@export var weapon_props: WeaponProps
@export var move_speed := 1.0
@export var move_accel := 1.0
@export var goal_interval := 25.0
@export var standoff_distance := 8.0
@export var spawn_interval := 4.0
@export var max_spawned := 8
@export var spawn_origin := Vector2(-0.29686213, -0.2961769)
@export var fire_radius := 10.0

var weapon: Weapon
var spawn_timer := 0.0
var spawned: Array = []
var pending := 0

const SPAWN_OFFSETS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT]

func _ready() -> void:
	super()
	weapon = make_weapon(weapon_props, Vector2.ZERO)

func update_ai(delta: float) -> void:
	if player == null:
		return

	var thrower := nearest_thrower(pos, pos.distance_squared_to(player_pos))

	if thrower:
		goal = thrower.center + (thrower.center - player_pos).normalized() * standoff_distance
	else:
		roam_goal(delta, goal_interval)

	if goal != Vector2.INF:
		force_move_to(goal, move_speed, move_accel, delta)

	var to_player := player_pos - pos
	weapon.set_fire_state(to_player.length() < fire_radius and has_line_of_sight(pos, player_pos), to_player)

	spawn_timer += delta

	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		spawn_one()

func spawn_one() -> void:
	if spawned.size() + pending >= max_spawned:
		return

	var kind := SpawnRequest.Kind.FIGHTER if randi() % 2 == 0 else SpawnRequest.Kind.BOMB
	var offset := SPAWN_OFFSETS[randi() % SPAWN_OFFSETS.size()].rotated(global_rotation)
	var request := spawn(kind, local_point_units(spawn_origin) + offset * 0.5, offset * 2.0)
	pending += 1
	request.spawned.connect(on_spawned)
	request.expired.connect(func(): pending -= 1)

func on_spawned(node: RegolithSprite) -> void:
	pending -= 1
	spawned.append(node)
	node.died.connect(func(): spawned.erase(node))
