extends GutTest

# Enemy ai: scenes load with cells, fighters chase and shoot, keep apart,
# bombs burst on the player, bases grab and throw bombs, stations drift,
# shoot and let fighters and bombs out, the boss runs its phases, the
# spawner fills the field. base, station and both boss phases are
# EnemyScripted hosts running base.lua, station.lua, boss_compass.lua and
# boss_stingray.lua

const SCENES := {
	"fighter": "res://game/scenes/enemies/EnemyFighter.tscn",
	"bomb": "res://game/scenes/enemies/EnemyBomb.tscn",
	"station": "res://game/scenes/enemies/EnemyStation.tscn",
	"base": "res://game/scenes/enemies/EnemyBase.tscn",
	"boss_compass": "res://game/scenes/enemies/EnemyBossCompass.tscn",
	"boss_stingray": "res://game/scenes/enemies/EnemyBossStingray.tscn",
}
const MESSAGE_SCENE := "res://game/scenes/ai/AiMessage.tscn"
const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)
	spawner = StableSpawner.new()
	spawner.fighter_scene = load(SCENES["fighter"])
	spawner.bomb_scene = load(SCENES["bomb"])
	spawner.station_scene = load(SCENES["station"])
	spawner.base_scene = load(SCENES["base"])
	spawner.boss_compass_scene = load(SCENES["boss_compass"])
	spawner.boss_stingray_scene = load(SCENES["boss_stingray"])
	spawner.message_scene = load(MESSAGE_SCENE)
	arena.add_child(spawner)
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()
	Dialog.clear()

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

# a scripted enemy with tunables set before it enters the tree
func add_scripted(key: String, units: Vector2, config: Dictionary) -> EnemyScripted:
	var enemy: EnemyScripted = load(SCENES[key]).instantiate()
	enemy.position = units * ppu()
	enemy.ai_config = config
	arena.add_child(enemy)
	return enemy

func units_between(a: Node2D, b: Node2D) -> float:
	return a.global_position.distance_to(b.global_position) / ppu()

func is_scripted(node: Node, ai_class: String) -> bool:
	return node is EnemyScripted and node.ai_class == ai_class

# a number read off the lua instance behind a scripted enemy, self is the instance
func lua_number(enemy: EnemyScripted, expression: String) -> float:
	assert_eq(Ai.lua.run("__probe = (function(self) return %s end)(__instance(%d))" % [expression, enemy.ai_id]), "")
	var value: Variant = Ai.lua.get_global("__probe")
	return float(value) if value is float or value is int else -1.0

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
	assert_true(is_scripted(enemies["station"], "station"), "station runs station.lua")
	assert_true(is_scripted(enemies["base"], "base"), "base runs base.lua")
	assert_true(enemies["boss_compass"] is EnemyBossCompass)
	assert_true(is_scripted(enemies["boss_compass"], "boss_compass"), "the shell runs boss_compass.lua")
	assert_true(is_scripted(enemies["boss_stingray"], "boss_stingray"), "the stingray runs boss_stingray.lua")
	assert_gt(enemies["station"].ai_id, 0, "station has a lua instance")
	assert_gt(enemies["base"].ai_id, 0, "base has a lua instance")
	assert_not_null(enemies["station"].weapon, "station carries its cannon")
	assert_not_null(enemies["base"].get_thrower(), "base carries its thrower")
	assert_not_null(Items.drop_table_for(enemies["base"]), "base keeps the original drop table")
	assert_not_null(Items.drop_table_for(enemies["station"]), "station keeps the original drop table")
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
	var base: EnemyScripted = add_enemy("base", Vector2.ZERO)
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
	assert_true(Throwable.of(bomb).thrown, "the bomb is marked thrown")
	assert_gt(thrown["velocity"].length(), 3.0, "thrown fast")
	assert_gt(thrown["velocity"].normalized().dot(thrown["to_player"]), 0.5, "thrown at the player")
	assert_true(bomb.exploding, "a thrown bomb fuses to burst on arrival")
	assert_eq(base.state_machine.get_state(), "throw", "player inside the throw radius")

func test_base_holds_what_it_grabs_until_the_player_is_close() -> void:
	add_player(Vector2(40.0, 0.0))
	var base: EnemyScripted = add_enemy("base", Vector2.ZERO)
	# the grab can land on the very first step, listen before it
	var thrower := base.get_thrower()
	var grabbed := {"count": 0}
	thrower.grabbed.connect(func(_node): grabbed["count"] += 1)
	var bomb: EnemyBomb = add_enemy("bomb", Vector2(0.0, -2.0))

	for i in 300:
		await wait_physics_frames(1)
		if grabbed["count"] > 0:
			break

	assert_eq(grabbed["count"], 1, "base took hold of the bomb")
	assert_true(thrower.is_holding(bomb))
	assert_eq(Throwable.of(bomb).held_by, base, "the bomb knows its holder")
	assert_eq(base.state_machine.get_state(), "guard", "player outside the throw radius, it holds")

	await wait_physics_frames(int(thrower.hold_time * 60.0) + 30)
	assert_true(thrower.is_holding(bomb), "still held, the player never came close")
	assert_false(Throwable.of(bomb).thrown)
	assert_lt(units_between(base, bomb), thrower.radius_max + 1.5, "parked on the ring")

# the boss shell runs boss_compass.lua, the phases themselves are in
# test_boss_compass.gd
func test_boss_shell_runs_its_phases_in_lua() -> void:
	add_player(Vector2.ZERO)
	var boss: EnemyBossCompass = add_enemy("boss_compass", Vector2(0.0, 30.0))
	await wait_physics_frames(3)

	assert_true(is_scripted(boss, "boss_compass"), "the shell runs boss_compass.lua")
	assert_gt(boss.ai_id, 0, "the shell has a lua instance")
	assert_eq(boss.state_machine.get_state(), "phase_1", "phase one while its weakpoints last")
	assert_true(boss.thrower.active, "phase one throws")

func test_station_moves_and_spawns() -> void:
	add_player(Vector2(30.0, 0.0))
	var station := add_scripted("station", Vector2.ZERO, {"spawn_interval": 0.2})

	var launched: Array = []
	spawner.spawned.connect(func(request: SpawnRequest, node: RegolithSprite):
		if request.ignore.has(station):
			launched.append(node))

	await wait_physics_frames(60)

	assert_eq(station.state_machine.get_state(), "roam", "no base around, roams near the player")
	assert_gt(station.linear_velocity.length(), 0.1, "station drifts to its goal")
	assert_gt(launched.size(), 0, "station let something out through the bus")
	assert_true(launched.all(func(e): return e is EnemyFighter or e is EnemyBomb), "fighters and bombs only")
	assert_eq(lua_number(station, "#self.spawned"), float(launched.size()), "the station heard back about each placed spawn")
	assert_gte(lua_number(station, "self.pending"), 0.0, "what waits for room is still pending")

func test_station_stops_at_its_cap() -> void:
	add_player(Vector2(30.0, 0.0))
	var station := add_scripted("station", Vector2.ZERO, {"spawn_interval": 0.1, "max_spawned": 2})

	var launched := {"count": 0}
	spawner.spawned.connect(func(request: SpawnRequest, _node: RegolithSprite):
		if request.ignore.has(station):
			launched["count"] += 1)

	await wait_physics_frames(120)
	assert_eq(launched["count"], 2, "two out, then it waits for them to die")

func test_station_fires_at_the_player_in_range() -> void:
	add_player(Vector2(6.0, 0.0))
	var station := add_scripted("station", Vector2.ZERO, {"spawn_interval": 1000.0})
	await wait_physics_frames(2)

	var shots := {"count": 0}
	station.weapon.fired.connect(func(_bullet): shots["count"] += 1)

	for i in 240:
		await wait_physics_frames(1)
		if shots["count"] > 0:
			break

	assert_true(station.weapon.triggered, "player in range with a clear line, trigger down")
	assert_gt(shots["count"], 0, "station fired")

func test_station_escorts_a_base_with_room() -> void:
	add_player(Vector2(40.0, 0.0))
	var base: EnemyScripted = add_enemy("base", Vector2(10.0, 0.0))
	var station := add_scripted("station", Vector2.ZERO, {"spawn_interval": 1000.0})
	await wait_physics_frames(5)

	assert_eq(station.state_machine.get_state(), "escort", "a base nearer than the player")
	var thrower := base.get_thrower()
	var standoff: Vector2 = thrower.center + (thrower.center - Vector2(40.0, 0.0)).normalized() * 8.0
	var start := station.global_position.distance_to(standoff * ppu())
	await wait_physics_frames(120)
	assert_lt(station.global_position.distance_to(standoff * ppu()), start, "closing on the standoff spot behind the base")

	thrower.active = false
	await wait_physics_frames(5)
	assert_eq(station.state_machine.get_state(), "roam", "a base with no room is not escorted")

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
		if seen.any(func(e): return e is EnemyFighter) and seen.any(func(e): return e is EnemyBomb) and seen.any(func(e): return is_scripted(e, "station")) and seen.any(func(e): return is_scripted(e, "base")):
			break

	assert_true(seen.any(func(e): return e is EnemyFighter), "spawned a fighter")
	assert_true(seen.any(func(e): return e is EnemyBomb), "spawned a bomb")
	assert_true(seen.any(func(e): return is_scripted(e, "station")), "spawned a station")
	assert_true(seen.any(func(e): return is_scripted(e, "base")), "spawned a base")
	assert_false(seen.any(func(e): return e is EnemyBossCompass), "the boss only spawns on request")
	assert_gte(enemy_spawner.enemies().size(), 4, "one of each kind at least")
