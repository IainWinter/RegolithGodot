extends GutTest

# the boss shell (Boss1) on boss_compass.lua against BossController: the
# phase states, the zones spawning through the bus, phases moving on when
# the weakpoint cells of a type are gone, the thrower stopping in phase
# two, the final phase detaching as a spawn inside the hull, the bolts
# fired from a hull point and the thrower grabbing what drifts in

const SCENES := {
	"fighter": "res://game/scenes/enemies/EnemyFighter.tscn",
	"bomb": "res://game/scenes/enemies/EnemyBomb.tscn",
	"boss_compass": "res://game/scenes/enemies/EnemyBossCompass.tscn",
	"boss_stingray": "res://game/scenes/enemies/EnemyBossStingray.tscn",
}
const MESSAGE_SCENE := "res://game/scenes/ai/AiMessage.tscn"
const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner
var errors: Array = []

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
	spawner.boss_compass_scene = load(SCENES["boss_compass"])
	spawner.boss_stingray_scene = load(SCENES["boss_stingray"])
	spawner.message_scene = load(MESSAGE_SCENE)
	arena.add_child(spawner)
	errors.clear()
	Ai.script_error.connect(on_script_error)
	await wait_physics_frames(1)

func after_each() -> void:
	Ai.script_error.disconnect(on_script_error)
	get_tree().current_scene = null
	arena.free()
	Dialog.clear()

func on_script_error(where: String, message: String) -> void:
	errors.append("%s: %s" % [where, message])

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

func lua_value(boss: EnemyScripted, expression: String) -> Variant:
	assert_eq(Ai.lua.run("__probe = (function(self) return %s end)(__instance(%d))" % [expression, boss.ai_id]), "")
	return Ai.lua.get_global("__probe")

# the mask paints weakpoint one as 250 and two as 251 in the green channel
const MASK_WEAKPOINT1 := 250
const MASK_WEAKPOINT2 := 251

func remove_weakpoints(sprite: RegolithSprite, code: int) -> int:
	var mask := sprite.get_mask_image()
	var removed := 0

	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).g8 == code:
				sprite.remove_cell(Vector2i(x, y))
				removed += 1

	return removed

func test_shell_runs_boss_compass_lua_and_settles_into_phase_one() -> void:
	add_player(Vector2.ZERO)
	var boss: EnemyBossCompass = add_enemy("boss_compass", Vector2(0.0, 30.0))
	await wait_physics_frames(3)

	assert_eq(boss.ai_class, "boss_compass")
	assert_gt(boss.ai_id, 0, "a lua instance")
	assert_true(boss.is_in_group("thrower"))

	var states := boss.state_machine.get_states()

	for name in ["phase_1", "phase_2", "detached"]:
		assert_true(states.has(name), "state %s registered" % name)

	assert_eq(boss.state_machine.get_state(), "phase_1", "phase one while its weakpoints last")
	assert_eq(int(lua_value(boss, "self.phase")), 1)
	assert_eq(int(lua_value(boss, "self.phases[1].alive_type")), RegolithSprite.CELL_WEAKPOINT1)
	assert_eq(int(lua_value(boss, "self.phases[2].alive_type")), RegolithSprite.CELL_WEAKPOINT2)
	assert_true(boss.thrower.active, "phase one throws")
	assert_true(lua_value(boss, "self.weapon_active"), "phase one fires")
	assert_true(boss.shield.active)
	assert_true(boss.trap.active)
	assert_gt(Dialog.queued_texts().size() + (1 if Dialog.current_text() != "" else 0), 0, "a line at the phase change")
	assert_eq(errors, [])

func test_phases_advance_on_weakpoint_loss_and_the_final_phase_detaches() -> void:
	add_player(Vector2.ZERO)
	var boss: EnemyBossCompass = add_enemy("boss_compass", Vector2(0.0, 30.0))
	await wait_physics_frames(2)

	boss.trap.active = false
	assert_eq(Ai.lua.run("__instance(%d).phases[1].zones[1].interval = 0.5" % boss.ai_id), "")

	var spawned: Array = []
	spawner.spawned.connect(func(request: SpawnRequest, node: RegolithSprite):
		if request.ignore.has(boss) and not request.is_rock():
			spawned.append(node))
	var phases: Array = []
	boss.state_machine.state_changed.connect(func(_from: String, to: String): phases.append(to))
	watch_signals(boss)
	await wait_physics_frames(60)

	assert_eq(boss.state_machine.get_state(), "phase_1")
	assert_gt(spawned.size(), 0, "phase one spawned something through the bus")
	assert_true(spawned.all(func(e): return e is EnemyBomb), "phase one's zone only drops bombs")
	assert_eq(int(lua_value(boss, "#self.spawned")), spawned.size(), "the shell heard back about each placed spawn")

	for bomb in spawned:
		assert_gt(bomb.linear_velocity.length(), 0.5, "a spawned bomb leaves the hull moving")

	assert_gt(remove_weakpoints(boss, MASK_WEAKPOINT1), 0, "removed phase one weakpoints")
	await wait_physics_frames(3)
	assert_eq(boss.state_machine.get_state(), "phase_2", "phase two after the weakpoints went")
	assert_eq(phases, ["phase_2"], "the phase change was announced once")
	assert_false(boss.thrower.active, "phase two stops throwing")
	assert_true(lua_value(boss, "self.weapon_active"), "phase two still fires")

	remove_weakpoints(boss, MASK_WEAKPOINT2)
	await wait_physics_frames(3)

	assert_eq(boss.state_machine.get_state(), "detached", "phases done")
	assert_true(lua_value(boss, "self.finished"))
	assert_true(boss.dead, "the shell is a rock now")
	assert_false(boss.is_in_group("enemy"))
	assert_false(boss.is_in_group("thrower"))
	assert_false(boss.shield.active)
	assert_false(boss.trap.active)
	assert_eq(boss.count_cells_of_type(RegolithSprite.CELL_WEAKPOINT1) + boss.count_cells_of_type(RegolithSprite.CELL_WEAKPOINT2), 0)

	var final_phase: EnemyBossStingray = null
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is EnemyBossStingray:
			final_phase = enemy

	assert_not_null(final_phase, "the final phase detached as a spawn")
	assert_signal_emitted(boss, "detached")
	if final_phase:
		await wait_physics_frames(3)
		assert_gt(final_phase.get_active_cell_count(), 0)
		assert_eq(final_phase.ai_class, "boss_stingray")

	assert_eq(errors, [])

func test_shell_fires_bolts_from_a_hull_point_facing_the_player() -> void:
	# the prefab points all sit on the hull's lower side, the player goes there
	add_player(Vector2(0.0, 14.0))
	var boss: EnemyBossCompass = add_enemy("boss_compass", Vector2.ZERO)
	boss.trap.active = false
	await wait_physics_frames(5)

	assert_not_null(boss.weapon, "the bolt weapon comes from weapon_props")
	assert_true(boss.weapon.triggered, "trigger down with the player known")
	assert_ne(boss.weapon.local_fire_origin, Vector2.ZERO, "fires from a hull point, not the origin")

	var point: Vector2 = lua_value(boss, "self.fire_point")
	assert_true(boss.fire_points.has(point), "one of the prefab points")
	var to_player := boss.player_pos - boss.pos
	assert_gt((boss.local_point_units(point) - boss.pos).dot(to_player), 0.0, "a point on the player's side")
	assert_eq(errors, [])

func test_shell_grabs_a_bomb_that_drifts_into_the_thrower() -> void:
	add_player(Vector2(-40.0, 0.0))
	var boss: EnemyBossCompass = add_enemy("boss_compass", Vector2.ZERO)
	boss.trap.active = false
	await wait_physics_frames(2)

	var thrower := boss.thrower
	var grabbed := {"count": 0}
	thrower.grabbed.connect(func(_node): grabbed["count"] += 1)
	var center := thrower.center_units()
	var away := (center - boss.pos).normalized()
	var bomb: EnemyBomb = add_enemy("bomb", center + away * 1.5)

	for i in 300:
		await wait_physics_frames(1)
		if grabbed["count"] > 0:
			break

	assert_eq(grabbed["count"], 1, "the shell took hold of the bomb")
	assert_true(thrower.is_holding(bomb))
	assert_eq(Throwable.of(bomb).held_by, boss)
	assert_eq(int(lua_value(boss, "(function() local n = 0 for _ in pairs(self.hold_timers) do n = n + 1 end return n end)()")), 1, "a hold timer for it")
	assert_eq(errors, [])
