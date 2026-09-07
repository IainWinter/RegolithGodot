extends GutTest

# AiGizmos: with the debug drawer visible the enemy parts get their lines
# under the AI_* names, hiding the drawer draws nothing

var arena: Node2D
var world: RegolithWorld
var draw: RegolithDebugDraw

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	arena.add_child(world)
	draw = get_node("/root/DebugDraw")
	draw.visible = true
	draw.set_all_names_enabled(false)
	draw.set_name_enabled(RegolithDebugDraw.AI_THROWER, true)
	draw.set_name_enabled(RegolithDebugDraw.AI_SHIELD, true)
	draw.set_name_enabled(RegolithDebugDraw.AI_TRAP, true)

func after_each() -> void:
	draw.set_all_names_enabled(false)
	draw.set_name_enabled(RegolithDebugDraw.DEFAULT, true)
	draw.visible = false
	get_tree().current_scene = null
	arena.free()

func spawn(path: String) -> Enemy:
	var enemy: Enemy = load(path).instantiate()
	arena.add_child(enemy)
	return enemy

func peak_lines(frames := 3) -> int:
	var peak := 0
	for i in frames:
		await get_tree().process_frame
		peak = maxi(peak, draw.get_line_count())
	return peak

func test_names_exist() -> void:
	assert_eq(draw.get_name_label(RegolithDebugDraw.AI_THROWER), "AI_THROWER")
	assert_eq(draw.get_name_label(RegolithDebugDraw.AI_SHIELD), "AI_SHIELD")
	assert_eq(draw.get_name_label(RegolithDebugDraw.AI_TRAP), "AI_TRAP")

func test_base_thrower_draws() -> void:
	spawn("res://game/scenes/enemies/EnemyBase.tscn")
	await wait_physics_frames(2)
	assert_gt(await peak_lines(), 0)

func test_boss_parts_draw_per_name() -> void:
	spawn("res://game/scenes/enemies/EnemyBossCompass.tscn")
	await wait_physics_frames(2)
	var all_on := await peak_lines()
	assert_gt(all_on, 0)

	draw.set_name_enabled(RegolithDebugDraw.AI_THROWER, false)
	draw.set_name_enabled(RegolithDebugDraw.AI_SHIELD, false)
	var trap_only := await peak_lines()
	assert_gt(trap_only, 0, "trap box still drawn")
	assert_lt(trap_only, all_on, "thrower and shield dropped")

func test_hidden_drawer_draws_nothing() -> void:
	spawn("res://game/scenes/enemies/EnemyBossCompass.tscn")
	draw.visible = false
	await wait_physics_frames(2)
	assert_eq(await peak_lines(), 0)

func test_scene_walk_draws_from_exports_alone() -> void:
	# the editor path: no running scripts needed, just the nodes and their exports
	var boss := spawn("res://game/scenes/enemies/EnemyBossCompass.tscn")
	await wait_physics_frames(2)
	draw.visible = false
	await wait_process_frames(2)
	var gizmos: Node = draw.get_node("AiGizmos")
	gizmos.emit_scene(arena)
	var count := draw.collect()
	assert_gt(count, 0)
	assert_true(boss.is_loaded())
