extends GutTest

# the stingray (Boss1 final phase) on boss_stingray.lua against
# AiBoss1FinalPhase: the states and how they start, limp ropes while it
# flies and held ropes in the fight, fight rocks of the original's cell
# counts, the player turning to cloud ending a fight with a ring of
# bullets, and the dive telegraph starting on the body. the body is
# EnemyBossStingray, the decisions are the lua class

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const BOSS_SCENE := "res://game/scenes/enemies/EnemyBossStingray.tscn"
const FIGHTER_SCENE := "res://game/scenes/enemies/EnemyFighter.tscn"
const BOMB_SCENE := "res://game/scenes/enemies/EnemyBomb.tscn"
const MESSAGE_SCENE := "res://game/scenes/ai/AiMessage.tscn"

const STATES := ["idle", "orbit", "prepare_dive", "dive", "aggress", "fight", "reposition"]

class FakeCloud extends Node:
	signal entered

class FakePlayer extends RegolithSprite:
	var cloud: Node

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner
var boss: EnemyBossStingray
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
	spawner.fighter_scene = load(FIGHTER_SCENE)
	spawner.bomb_scene = load(BOMB_SCENE)
	spawner.message_scene = load(MESSAGE_SCENE)
	arena.add_child(spawner)
	await wait_physics_frames(1)

	errors.clear()
	Ai.script_error.connect(on_script_error)

	boss = load(BOSS_SCENE).instantiate()
	arena.add_child(boss)
	await wait_physics_frames(2)

func after_each() -> void:
	Ai.script_error.disconnect(on_script_error)
	get_tree().current_scene = null
	arena.free()
	Dialog.clear()

func on_script_error(where: String, message: String) -> void:
	errors.append("%s: %s" % [where, message])

func state() -> String:
	return boss.state_machine.get_state()

# a value read off the lua instance, self is the instance
func lua_value(expression: String) -> Variant:
	assert_eq(Ai.lua.run("__probe = (function(self) return %s end)(__instance(%d))" % [expression, boss.ai_id]), "")
	return Ai.lua.get_global("__probe")

func make_player() -> FakePlayer:
	var player := FakePlayer.new()
	player.cloud = FakeCloud.new()
	player.add_child(player.cloud)
	player.position = Vector2(20.0, 0.0) * Steering.ppu()
	arena.add_child(player)
	boss.player = player
	return player

# what the player sensor would say, straight into the inbox
func report_player(player: FakePlayer, units: Vector2) -> void:
	boss.receive({
		"kind": PlayerSensor.PLAYER_SEEN,
		"player": player,
		"position": units,
		"center": units,
		"velocity": Vector2.ZERO,
		"distance": units.distance_to(boss.pos),
		"in_sight": true,
	})

func test_runs_boss_stingray_lua_with_its_states() -> void:
	assert_eq(boss.ai_class, "boss_stingray")
	assert_gt(boss.ai_id, 0, "a lua instance")

	var states := boss.state_machine.get_states()

	for name in STATES:
		assert_true(states.has(name), "state %s registered" % name)

	assert_eq(state(), "idle", "idle until the player sensor reports them")
	assert_eq(errors, [])

func test_player_report_starts_the_orbit() -> void:
	var player := make_player()
	report_player(player, Vector2(20.0, 0.0))
	await wait_physics_frames(2)

	assert_eq(state(), "orbit")
	assert_almost_eq(boss.rope_angle_stiffness, boss.rope_stiffness, 0.0001, "limp while it flies")
	assert_gt(boss.linear_velocity.length(), 0.0, "steering toward the ring")

	boss.receive({"kind": PlayerSensor.PLAYER_LOST})
	await wait_physics_frames(2)
	assert_eq(state(), "idle", "lost the player, idle again")
	assert_eq(errors, [])

func test_orbit_dives_after_orbit_roam_time() -> void:
	boss.orbit_roam_time = 0.05
	var player := make_player()
	report_player(player, Vector2(20.0, 0.0))

	for i in 120:
		await wait_physics_frames(1)
		if state() != "orbit":
			break

	assert_true(state() == "prepare_dive" or state() == "dive", "lined up a dive, got %s" % state())
	assert_eq(int(lua_value("self.dive.index")), 1, "the first dive")
	assert_not_null(get_tree().get_first_node_in_group("warning_line"), "the dive was telegraphed")
	assert_eq(errors, [])

func test_ropes_hang_limp_in_flight_and_hold_in_the_fight() -> void:
	assert_almost_eq(boss.rope_angle_stiffness, boss.rope_stiffness, 0.0001, "limp from the start")
	assert_almost_eq(boss.rope_stiffness, 0.02, 0.0001, "AiBoss1FinalPhase rope_stiffness")
	assert_almost_eq(boss.fight_rope_stiffness, 0.3, 0.0001, "AiBoss1Fight rope_stiffness")

	boss.steer_fight(Vector2.ZERO, 0.0, 1.0 / 60.0)
	assert_almost_eq(boss.rope_angle_stiffness, boss.fight_rope_stiffness, 0.0001, "held while anchored")

	boss.steer_toward_target(Vector2(10.0, 0.0), 1.0, 1.0 / 60.0)
	assert_almost_eq(boss.rope_angle_stiffness, boss.rope_stiffness, 0.0001, "limp again when it flies")

	# the states pick the steering: the fight anchors, orbit flies
	var player := make_player()
	report_player(player, Vector2(20.0, 0.0))
	await wait_physics_frames(1)
	Ai.invoke(boss.ai_id, "start_fight")
	await wait_physics_frames(1)
	assert_eq(state(), "fight")
	assert_almost_eq(boss.rope_angle_stiffness, boss.fight_rope_stiffness, 0.0001, "the fight state holds the ropes")
	assert_eq(errors, [])

func test_fight_rocks_match_the_original_cell_counts() -> void:
	assert_eq(boss.fight_rock_cells_min, 100)
	assert_eq(boss.fight_rock_cells_max, 300)

	for i in 50:
		assert_between(boss.fight_rock_cells(), 100, 300)

	var props := boss.fight_rock_props(200)
	assert_eq(props.min_chunks, 1)
	assert_eq(props.max_chunks, 1)
	assert_false(props.shape_variants)
	assert_eq(props.ore_chance, 0.0)
	assert_almost_eq(props.radius_scale, sqrt(200.0 / PI) / float(RockGenerator.CELLS), 0.0001, "a disc of about 200 cells in one chunk")
	assert_ne(props, boss.rock_props, "the shared props are untouched")

func test_fight_starts_beside_the_player_with_the_shield_on() -> void:
	var player := make_player()
	report_player(player, Vector2(20.0, 0.0))
	await wait_physics_frames(1)
	Ai.invoke(boss.ai_id, "start_fight")

	assert_eq(state(), "fight")
	assert_true(boss.shield.active, "start_fight turns the shield on")
	assert_eq(float(lua_value("self.fight.side")), -1.0, "the boss is left of the player")
	var fight_position: Vector2 = lua_value("self.fight.position")
	assert_almost_eq(fight_position, Vector2(20.0 - EnemyBossStingray.camera_size() * boss.fight_offset_ratio, 0.0), Vector2(0.01, 0.01), "a screen beside the player")
	assert_eq(errors, [])

func test_player_cloud_ends_the_fight_with_a_bullet_ring() -> void:
	var player := make_player()
	report_player(player, Vector2(20.0, 0.0))
	await wait_physics_frames(1)
	boss.watch_player()
	Ai.invoke(boss.ai_id, "start_fight")
	assert_eq(state(), "fight")
	assert_true(boss.shield.active)

	watch_signals(boss.burst_weapon)
	player.cloud.entered.emit()
	await wait_physics_frames(1)

	assert_eq(state(), "reposition", "the fight ends and it swings back to orbit")
	assert_false(boss.shield.active)
	assert_false(boss.trap.active)
	assert_signal_emit_count(boss.burst_weapon, "fired", boss.fight_kills_player_bullet_ring_count)
	assert_eq(errors, [])

func test_player_cloud_outside_a_fight_does_nothing() -> void:
	var player := make_player()
	report_player(player, Vector2(20.0, 0.0))
	await wait_physics_frames(1)
	boss.watch_player()
	assert_eq(state(), "orbit")

	watch_signals(boss.burst_weapon)
	player.cloud.entered.emit()
	await wait_physics_frames(1)

	assert_eq(state(), "orbit")
	assert_signal_not_emitted(boss.burst_weapon, "fired")
	assert_eq(errors, [])

func test_dive_telegraph_starts_on_the_body() -> void:
	var player := make_player()
	report_player(player, Vector2(20.0, 0.0))
	await wait_physics_frames(1)
	Ai.invoke(boss.ai_id, "start_prepare_dive")

	assert_eq(state(), "prepare_dive")
	var line := get_tree().get_first_node_in_group("warning_line") as WarningLine
	assert_not_null(line)
	assert_almost_eq(line.begin, EffectSpawner.effect_origin(boss), Vector2(0.01, 0.01), "from the body, not the padded node origin")
	assert_eq(line.lifetime, 2.5, "SpawnWarningLineEvent lifetime")
	assert_eq(line.material.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, "the original line configs are additive")

	var dive_point: Vector2 = lua_value("self.dive.point")
	var ppu := Steering.ppu()
	assert_gt(line.end.distance_to(line.begin), dive_point.distance_to(boss.pos) * ppu, "line runs past the dive point")
	assert_eq(errors, [])
