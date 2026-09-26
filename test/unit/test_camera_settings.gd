extends GutTest

# the camera controller port and the GameSettings autoload, the aim assist
# is in test_aim_assist.gd

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var arena: Node2D
var world: RegolithWorld

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)
	await wait_physics_frames(1)

func after_each() -> void:
	arena.free()

func add_block(at: Vector2, dynamic := true) -> RegolithSprite:
	var block := RegolithSprite.new()
	block.dynamic = dynamic
	block.position = at
	arena.add_child(block)
	block.create_blank(Vector2i(32, 32))
	block.fill_rect(Rect2i(0, 0, 32, 32), Color.WHITE, RegolithSprite.CELL_FILLED, 0)
	return block

func test_camera_leads_a_moving_target() -> void:
	var target := add_block(Vector2(100.0, 100.0))
	var camera := RegolithCamera.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.target = target
	camera.follow_speed = 100.0
	arena.add_child(camera)
	await wait_physics_frames(2)

	target.linear_velocity = Vector2(10.0, 0.0)
	await wait_physics_frames(30)

	# headless frames take microseconds, so the easing is stepped by hand
	for i in 10:
		camera._process(1.0 / 60.0)

	var ppu := RegolithWorld.pixels_per_unit()
	var lead := camera.global_position.x - target.get_center_of_mass().x
	assert_gt(lead, 0.0, "camera sits ahead of the target along its velocity")
	assert_lt(lead, 10.0 * ppu * camera.lookahead_time * 1.5, "lead is the lookahead time of travel")
	assert_almost_eq(camera.view_height, camera.height_units, 0.01, "a lone target never zooms out")

func test_camera_frames_extra_points_by_zooming_out() -> void:
	var target := add_block(Vector2(0.0, 0.0), false)
	var camera := RegolithCamera.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.target = target
	camera.follow_speed = 1000.0
	arena.add_child(camera)
	await wait_process_frames(2)

	var ppu := RegolithWorld.pixels_per_unit()
	var far := Vector2(0.0, camera.height_units * 3.0 * ppu)

	for i in 5:
		camera.frame_points = PackedVector2Array([far])
		camera._process(1.0 / 60.0)

	assert_gt(camera.view_height, camera.height_units * 1.5, "the view grew to keep the far point in")
	assert_gt(camera.global_position.y, 0.0, "the view slid toward the far point")

	for i in 5:
		camera._process(1.0 / 60.0)

	assert_almost_eq(camera.view_height, camera.height_units, 0.5, "the view shrinks back without points")

func test_game_settings_autoload_round_trips() -> void:
	var settings := get_node("/root/GameSettings")
	assert_not_null(settings)
	var before: bool = settings.aim_assist

	settings.aim_assist = false
	settings.volume = 42
	assert_eq(settings.save(), OK)

	settings.aim_assist = true
	settings.volume = 100
	settings.load_settings()
	assert_false(settings.aim_assist)
	assert_eq(settings.volume, 42)

	settings.aim_assist = before
	settings.volume = 100
	settings.save()
