extends Node2D
class_name EnemySpawner

# EnemySpawner: every interval, while under the cap, asks the bus for an
# enemy just outside the camera view around the player. kinds come from a
# shuffled bag so every kind shows up. the boss spawns on request only,
# spawn(SpawnRequest.Kind.BOSS_COMPASS, position). the StableSpawner finds the room

@export var enabled := true
@export var spawn_interval := 10.0
@export var max_count := 8
@export var padding := 2.0
@export var kinds: Array[SpawnRequest.Kind] = [SpawnRequest.Kind.FIGHTER, SpawnRequest.Kind.BOMB, SpawnRequest.Kind.STATION, SpawnRequest.Kind.BASE]

signal spawned(enemy: Enemy)

var timer := 0.0
var bag: Array[SpawnRequest.Kind] = []
var pending := 0

func _physics_process(delta: float) -> void:
	if not enabled:
		return

	timer += delta

	if timer < spawn_interval:
		return

	timer = 0.0
	spawn_random()

func enemies() -> Array:
	return get_tree().get_nodes_in_group("enemy").filter(func(n): return n is Enemy and not n.dead)

func next_kind() -> SpawnRequest.Kind:
	if bag.is_empty():
		bag = kinds.duplicate()
		bag.shuffle()

	return bag.pop_back()

func spawn_random() -> SpawnRequest:
	if enemies().size() + pending >= max_count:
		return null

	var player := Steering.find_player(get_tree())

	if player == null:
		return null

	var center := player.global_position / Steering.ppu()
	var extent := Steering.camera_half_extents(self)
	return spawn(next_kind(), center + Steering.random_outside_box(extent, Vector2.ONE * padding))

func spawn(kind: SpawnRequest.Kind, position: Vector2) -> SpawnRequest:
	var request := SpawnBus.spawn(kind, position, Vector2.ZERO, true)
	pending += 1
	request.spawned.connect(on_spawned)
	request.expired.connect(func(): pending -= 1)
	return request

func on_spawned(node: RegolithSprite) -> void:
	pending -= 1

	if node is Enemy:
		spawned.emit(node)
