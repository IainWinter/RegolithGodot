extends GutTest

# the death path: the player cloud's died signal moves GameState to DEAD,
# the tree pauses under the death menu, the cloud alarm stops and the dead
# song starts, Retry reloads the current scene and returns to PLAYING. the
# cloud that ships in Main.tscn is the one watched, through the real path:
# the core blowing or the hull going, then the cloud timer. a cloud outside
# the current scene (a test arena) never ends the game

var main: Node2D

func before_each() -> void:
	main = load("res://game/scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await wait_physics_frames(2)

func after_each() -> void:
	if GameState.state != GameState.State.PLAYING:
		GameState.set_state(GameState.State.PLAYING)
	get_tree().paused = false
	Sound.stop_all()
	var current := get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(current):
		current.free()
	if is_instance_valid(main) and main != current:
		main.free()

func player_node() -> Player:
	return get_tree().current_scene.get_node("Player")

func player_cloud() -> PlayerCloud:
	return player_node().cloud

# chews the player's core one cell a frame until the core blows, the way
# a gun does it
func blow_the_core() -> void:
	var player := player_node()
	var cloud := player.cloud
	var count := player.get_cell_count()

	for y in count.y:
		for x in count.x:
			if cloud.is_cloud:
				return
			if player.get_cell_type(Vector2i(x, y)) == RegolithSprite.CELL_CORE:
				player.remove_cell(Vector2i(x, y))
				await wait_physics_frames(2)

func alarm_players() -> int:
	var playing := 0
	for player in Sound.players:
		if player.playing and player.get_meta(&"sound", &"") == &"player_low_core":
			playing += 1
	return playing

func assert_dead_screen() -> void:
	assert_eq(GameState.state, GameState.State.DEAD)
	assert_false(get_tree().paused, "the world drifts on under the death menu, the burst keeps flying")
	assert_eq(Engine.time_scale, 1.0, "at full speed")
	assert_true(GameState.menu is DeathMenu, "death menu on screen")
	assert_true(GameState.menu.is_inside_tree())
	assert_eq(Sound.music_name, &"music_level_fail", "the dead song plays from the transition")
	assert_false(Sound.is_playing(&"player_low_core"), "the cloud alarm stopped")

func test_the_main_scene_cloud_blowing_and_timing_out_shows_the_death_menu() -> void:
	var changes: Array = []
	GameState.state_changed.connect(func(from, to): changes.append([from, to]))
	var cloud := player_cloud()
	var deaths := [0]
	cloud.died.connect(func(): deaths[0] += 1)

	await blow_the_core()
	assert_true(cloud.is_cloud, "the core blowing starts the cloud")
	assert_eq(Sound.last_played, &"player_low_core", "the cloud alarm starts with the cloud")
	assert_eq(alarm_players(), 1, "one alarm, the cloud is watched once")
	assert_eq(GameState.state, GameState.State.PLAYING, "alive while the timer runs")

	cloud.death_timer = cloud.death_time - 0.05
	await wait_physics_frames(6)
	await wait_process_frames(1)

	assert_eq(deaths[0], 1, "the timer killed the cloud")
	assert_dead_screen()
	assert_eq(changes, [[GameState.State.PLAYING, GameState.State.DEAD]])
	assert_false(is_instance_valid(player_node_or_null()), "player gone")

	var menu: DeathMenu = GameState.menu
	assert_not_null(menu.button_named(&"Retry"))
	assert_true(menu.button_named(&"MainMenu").disabled, "main menu is a placeholder")
	assert_not_null(menu.button_named(&"Quit"))
	assert_eq(menu.focused_button(), menu.button_named(&"Retry"), "cursor starts on retry")

func player_node_or_null() -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("Player") if scene else null

# the whole ship shredded in one commit, nothing left to count a core on
func test_the_hull_going_at_once_still_ends_the_game() -> void:
	var cloud := player_cloud()
	player_node().remove_all_cells()
	await wait_physics_frames(4)
	assert_true(cloud.is_cloud, "cloud from the shredded hull")
	assert_eq(GameState.state, GameState.State.PLAYING)

	cloud.death_timer = cloud.death_time - 0.05
	await wait_physics_frames(6)
	await wait_process_frames(1)
	assert_dead_screen()

func test_a_hit_on_the_cloud_after_invincibility_ends_the_game() -> void:
	var player := player_node()
	var cloud := player.cloud
	await blow_the_core()
	cloud.invincible_timer = 0.0

	player.remove_cell(first_hull_cell(player))
	await wait_physics_frames(4)
	await wait_process_frames(1)
	assert_dead_screen()

func first_hull_cell(player: RegolithSprite) -> Vector2i:
	var count := player.get_cell_count()
	for y in count.y:
		for x in count.x:
			if player.has_cell(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func test_watching_twice_wires_the_cloud_once() -> void:
	GameState.watch_existing_clouds()
	GameState.watch_cloud(player_cloud())
	player_cloud().enter()
	assert_eq(alarm_players(), 1, "one alarm")

func test_retry_reloads_the_scene_and_plays_again() -> void:
	var old_scene := get_tree().current_scene
	player_cloud().die()
	await wait_process_frames(2)
	assert_eq(GameState.state, GameState.State.DEAD)

	var menu: DeathMenu = GameState.menu
	menu.button_named(&"Retry").pressed.emit()
	await wait_process_frames(3)

	assert_eq(GameState.state, GameState.State.PLAYING, "retry plays again")
	assert_false(get_tree().paused, "tree running")
	assert_null(GameState.menu, "death menu gone")
	assert_eq(Sound.music_name, &"", "the dead song stopped")

	var fresh := get_tree().current_scene
	assert_not_null(fresh, "a current scene again")
	assert_ne(fresh, old_scene, "a fresh copy of the level")
	assert_false(is_instance_valid(old_scene), "the old level is gone")
	assert_not_null(fresh.get_node_or_null("Player"), "with a player")

	# the fresh player is watched too, dying again works
	await wait_physics_frames(2)
	player_cloud().die()
	await wait_process_frames(2)
	assert_eq(GameState.state, GameState.State.DEAD, "death is wired again after the reload")

func test_death_pauses_the_paused_game_too() -> void:
	GameState.pause()
	await wait_process_frames(1)
	player_cloud().die()
	await wait_process_frames(2)
	assert_eq(GameState.state, GameState.State.DEAD, "dying while paused still ends the game")
	assert_true(GameState.menu is DeathMenu)
	assert_false(get_tree().paused, "the pause lifts for the death screen")
	assert_eq(Engine.time_scale, 1.0, "no slide left over")

func test_a_cloud_outside_the_current_scene_does_not_end_the_game() -> void:
	var arena := Node2D.new()
	get_tree().root.add_child(arena)
	# a cloud on a plain node only warns about its parent, enough for the hook
	var stray := PlayerCloud.new()
	var host := Node2D.new()
	host.add_child(stray)
	arena.add_child(host)
	await wait_process_frames(1)

	stray.died.emit()
	await wait_process_frames(1)
	assert_eq(GameState.state, GameState.State.PLAYING, "only the current scene's player ends the game")

	arena.free()
