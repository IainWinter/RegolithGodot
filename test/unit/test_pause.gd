extends GutTest

# the GameState autoload: the pause action toggles PLAYING and PAUSED, the
# tree pauses with it and the pause menu comes and goes, the editor's own
# pause is left alone, the menu's buttons drive the state and take focus.
# pausing is a slide: the time scale lerps to zero on real time under the
# game audio sinking under water, so the tests wait for the state to land

var main: Node2D

func before_each() -> void:
	main = load("res://game/scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await wait_physics_frames(2)

func after_each() -> void:
	if GameState.state != GameState.State.PLAYING:
		GameState.set_state(GameState.State.PLAYING)
	GameState.settle_transition()
	get_tree().paused = false
	get_tree().current_scene = null
	if is_instance_valid(main):
		main.free()

func press_pause() -> void:
	var event := InputEventAction.new()
	event.action = GameState.PAUSE_ACTION
	event.pressed = true
	Input.parse_input_event(event)
	await wait_process_frames(2)
	event = InputEventAction.new()
	event.action = GameState.PAUSE_ACTION
	event.pressed = false
	Input.parse_input_event(event)
	await wait_process_frames(1)

# real time wait for the slide to land: the state reached and no lerp left
func settle(state: GameState.State, timeout := 2.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while (GameState.state != state or GameState.transition != null) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await wait_process_frames(1)

func test_starts_playing_and_unpaused() -> void:
	assert_eq(GameState.state, GameState.State.PLAYING)
	assert_false(get_tree().paused)
	assert_null(GameState.menu)

func test_pause_action_pauses_the_tree_and_shows_the_menu() -> void:
	var changes: Array = []
	GameState.state_changed.connect(func(from, to): changes.append([from, to]))

	await press_pause()
	assert_eq(GameState.state, GameState.State.PLAYING, "the slide is still running right after the press")
	assert_not_null(GameState.transition, "time scale lerp in flight")
	assert_gt(Sound.underwater, 0.0, "the audio starts sinking during the slide")
	await settle(GameState.State.PAUSED)

	assert_eq(GameState.state, GameState.State.PAUSED)
	assert_true(get_tree().paused, "tree paused")
	assert_eq(Engine.time_scale, 1.0, "time scale back to one once the tree holds the pause")
	assert_eq(GameState.PAUSE_FLOOR, 0.02, "the slide bottoms out just above zero, a zero time scale makes the physics interpolation NaN")
	assert_true(GameState.menu is PauseMenu, "pause menu on screen")
	assert_true(GameState.menu.is_inside_tree())
	assert_almost_eq(Sound.underwater, 1.0, 0.01, "audio fully under water")
	assert_lt(Sound.lowpass.cutoff_hz, 1000.0, "the World bus low pass is closed")
	assert_eq(AudioServer.get_bus_index(Sound.MENU_BUS) != -1, true, "menu sounds have their own bus")
	assert_eq(Sound.bus_for(&"ui_click"), Sound.MENU_BUS, "menu clicks stay clear")
	assert_eq(Sound.bus_for(&"explosion"), Sound.WORLD_BUS, "game sounds sink")
	assert_eq(changes, [[GameState.State.PLAYING, GameState.State.PAUSED]])

	await press_pause()
	await settle(GameState.State.PLAYING)

	assert_eq(GameState.state, GameState.State.PLAYING)
	assert_false(get_tree().paused, "tree running again")
	assert_eq(Engine.time_scale, 1.0, "time scale climbed back")
	assert_null(GameState.menu, "menu gone")
	assert_eq(Sound.underwater, 0.0, "audio surfaced")
	assert_gt(Sound.lowpass.cutoff_hz, 20000.0, "low pass open again")
	assert_eq(changes.size(), 2)
	assert_eq(changes[1], [GameState.State.PAUSED, GameState.State.PLAYING])

func test_paused_world_is_frozen() -> void:
	var rock: RegolithSprite = main.get_node("Rock")
	GameState.pause()
	await settle(GameState.State.PAUSED)
	var start := rock.global_position
	rock.linear_velocity = Vector2(5, 0)
	await wait_physics_frames(6)
	assert_eq(rock.global_position, start, "nothing moves while paused")

	GameState.resume()
	await wait_physics_frames(6)
	assert_ne(rock.global_position, start, "moves again after resume")

func test_menu_buttons_and_focus() -> void:
	GameState.pause()
	await settle(GameState.State.PAUSED)

	var menu: PauseMenu = GameState.menu
	assert_not_null(menu.button_named(&"Resume"))
	assert_true(menu.button_named(&"Options").disabled, "options is a placeholder")
	assert_true(menu.button_named(&"MainMenu").disabled, "main menu is a placeholder")
	assert_eq(menu.button_named(&"Options").focus_mode, Control.FOCUS_NONE, "placeholders are skipped by the cursor")
	assert_not_null(menu.button_named(&"Quit"))
	assert_true(menu.frame is Container, "one frame node to swap for the pipes")
	assert_eq(menu.focused_button(), menu.button_named(&"Resume"), "cursor starts on resume")

	# wrapping: up from resume lands on quit
	var resume := menu.button_named(&"Resume")
	assert_eq(resume.get_node(resume.focus_neighbor_top), menu.button_named(&"Quit"))
	assert_eq(resume.get_node(resume.focus_neighbor_bottom), menu.button_named(&"Controls"), "down from resume is the controls page")
	var controls := menu.button_named(&"Controls")
	assert_eq(controls.get_node(controls.focus_neighbor_bottom), menu.button_named(&"Quit"), "the placeholders in between are skipped")

	resume.pressed.emit()
	await wait_process_frames(1)
	assert_eq(GameState.state, GameState.State.PLAYING, "resume button resumes")
	assert_false(get_tree().paused)

func test_controls_page_lists_every_binding() -> void:
	GameState.pause()
	await settle(GameState.State.PAUSED)

	var menu: PauseMenu = GameState.menu
	menu.button_named(&"Controls").pressed.emit()
	await wait_process_frames(1)

	assert_true(menu.is_showing_controls(), "the controls page is up")
	assert_false(menu.frame.visible, "the buttons step aside")
	assert_eq(GameState.state, GameState.State.PAUSED, "still paused")
	for action in Controls.TABLE:
		assert_true(menu.controls_list.rows.has(action), "listed: %s" % action)
	var pause_row: HBoxContainer = menu.controls_list.rows[Controls.PAUSE]
	assert_string_contains((pause_row.get_node("Bindings") as Label).text, "Escape")
	assert_eq(menu.get_viewport().gui_get_focus_owner(), menu.back_button, "cursor on back")

	menu.back_button.pressed.emit()
	await wait_process_frames(1)
	assert_false(menu.is_showing_controls())
	assert_true(menu.frame.visible)
	assert_eq(menu.focused_button(), menu.button_named(&"Controls"), "back returns the cursor to controls")

func test_pause_key_goes_through_the_action() -> void:
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	assert_true(escape.is_action_pressed(GameState.PAUSE_ACTION), "escape is the pause action")
	GameState._unhandled_input(escape)
	await settle(GameState.State.PAUSED)
	assert_eq(GameState.state, GameState.State.PAUSED, "escape pauses")

func test_editor_pause_is_not_the_menu_pause() -> void:
	main.open_editor()
	await wait_process_frames(1)
	assert_true(get_tree().paused)
	assert_eq(GameState.state, GameState.State.PLAYING, "the editor pauses on its own")

	assert_false(GameState.toggle_pause(), "the pause action leaves the editor's pause alone")
	assert_null(GameState.menu)

	main.editor.close()
	await wait_process_frames(1)
	assert_false(get_tree().paused, "closing the editor resumes")

func test_menus_keep_processing_while_paused() -> void:
	GameState.pause()
	await settle(GameState.State.PAUSED)
	assert_true(GameState.menu.can_process(), "menu runs while paused")
	assert_true(GameState.can_process(), "state machine runs while paused")
	assert_true(main.get_node("Hotkeys").can_process(), "F2 / F3 keep working while paused")
	assert_false(main.can_process(), "the game itself is frozen")

# the split between game effects and menu effects: every particle node in
# the world branch inherits the pause, including the player cloud's own
func test_world_effects_freeze_and_menu_effects_run() -> void:
	var player: RegolithSprite = main.get_node("Player")
	var cloud: PlayerCloud = player.get_node("Cloud")
	cloud.enter()
	await wait_process_frames(2)

	var world_particles: Array = []
	for node in main.find_children("*", "GPUParticles2D", true, false):
		world_particles.append(node)
	assert_gt(world_particles.size(), 1, "cell particles and the cloud's own node")

	GameState.pause()
	await settle(GameState.State.PAUSED)

	for node in world_particles:
		if is_instance_valid(node):
			assert_false(node.can_process(), "%s stands still under the pause menu" % node.name)
			assert_ne(node.process_mode, Node.PROCESS_MODE_ALWAYS, "%s is a game effect, not a menu effect" % node.name)

	assert_almost_eq(Sound.underwater, 1.0, 0.01, "the game audio is under water")
	assert_true(GameState.menu.can_process(), "the menu keeps moving")

	GameState.resume()
	await settle(GameState.State.PLAYING)
	for node in world_particles:
		if is_instance_valid(node):
			assert_true(node.can_process(), "%s runs again" % node.name)

# the slide: time slows to a stop over PAUSE_FADE of real time, and the
# toggle is ignored while it runs
func test_pause_slows_time_to_a_stop_then_holds() -> void:
	GameState.pause()
	await wait_process_frames(1)
	assert_lt(Engine.time_scale, 1.0, "time is slowing")
	assert_gt(Engine.time_scale, 0.0, "but not stopped yet")
	assert_false(GameState.toggle_pause(), "no toggling mid slide")
	assert_false(get_tree().paused, "the tree still runs during the slide")
	await settle(GameState.State.PAUSED)
	assert_true(get_tree().paused)
	assert_eq(Engine.time_scale, 1.0)
	assert_eq(Sound.last_played, GameState.PAUSE_SOUND, "the pause sound played")
