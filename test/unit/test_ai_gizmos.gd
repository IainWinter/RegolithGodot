extends GutTest

# with the debug drawer visible the enemy parts push their draw_gizmos
# shapes into the AI_* lists, hiding the drawer draws nothing. spawns a
# local GizmoWalker under the test's drawer, same as the autoload does

const GizmoWalker := preload("res://addons/regolith_debug/GizmoWalker.gd")

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
	draw = RegolithDebugDraw.new()
	draw.set_all_names_enabled(false)
	draw.set_name_enabled(RegolithDebugDraw.AI_THROWER, true)
	draw.set_name_enabled(RegolithDebugDraw.AI_SHIELD, true)
	draw.set_name_enabled(RegolithDebugDraw.AI_TRAP, true)
	world.add_child(draw)
	var walker := GizmoWalker.new()
	walker.draw = draw
	draw.add_child(walker)

func after_each() -> void:
	draw.set_all_names_enabled(false)
	draw.set_name_enabled(RegolithDebugDraw.DEFAULT, true)
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
