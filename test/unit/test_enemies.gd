extends GutTest

# Enemy ai: scenes load with cells, fighters chase and shoot, keep apart,
# bombs burst on the player, bases throw bombs, the boss runs its phases,
# the spawner fills the field

const SCENES := {
	"fighter": "res://game/scenes/enemies/EnemyFighter.tscn",
	"bomb": "res://game/scenes/enemies/EnemyBomb.tscn",
	"station": "res://game/scenes/enemies/EnemyStation.tscn",
	"base": "res://game/scenes/enemies/EnemyBase.tscn",
	"boss_compass": "res://game/scenes/enemies/EnemyBossCompass.tscn",
	"boss_stingray": "res://game/scenes/enemies/EnemyBossStingray.tscn",
}

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	arena.add_child(world)
	spawner = StableSpawner.new()
	spawner.fighter_scene = load(SCENES["fighter"])
	spawner.bomb_scene = load(SCENES["bomb"])
	spawner.station_scene = load(SCENES["station"])
	spawner.base_scene = load(SCENES["base"])
	spawner.boss_compass_scene = load(SCENES["boss_compass"])
	spawner.boss_stingray_scene = load(SCENES["boss_stingray"])
	arena.add_child(spawner)
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func add_player(units: Vector2) -> Player:
	var player: Player = load("res://game/scenes/player/Player.tscn").instantiate()
	player.position = units * ppu()
	player.set_process(false)
	arena.add_child(player)
	return player

func add_enemy(key: String, units: Vector2) -> Enemy:
	var enemy: Enemy = load(SCENES[key]).instantiate()
	enemy.position = units * ppu()
	arena.add_child(enemy)
	return enemy

func units_between(a: Node2D, b: Node2D) -> float:
	return a.global_position.distance_to(b.global_position) / ppu()

func test_enemy_scenes_load_with_cells() -> void:
	var enemies := {}
	var x := 0.0

	for key in SCENES:
		enemies[key] = add_enemy(key, Vector2(x, 0.0))
		x += 30.0

	await wait_physics_frames(3)

	for key in enemies:
		var enemy: Enemy = enemies[key]
		assert_gt(enemy.get_active_cell_count(), 0, "%s has cells" % key)
		assert_true(enemy.is_in_group("enemy"), "%s in group enemy" % key)
		assert_true(enemy.is_in_group("regolith"), "%s in group regolith" % key)

	assert_true(enemies["fighter"] is EnemyFighter)
	assert_true(enemies["bomb"] is EnemyBomb)
	assert_true(enemies["station"] is EnemyStation)
	assert_true(enemies["base"] is EnemyBase)
	assert_true(enemies["boss_compass"] is EnemyBossCompass)
	assert_true(enemies["base"].is_in_group("thrower"), "base in group thrower")
	assert_true(enemies["boss_compass"].is_in_group("thrower"), "boss in group thrower")
	assert_gt(enemies["boss_compass"].count_cells_of_type(RegolithSprite.CELL_WEAKPOINT1), 0, "boss has phase one weakpoints")
	assert_gt(enemies["boss_compass"].count_cells_of_type(RegolithSprite.CELL_WEAKPOINT2), 0, "boss has phase two weakpoints")

func test_fighter_moves_toward_player_and_fires() -> void:
	var player := add_player(Vector2.ZERO)
	var fighter: EnemyFighter = add_enemy("fighter", Vector2(12.0, 0.0))
	await wait_physics_frames(2)

	var counts := {"fired": 0}
	fighter.weapon.fired.connect(func(_bullet): counts["fired"] += 1)

	await wait_physics_frames(300)

	assert_lt(units_between(fighter, player), 10.0, "fighter closed into firing range")
	assert_gt(counts["fired"], 0, "fighter fired at the player")

func test_fighters_separate() -> void:
	var a: EnemyFighter = add_enemy("fighter", Vector2(0.0, 0.0))
	var b: EnemyFighter = add_enemy("fighter", Vector2(0.1, 0.0))
	await wait_physics_frames(90)

	assert_gt(units_between(a, b), 1.0, "overlapping fighters pushed apart")

func test_bomb_reaches_player_and_removes_cells() -> void:
	var player := add_player(Vector2.ZERO)
	var bomb: EnemyBomb = add_enemy("bomb", Vector2(8.0, 0.0))
	await wait_physics_frames(2)

	var counts := {"exploded": 0}
	bomb.exploded.connect(func(_position): counts["exploded"] += 1)
	var cells := player.get_active_cell_count()

	for i in 360:
		await wait_physics_frames(1)
		if counts["exploded"] > 0:
			break

	await wait_physics_frames(60)

	assert_eq(counts["exploded"], 1, "bomb exploded near the player")
	assert_lt(player.get_active_cell_count(), cells, "player lost cells")

func test_base_throws_nearby_bomb() -> void:
	var player := add_player(Vector2(10.0, 0.0))
	var base: EnemyBase = add_enemy("base", Vector2.ZERO)
	var bomb: EnemyBomb = add_enemy("bomb", Vector2(0.0, -2.0))
	await wait_physics_frames(2)

	var thrown := {}
	base.threw.connect(func(node):
		thrown["node"] = node
		thrown["velocity"] = node.linear_velocity
		thrown["to_player"] = (player.global_position - node.global_position).normalized())

	for i in 600:
		await wait_physics_frames(1)
		if not thrown.is_empty():
			break

	assert_false(thrown.is_empty(), "base threw something")
	if thrown.is_empty():
		return

	assert_eq(thrown["node"], bomb, "the bomb was thrown")
	assert_true(bomb.has_meta("thrown"), "the bomb is marked thrown")
	assert_gt(thrown["velocity"].length(), 3.0, "thrown fast")
	assert_gt(thrown["velocity"].normalized().dot(thrown["to_player"]), 0.5, "thrown at the player")

func remove_weakpoints(sprite: RegolithSprite, code: int) -> int:
	var mask := sprite.get_mask_image()
	var removed := 0

	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).g8 == code:
				sprite.remove_cell(Vector2i(x, y))
				removed += 1

	return removed

func test_boss_controller_advances_phases_and_spawns() -> void:
	add_player(Vector2.ZERO)
	var boss: EnemyBossCompass = add_enemy("boss_compass", Vector2(0.0, 30.0))
	await wait_physics_frames(2)

	boss.trap.active = false
	var controller := boss.controller
	controller.phases[0]["zones"][0]["interval"] = 0.5

	var spawned := {"count": 0}
	var phases: Array = []
	controller.spawned_enemy.connect(func(_enemy): spawned["count"] += 1)
	controller.phase_changed.connect(func(phase): phases.append(phase))
	watch_signals(controller)
	await wait_physics_frames(60)

	assert_eq(controller.phase, 0)
	assert_gt(spawned["count"], 0, "phase one spawned something")

	assert_gt(remove_weakpoints(boss, 250), 0, "removed phase one weakpoints")
	await wait_physics_frames(3)
	assert_eq(controller.phase, 1, "phase two after the weakpoints went")
	assert_eq(phases, [1], "the phase change was announced once")
	assert_false(boss.thrower.active, "phase two stops throwing")

	remove_weakpoints(boss, 251)
	await wait_physics_frames(3)

	assert_true(controller.finished, "phases done")
	assert_signal_emitted(controller, "phases_finished")
	assert_true(boss.dead, "the shell is a rock now")
	assert_false(boss.is_in_group("enemy"))

	var final_phase: EnemyBossStingray = null
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is EnemyBossStingray:
			final_phase = enemy

	assert_not_null(final_phase, "the final phase detached")
	if final_phase:
		await wait_physics_frames(3)
		assert_gt(final_phase.get_active_cell_count(), 0)

func test_station_moves_and_spawns() -> void:
	add_player(Vector2(30.0, 0.0))
	var station: EnemyStation = add_enemy("station", Vector2.ZERO)
	station.spawn_interval = 0.2
	await wait_physics_frames(60)

	assert_gt(station.linear_velocity.length(), 0.1, "station drifts to its goal")
	assert_gt(station.spawned.size(), 0, "station let something out")

func test_spawner_produces_each_type() -> void:
	add_player(Vector2.ZERO)

	var enemy_spawner := EnemySpawner.new()
	enemy_spawner.spawn_interval = 0.05
	enemy_spawner.max_count = 30
	arena.add_child(enemy_spawner)

	var seen: Array = []
	enemy_spawner.spawned.connect(func(enemy): seen.append(enemy))

	var frames := 0
	while frames < 600:
		await wait_physics_frames(10)
		frames += 10
		if seen.any(func(e): return e is EnemyFighter) and seen.any(func(e): return e is EnemyBomb) and seen.any(func(e): return e is EnemyStation) and seen.any(func(e): return e is EnemyBase):
			break

	assert_true(seen.any(func(e): return e is EnemyFighter), "spawned a fighter")
	assert_true(seen.any(func(e): return e is EnemyBomb), "spawned a bomb")
	assert_true(seen.any(func(e): return e is EnemyStation), "spawned a station")
	assert_true(seen.any(func(e): return e is EnemyBase), "spawned a base")
	assert_false(seen.any(func(e): return e is EnemyBossCompass), "the boss only spawns on request")
	assert_gt(enemy_spawner.enemies().size(), 4)
