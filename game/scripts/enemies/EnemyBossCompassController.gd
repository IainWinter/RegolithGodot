class_name EnemyBossCompassController
extends Node

# EnemyBossCompassController: the phases of the boss shell. each phase lasts while the
# weakpoint cells of its type last, spawns bombs and fighters from zones on
# the hull, and says what the shell does. the phases move on when the world
# takes cells off the host, the boss hears phase_changed and phases_finished
# and applies them. the boss calls update each physics step for the spawn
# clocks. zones are in the original's -1..1 local space

signal spawned_enemy(enemy: Node)
signal phase_changed(phase: int)
signal phases_finished

var phases: Array = [
	{
		"alive_type": RegolithSprite.CELL_WEAKPOINT1,
		"weapon_active": true,
		"thrower_active": true,
		"zones": [
			{"kind": "bomb", "max_alive": 3, "interval": 9.0, "burst": 1, "position": Vector2(-0.15, 1.1), "scale": Vector2(0.85, 0.6), "angle": -5.6, "timer": 0.0},
		],
	},
	{
		"alive_type": RegolithSprite.CELL_WEAKPOINT2,
		"weapon_active": true,
		"thrower_active": false,
		"zones": [
			{"kind": "bomb", "max_alive": 12, "interval": 7.0, "burst": 4, "position": Vector2(-0.65, 0.1), "scale": Vector2(0.4, 0.35), "angle": -5.6, "timer": 0.0},
			{"kind": "fighter", "max_alive": 6, "interval": 9.0, "burst": 3, "position": Vector2(-0.05, 0.85), "scale": Vector2(0.4, 0.4), "angle": -5.6, "timer": 0.0},
		],
	},
]

@export var rock_interval := 4.0
@export var rock_max_alive := 6
@export var rock_zone_position := Vector2(0.0, 2.8)
@export var rock_zone_scale := Vector2(1.8, 0.8)

var host: EnemyBossCompass
var phase := 0
var finished := false
var settled := false
var spawned: Array = []
var rocks_spawned: Array = []
var pending := 0
var rocks_pending := 0
var rock_timer := 0.0

func _ready() -> void:
	host = get_parent() as EnemyBossCompass

	var world := RegolithWorld.active()

	if world:
		world.cells_removed.connect(on_cells_removed)
		world.sprite_split.connect(on_sprite_split)

func current_phase() -> Dictionary:
	return phases[phase] if phase < phases.size() else {}

func weapon_active() -> bool:
	return current_phase().get("weapon_active", false)

func thrower_active() -> bool:
	return current_phase().get("thrower_active", false)

func on_cells_removed(sprite: RegolithSprite, _count: int) -> void:
	if sprite == host:
		advance_phases()

func on_sprite_split(source: RegolithSprite, _piece: RegolithSprite) -> void:
	if source == host:
		advance_phases()

func advance_phases(announce := false) -> void:
	if finished or host == null or not host.is_loaded():
		return

	var start := phase

	while phase < phases.size() and host.count_cells_of_type(phases[phase]["alive_type"]) == 0:
		phase += 1

	if phase >= phases.size():
		finished = true
		phases_finished.emit()
	elif phase != start or announce:
		phase_changed.emit(phase)

func update(host_node: EnemyBossCompass, delta: float) -> void:
	host = host_node

	if not settled:
		settled = true
		advance_phases(true)

	if finished:
		return

	rock_timer += delta

	if rock_timer >= rock_interval:
		rock_timer = 0.0
		Steering.prune_dead(rocks_spawned)

		if host.rock_props and rocks_spawned.size() + rocks_pending < rock_max_alive:
			var request := host.spawn_rock(host.rock_props, zone_point(host, rock_zone_position, rock_zone_scale, 0.0), Vector2.ZERO)
			rocks_pending += 1
			request.spawned.connect(func(rock: RegolithSprite): rocks_pending -= 1; rocks_spawned.append(rock))
			request.expired.connect(func(): rocks_pending -= 1)

	for zone in phases[phase]["zones"]:
		zone["timer"] += delta

		if zone["timer"] < zone["interval"]:
			continue

		zone["timer"] = 0.0

		var kind := SpawnRequest.Kind.BOMB if zone["kind"] == "bomb" else SpawnRequest.Kind.FIGHTER

		for b in zone["burst"]:
			if spawned.size() + pending >= zone["max_alive"]:
				break

			var spawn_pos := zone_point(host, zone["position"], zone["scale"], zone["angle"])
			var request := host.spawn(kind, spawn_pos, Vector2.ZERO)
			pending += 1
			request.spawned.connect(func(enemy: RegolithSprite): on_spawned(enemy, spawn_pos))
			request.expired.connect(func(): pending -= 1)

func on_spawned(enemy: RegolithSprite, spawn_pos: Vector2) -> void:
	pending -= 1

	if enemy is EnemyBomb:
		enemy.linear_velocity = (spawn_pos - host.pos).normalized() * enemy.speed

	spawned.append(enemy)
	enemy.died.connect(func(): spawned.erase(enemy))
	spawned_enemy.emit(enemy)

func zone_point(host: EnemyBossCompass, position: Vector2, scale: Vector2, angle: float) -> Vector2:
	var center := host.local_point_units(position)
	var half := scale * Steering.half_extent_units(host)
	return Steering.random_in_box(center, half, host.global_rotation - angle)
