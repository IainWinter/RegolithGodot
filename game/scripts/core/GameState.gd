extends Node

# the GameState autoload, the state machine that owns get_tree().paused.
# PLAYING runs the game, PAUSED freezes it under the pause menu, DEAD puts
# the death menu over a world that keeps drifting (the player's burst flies
# on), MENU is reserved for the main menu to come. the pause action toggles
# PLAYING and PAUSED, the player cloud's died signal moves to DEAD, the
# death menu's Retry reloads the current scene and goes back to PLAYING.
#
# pausing is a PAUSE_FADE long slide: the time scale lerps to zero on real
# time while the game audio sinks under water (Sound.underwater closes a
# low pass on the World bus, menu sounds stay clear), then the tree pauses
# and the menu opens. resuming unpauses and lerps time and audio back.
# everything in the world branch inherits the pause (particles included),
# the menus and this node are PROCESS_MODE_ALWAYS, so menu effects run
# while game effects stand still.
# the menus are scenes instantiated under this node on entry and freed on
# exit, so they survive the scene reload. the sprite editor pauses the tree
# on its own while the state stays PLAYING, the toggle leaves that alone

enum State { PLAYING, PAUSED, DEAD, MENU }

signal state_changed(from: State, to: State)

const PAUSE_MENU := preload("res://game/scenes/ui/PauseMenu.tscn")
const DEATH_MENU := preload("res://game/scenes/ui/DeathMenu.tscn")

const PAUSE_ACTION := Controls.PAUSE
const PAUSE_SOUND := &"ui_pause"
# seconds of real time the time scale takes to reach zero, and to come back
const PAUSE_FADE := 0.2
# the slide stops just short of zero: at a time scale of exactly zero the
# physics interpolation fraction is 0 / 0 and the camera transform turns
# NaN for a frame, which the tree pause then freezes in place
const PAUSE_FLOOR := 0.02

var state := State.PLAYING
# the pause or death menu on screen, null while playing
var menu: CanvasLayer
# the time scale lerp in flight, null when settled
var transition: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(on_node_added)
	watch_existing_clouds()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PAUSE_ACTION):
		if toggle_pause():
			get_viewport().set_input_as_handled()

func is_playing() -> bool:
	return state == State.PLAYING

func is_paused() -> bool:
	return state != State.PLAYING

# the state's own wish for the tree, for whoever else pauses it (the editor)
# to restore when they are done
func wants_paused() -> bool:
	return state == State.PAUSED or state == State.MENU

# pause from PLAYING, resume from PAUSED. false when nothing changed: dead,
# in a menu, or something else (the sprite editor) holds the tree paused
func toggle_pause() -> bool:
	if transition:
		return false

	match state:
		State.PLAYING:
			if get_tree().paused:
				return false
			pause()
			return true
		State.PAUSED:
			resume()
			return true
	return false

# the slide into the pause: the pause sound, the game audio sinking and the
# time scale lerping to zero on real time, then the tree pauses and the
# menu opens
func pause() -> void:
	if state != State.PLAYING:
		return

	# a resume still climbing back is cut short, the slide starts from where
	# the time scale is
	if transition:
		transition.kill()
		transition = null

	Sound.play(PAUSE_SOUND)

	transition = create_tween()
	transition.set_ignore_time_scale(true)
	transition.set_parallel(true)
	transition.tween_property(Engine, ^"time_scale", PAUSE_FLOOR, PAUSE_FADE)
	transition.tween_property(Sound, ^"underwater", 1.0, PAUSE_FADE)
	transition.chain().tween_callback(finish_pause)

func finish_pause() -> void:
	transition = null
	Engine.time_scale = 1.0
	set_state(State.PAUSED)

# the tree runs again at once, the time scale climbs back over PAUSE_FADE
# while the audio surfaces
func resume() -> void:
	if state != State.PAUSED or transition:
		return

	set_state(State.PLAYING)
	Engine.time_scale = PAUSE_FLOOR
	Sound.underwater = 1.0
	transition = create_tween()
	transition.set_ignore_time_scale(true)
	transition.set_parallel(true)
	transition.tween_property(Engine, ^"time_scale", 1.0, PAUSE_FADE)
	transition.tween_property(Sound, ^"underwater", 0.0, PAUSE_FADE)
	transition.chain().tween_callback(finish_resume)

func finish_resume() -> void:
	transition = null
	Engine.time_scale = 1.0
	Sound.underwater = 0.0

func die() -> void:
	if state == State.PLAYING or state == State.PAUSED:
		set_state(State.DEAD)

# whatever slide is in flight stops, time runs at full speed, the audio is dry
func settle_transition() -> void:
	if transition:
		transition.kill()
		transition = null

	Engine.time_scale = 1.0
	Sound.underwater = 0.0

# the death menu's Retry: the current scene comes back fresh and the game
# runs again
func retry() -> void:
	var tree := get_tree()

	if tree.current_scene:
		tree.reload_current_scene()
	else:
		push_warning("GameState.retry: no current scene to reload")

	set_state(State.PLAYING)

func quit() -> void:
	get_tree().quit()

func set_state(to: State) -> void:
	if to == state:
		return

	var from := state
	state = to
	exit_state(from)
	enter_state(to)
	# only the pause menu and the main menu freeze the world, the death
	# menu sits over a world that keeps going
	get_tree().paused = to == State.PAUSED or to == State.MENU
	state_changed.emit(from, to)

func enter_state(to: State) -> void:
	match to:
		State.PAUSED:
			var pause_menu := PAUSE_MENU.instantiate()
			pause_menu.resume_pressed.connect(resume)
			pause_menu.quit_pressed.connect(quit)
			show_menu(pause_menu)
		State.DEAD:
			# the PlayerKillEvent of the original: the cloud alarm stops and
			# the dead song starts, the death screen sits on top
			Sound.stop(&"player_low_core")
			Sound.music(&"music_level_fail")
			var death_menu := DEATH_MENU.instantiate()
			death_menu.retry_pressed.connect(retry)
			death_menu.quit_pressed.connect(quit)
			show_menu(death_menu)

func exit_state(from: State) -> void:
	match from:
		State.DEAD:
			Sound.stop_music()
		State.PAUSED:
			settle_transition()
		State.PLAYING:
			if transition and state != State.PAUSED:
				# a death mid slide, the pause never lands
				settle_transition()

	close_menu()

func show_menu(layer: CanvasLayer) -> void:
	close_menu()
	menu = layer
	add_child(menu)

func close_menu() -> void:
	if menu == null:
		return

	menu.queue_free()
	menu = null

# the player cloud of the current scene reports through its signals, the
# hook the original PlayerEventHandler had on PlayerKillEvent. every cloud
# entering the tree is watched, and the ones already in it when this
# autoload starts (node_added only tells of later ones). clouds in scenes
# that are not the current one (test arenas) are watched too but only the
# current scene's player can end the game
func on_node_added(node: Node) -> void:
	if node is PlayerCloud:
		watch_cloud(node)

func watch_existing_clouds() -> void:
	for node in get_tree().get_nodes_in_group("player_cloud"):
		if node is PlayerCloud:
			watch_cloud(node)

func watch_cloud(cloud: PlayerCloud) -> void:
	if cloud.died.is_connected(on_cloud_died.bind(cloud)):
		return

	cloud.entered.connect(on_cloud_entered.bind(cloud))
	cloud.left.connect(on_cloud_left.bind(cloud))
	cloud.died.connect(on_cloud_died.bind(cloud))

func in_current_scene(node: Node) -> bool:
	var current := get_tree().current_scene
	return current != null and node.is_inside_tree() and (current == node or current.is_ancestor_of(node))

func on_cloud_entered(cloud: PlayerCloud) -> void:
	if in_current_scene(cloud):
		Sound.play(&"player_low_core", true)

func on_cloud_left(cloud: PlayerCloud) -> void:
	if in_current_scene(cloud):
		Sound.stop(&"player_low_core")
		Sound.play(&"pickup_health")

func on_cloud_died(cloud: PlayerCloud) -> void:
	if in_current_scene(cloud):
		die()
