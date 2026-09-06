extends GutTest

# debug lines: a RegolithDebugDraw in the scene draws what the solver and
# the world emit when their names are enabled, scripts can add lines of
# their own for one frame, hiding it draws nothing, and the monitors report
# the world

var world: RegolithWorld
var draw: RegolithDebugDraw

func before_each() -> void:
	world = RegolithWorld.new()
	world.pixels_per_cell = 3
	add_child_autofree(world)

	draw = RegolithDebugDraw.new()
	draw.name = "DebugDraw"
	world.add_child(draw)

func after_each() -> void:
	# names and layers are global state, leave them how they started
	draw.set_all_names_enabled(false)
	draw.set_name_enabled(RegolithDebugDraw.DEFAULT, true)
	get_tree().paused = false

func spawn_block(at: Vector2) -> RegolithSprite:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.4, 0.2, 1.0))
	var block := RegolithSprite.new()
	block.texture = ImageTexture.create_from_image(img)
	block.dynamic = false
	block.position = at
	add_child_autofree(block)
	return block

# lines added between frames land one or two frames later depending on where
# in the frame the test resumed, so look at the most seen over a few frames
func peak_lines(frames := 3) -> int:
	var peak := 0
	for i in frames:
		await get_tree().process_frame
		peak = maxi(peak, draw.get_line_count())
	return peak

func test_drawer_joins_its_group_and_knows_every_name() -> void:
	assert_true(draw.is_in_group("regolith_debug_draw"))
	assert_eq(draw.get_name_label(RegolithDebugDraw.PHYSICS_CONTACT_POINT), "PHYSICS_CONTACT_POINT")
	assert_gt(draw.get_name_count(), RegolithDebugDraw.EXPLOSION_FORCE)

func test_script_lines_draw_for_one_frame() -> void:
	draw.add_line(Vector2(0, 0), Vector2(10, 10))
	draw.add_rect(Rect2(0, 0, 10, 10))
	assert_eq(await peak_lines(), 5, "a line and a box")
	assert_eq(await peak_lines(), 0, "per frame lines are dropped once drawn")

func test_disabled_names_drop_at_emit() -> void:
	draw.set_name_enabled(RegolithDebugDraw.AI_PATH, false)
	draw.add_line(Vector2(0, 0), Vector2(10, 10), RegolithDebugDraw.AI_PATH)
	assert_eq(await peak_lines(), 0)

	draw.set_name_enabled(RegolithDebugDraw.AI_PATH, true)
	draw.set_name_color(RegolithDebugDraw.AI_PATH, Color(1, 0, 0))
	assert_true(draw.is_name_enabled(RegolithDebugDraw.AI_PATH))
	assert_eq(draw.get_name_color(RegolithDebugDraw.AI_PATH), Color(1, 0, 0))
	draw.add_line(Vector2(0, 0), Vector2(10, 10), RegolithDebugDraw.AI_PATH)
	assert_eq(await peak_lines(), 1)

func test_world_draws_sprite_quads_when_asked() -> void:
	draw.set_all_names_enabled(false)
	spawn_block(Vector2(100, 100))
	await wait_physics_frames(2)
	assert_eq(await peak_lines(), 0, "nothing enabled, nothing drawn")

	draw.set_name_enabled(RegolithDebugDraw.SPRITE, true)
	assert_eq(await peak_lines(), 4, "one quad per sprite")

func test_solver_lines_reach_the_drawer() -> void:
	draw.set_all_names_enabled(false)
	draw.set_name_enabled(RegolithDebugDraw.PHYSICS_BROADPHASE_OVERLAP_WORLD_BOUNDS, true)
	spawn_block(Vector2(100, 100))
	await wait_physics_frames(2)
	assert_eq(await peak_lines(), 4, "the proxy's extended box from the fixed list")

func test_hidden_drawer_draws_nothing() -> void:
	draw.set_name_enabled(RegolithDebugDraw.SPRITE, true)
	spawn_block(Vector2(100, 100))
	await wait_physics_frames(2)
	assert_gt(await peak_lines(), 0)

	draw.visible = false
	await wait_physics_frames(2)
	await wait_process_frames(2)
	assert_eq(draw.get_line_count(), 0)

	draw.visible = true
	assert_gt(await peak_lines(), 0, "showing it again brings the lines back")

func test_monitors_report_the_world() -> void:
	spawn_block(Vector2(100, 100))
	await wait_physics_frames(2)
	await wait_process_frames(1)
	assert_true(Performance.has_custom_monitor("regolith/sprites"))
	assert_eq(int(Performance.get_custom_monitor("regolith/sprites")), 1)
	assert_true(Performance.has_custom_monitor("regolith/physics_ms"))
	assert_gte(world.get_physics_time_ms(), 0.0)

func test_panel_shows_the_scene_drawer_and_steps() -> void:
	draw.visible = false
	var panel = load("res://scenes/debug/DebugPanel.gd").new(world)
	add_child_autofree(panel)
	await wait_process_frames(2)
	assert_same(panel.draw, draw, "the scene's drawer, not a new one")
	assert_true(draw.visible, "opening the panel shows it")
	assert_eq(panel.name_checks.size(), draw.get_name_count())

	get_tree().paused = true
	panel.step_once()
	await wait_process_frames(3)
	assert_true(get_tree().paused, "step holds again after one tick")

	panel.free()
	assert_false(draw.visible, "closing the panel hides it again")

func test_panel_makes_a_drawer_when_the_scene_has_none() -> void:
	world.remove_child(draw)
	draw.free()
	var panel = load("res://scenes/debug/DebugPanel.gd").new(world)
	add_child_autofree(panel)
	await wait_process_frames(2)
	draw = panel.draw
	assert_true(draw is RegolithDebugDraw)
	assert_same(world.get_node_or_null("DebugDraw"), draw)
