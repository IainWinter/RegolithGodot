extends GutTest

# the WarningLine telegraph: one node per scene, restarted by warn(), gone
# after its lifetime, and the stingray raises it before every dive

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var arena: Node2D
var world: RegolithWorld

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
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

func test_warn_makes_one_line_and_restarts_it() -> void:
	var line := WarningLine.warn(Vector2(0.0, 0.0), Vector2(100.0, 0.0), 0.5)
	assert_not_null(line)
	assert_true(line.active)
	assert_true(line.is_in_group("warning_line"))
	assert_eq(line.get_parent(), arena, "made under the world's parent")

	await wait_process_frames(3)
	var age := line.age
	assert_gt(age, 0.0)

	var again := WarningLine.warn(Vector2(0.0, 0.0), Vector2(0.0, 100.0), 2.0)
	assert_eq(again, line, "the same node serves again")
	assert_eq(line.end, Vector2(0.0, 100.0))
	assert_eq(line.lifetime, 2.0)
	assert_lt(line.age, age)
	assert_eq(get_tree().get_nodes_in_group("warning_line").size(), 1)

func test_line_ends_after_lifetime() -> void:
	var line := WarningLine.warn(Vector2(0.0, 0.0), Vector2(100.0, 0.0), 0.05)
	await wait_seconds(0.3)
	assert_false(line.active)
	assert_false(line.visible)
	assert_true(is_instance_valid(line), "node stays for the next warn")

func test_fade_and_pulse_alpha_stay_in_range() -> void:
	var line := WarningLine.warn(Vector2(0.0, 0.0), Vector2(100.0, 0.0), 1.0)
	line.age = 0.8
	assert_almost_eq(line.fade_of(0.5), 0.4, 0.001, "fades over the last fade_time")
	line.age = 0.1
	assert_eq(line.fade_of(0.5), 1.0)

	for i in 20:
		var alpha := line.glow_alpha(float(i) / 19.0, 3.0, 1.0)
		assert_between(alpha, line.props.glow_base_alpha - 0.001, line.props.glow_base_alpha + line.props.glow_pulse_alpha + 0.001)

func test_stingray_dive_raises_a_warning_line() -> void:
	var boss: EnemyBossStingray = load("res://game/scenes/enemies/EnemyBossStingray.tscn").instantiate()
	boss.position = Vector2(0.0, 0.0)
	arena.add_child(boss)
	await wait_physics_frames(2)

	# what the player sensor would report, then the script lines up a dive
	boss.receive({"kind": PlayerSensor.PLAYER_SEEN, "player": null, "position": Vector2(20.0, 0.0), "center": Vector2(20.0, 0.0), "velocity": Vector2.ZERO, "distance": 20.0, "in_sight": true})
	await wait_physics_frames(1)
	Ai.invoke(boss.ai_id, "start_prepare_dive", [Vector2.ZERO])

	var line := get_tree().get_first_node_in_group("warning_line") as WarningLine
	assert_not_null(line, "dive telegraph raised")
	assert_true(line.active)
	assert_eq(line.lifetime, boss.dive_warning_time)
	assert_eq(boss.state_machine.get_state(), "prepare_dive")
	assert_eq(Ai.lua.run("__probe = __instance(%d).dive.point" % boss.ai_id), "")
	var dive_point: Vector2 = Ai.lua.get_global("__probe")
	var ppu := RegolithWorld.pixels_per_unit()
	assert_gt(line.end.distance_to(line.begin), dive_point.length() * ppu, "line runs past the dive point")
