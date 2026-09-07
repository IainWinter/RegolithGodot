extends GutTest

# Player in the main scene: sprite loads with a core, moves on input, dashes

var main: Node2D
var player: Player

func before_each() -> void:
	main = load("res://game/scenes/Main.tscn").instantiate()
	add_child_autofree(main)
	player = main.get_node("Player")
	await wait_physics_frames(3)

func after_each() -> void:
	Input.action_release("move_right")
	Input.action_release("move_up")

func test_player_sprite_loads_with_core() -> void:
	assert_gt(player.get_active_cell_count(), 0)
	assert_gt(player.count_cells_of_type(RegolithSprite.CELL_CORE), 0)
	assert_gt(player.count_cells_of_type(RegolithSprite.CELL_FILLED), 0)
	assert_true(player.is_repairable())
	assert_true(player.is_angle_fixed())

	var core := Vector2i(-1, -1)
	for y in 16:
		for x in 16:
			if player.get_cell_type(Vector2i(x, y)) == RegolithSprite.CELL_CORE:
				core = Vector2i(x, y)
	assert_ne(core, Vector2i(-1, -1), "a core cell exists in the 16x16 sprite")
	assert_gt(player.get_cell_color(core).a, 0.0)

func test_move_right_action_moves_player() -> void:
	var start := player.global_position
	Input.action_press("move_right")
	await wait_physics_frames(60)
	Input.action_release("move_right")
	var moved := player.global_position - start
	assert_gt(moved.x, 10.0, "moved right")
	assert_almost_eq(player.global_rotation, 0.0, 0.01, "angle fixed keeps rotation")

func test_dash_adds_impulse_and_starts_cooldown() -> void:
	Input.action_press("move_up")
	await wait_physics_frames(1)
	var before := player.linear_velocity

	var dash := InputEventAction.new()
	dash.action = "dash"
	dash.pressed = true
	Input.parse_input_event(dash)
	await wait_physics_frames(2)

	assert_gt(player.dash_timer, 0.0, "cooldown running")
	assert_lt(player.linear_velocity.y, before.y - 1.0, "dash pushed up")
	Input.action_release("move_up")

func test_losing_the_core_emits_core_destroyed_once() -> void:
	watch_signals(player)
	var count := player.get_cell_count()

	for y in count.y:
		for x in count.x:
			if player.get_cell_type(Vector2i(x, y)) == RegolithSprite.CELL_CORE:
				player.remove_cell(Vector2i(x, y))

	await wait_physics_frames(6)

	assert_eq(player.count_cells_of_type(RegolithSprite.CELL_CORE), 0)
	assert_gt(player.get_active_cell_count(), 0, "the hull is still there")
	assert_signal_emit_count(player, "core_destroyed", 1)
