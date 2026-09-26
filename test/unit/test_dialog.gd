extends GutTest

# the Dialog autoload and its window: lines queue in order and show one at
# a time with the speaker's icon and name, the typewriter reveals them at
# the character's text_speed and freezes with the tree, repeats coalesce,
# interrupt drops a speaker, the window slides out once the queue empties,
# and every Character .tres has a face on disk and its own id. the time
# driven steps run through Dialog.advance so the asserts need no frames

const FIGHTER := &"fighter"
const BOMB := &"bomb"
const EXPECTED_IDS := [&"fighter", &"bomb", &"base", &"station", &"boss_compass", &"boss_stingray", &"player", &"turret"]

var started: Array = []
var finished: Array = []
var empties := 0

func before_each() -> void:
	reset_dialog()
	started = []
	finished = []
	empties = 0
	Dialog.line_started.connect(on_started)
	Dialog.line_finished.connect(on_finished)
	Dialog.queue_empty.connect(on_empty)

func after_each() -> void:
	Dialog.line_started.disconnect(on_started)
	Dialog.line_finished.disconnect(on_finished)
	Dialog.queue_empty.disconnect(on_empty)
	get_tree().paused = false
	reset_dialog()

# nothing waiting, nothing on screen, the slide out landed, repeats allowed
func reset_dialog() -> void:
	Dialog.clear()
	Dialog.advance(Dialog.FADE * 2.0)
	Dialog.forget()

func on_started(character: Character, text: String) -> void:
	started.append([character.id, text])

func on_finished(character: Character, text: String) -> void:
	finished.append([character.id, text])

func on_empty() -> void:
	empties += 1

# runs the dialog in small steps until it goes idle
func run_out(max_seconds := 60.0) -> void:
	var elapsed := 0.0
	while Dialog.phase != Dialog.Phase.IDLE and elapsed < max_seconds:
		Dialog.advance(0.05)
		elapsed += 0.05

func window() -> DialogWindow:
	return Dialog.window

func fixed_speed_character(speed: float) -> Character:
	var character := Character.new()
	character.id = &"tester"
	character.display_name = "Tester"
	character.text_speed = speed
	return character

# characters

func test_every_character_tres_has_an_icon_file_and_a_unique_id() -> void:
	var ids: Array = []
	var count := 0

	for file in DirAccess.get_files_at(CharacterRegistry.DIR):
		if file.get_extension() != "tres":
			continue

		count += 1
		var character := load("%s/%s" % [CharacterRegistry.DIR, file]) as Character
		assert_not_null(character, "%s is a Character" % file)
		if character == null:
			continue

		assert_ne(character.id, &"", "%s has an id" % file)
		assert_false(ids.has(character.id), "%s: id %s is unique" % [file, character.id])
		ids.append(character.id)
		assert_eq(String(character.id), file.get_basename(), "%s is named after its id" % file)
		assert_ne(character.display_name, "", "%s has a display name" % file)
		assert_not_null(character.icon, "%s has an icon" % file)
		if character.icon != null:
			var path := character.icon.resource_path
			assert_true(path.begins_with("res://game/images/characters/"), "%s icon under game/images/characters: %s" % [file, path])
			assert_true(FileAccess.file_exists(path), "%s icon file exists: %s" % [file, path])
			assert_eq(character.icon.get_size(), Vector2(32, 32), "%s icon is 32x32" % file)
		assert_gt(character.text_speed, 0.0)

	assert_eq(count, EXPECTED_IDS.size(), "one .tres per ship")

	for id in EXPECTED_IDS:
		assert_true(CharacterRegistry.has(id), "registry knows %s" % id)
		assert_eq(CharacterRegistry.find(id).id, id)

	assert_eq(CharacterRegistry.all().size(), EXPECTED_IDS.size())
	assert_null(CharacterRegistry.find(&"nobody"))
	assert_eq(CharacterRegistry.find_or_placeholder(&"nobody").display_name, "Nobody", "an unknown id still gets a name")

func test_class_names_map_to_ids() -> void:
	assert_eq(CharacterRegistry.id_for_class_name("EnemyBossCompass"), &"boss_compass")
	assert_eq(CharacterRegistry.id_for_class_name("EnemyFighter"), &"fighter")
	assert_eq(CharacterRegistry.id_for_class_name("Player"), &"player")
	assert_eq(CharacterRegistry.id_for_class_name(""), &"")

func test_say_from_resolves_the_speaker_from_the_node() -> void:
	# a character_id meta
	var tagged := Node.new()
	tagged.set_meta(&"character_id", &"station")
	assert_eq(CharacterRegistry.id_for_node(tagged), &"station")
	tagged.free()

	# the lua class name of a scripted enemy
	var lua_script := GDScript.new()
	lua_script.source_code = "extends Node\nvar ai_class := \"bomb\"\n"
	lua_script.reload()
	var scripted := Node.new()
	scripted.set_script(lua_script)
	assert_eq(CharacterRegistry.id_for_node(scripted), BOMB)
	assert_true(Dialog.say_from(scripted, "Incoming!"))
	assert_eq(Dialog.current_character().id, BOMB)
	scripted.free()

	# a character property
	var owner_script := GDScript.new()
	owner_script.source_code = "extends Node\nvar character: Character\n"
	owner_script.reload()
	var owner := Node.new()
	owner.set_script(owner_script)
	owner.character = CharacterRegistry.find(FIGHTER)
	assert_eq(CharacterRegistry.id_for_node(owner), FIGHTER)
	owner.free()

	# the gdscript class of an enemy, EnemyBossCompass -> boss_compass
	var boss := EnemyBossCompass.new()
	assert_eq(CharacterRegistry.id_for_node(boss), &"boss_compass")
	boss.free()

	# nothing known: the node's name stands in
	var stray := Node.new()
	stray.name = "Rock"
	assert_true(Dialog.say_from(stray, "..."))
	assert_eq(Dialog.queued_texts(), ["..."])
	stray.free()

# the queue

func test_three_lines_from_two_characters_play_in_order() -> void:
	assert_true(Dialog.say(FIGHTER, "Target sighted."))
	assert_true(Dialog.say(BOMB, "Going in!"))
	assert_true(Dialog.say(FIGHTER, "Cover me."))

	assert_eq(started, [[FIGHTER, "Target sighted."]], "the first line starts at once")
	assert_eq(Dialog.queued_texts(), ["Going in!", "Cover me."])
	assert_eq(Dialog.phase, Dialog.Phase.OPENING)

	Dialog.advance(Dialog.FADE)
	assert_eq(Dialog.phase, Dialog.Phase.TYPING)
	assert_true(window().visible, "window on screen after the slide in")
	assert_eq(window().shown, 1.0)

	var fighter := CharacterRegistry.find(FIGHTER)
	assert_eq(window().name_label.text, fighter.display_name, "speaker name shown")
	assert_eq(window().name_label.get_theme_color("font_color"), fighter.color, "in the character color")
	assert_eq(window().icon.texture, fighter.icon, "the character icon shown")
	assert_eq(window().text_label.text, "Target sighted.")

	run_out()

	assert_eq(started, [[FIGHTER, "Target sighted."], [BOMB, "Going in!"], [FIGHTER, "Cover me."]], "lines in order")
	assert_eq(finished, started, "each finished in turn")
	assert_eq(empties, 1, "queue_empty once")
	assert_false(Dialog.is_showing())
	assert_false(window().visible, "window hidden when the queue empties")
	assert_eq(window().shown, 0.0)
	assert_eq(Dialog.queued_texts(), [])

func test_the_bomb_line_shows_its_own_face() -> void:
	Dialog.say(BOMB, "Boom.")
	Dialog.advance(Dialog.FADE)
	var bomb := CharacterRegistry.find(BOMB)
	assert_eq(window().icon.texture, bomb.icon)
	assert_eq(window().name_label.text, bomb.display_name)
	assert_eq(window().name_label.get_theme_color("font_color"), bomb.color)

func test_typewriter_reveals_at_text_speed_then_holds() -> void:
	var text := "0123456789012345678901234567890123456789"
	assert_eq(text.length(), 40)
	Dialog.say_as(fixed_speed_character(40.0), text, 1.0)
	Dialog.advance(Dialog.FADE)
	assert_eq(window().revealed(), 0, "nothing revealed before the typewriter runs")
	assert_eq(window().text_label.visible_characters, 0)

	Dialog.advance(0.5)
	assert_eq(window().text_label.visible_characters, 20, "40 chars per second, half a second in")
	assert_eq(Dialog.phase, Dialog.Phase.TYPING)

	Dialog.advance(0.25)
	assert_eq(window().text_label.visible_characters, 30)

	Dialog.advance(0.25)
	assert_eq(window().text_label.visible_characters, 40, "fully revealed")
	assert_true(window().is_fully_revealed())
	assert_eq(Dialog.phase, Dialog.Phase.HOLDING)
	assert_eq(finished, [], "held after the reveal")

	Dialog.advance(0.5)
	assert_eq(finished, [], "still holding half way through the second")
	Dialog.advance(0.6)
	assert_eq(finished.size(), 1, "the hold ran out")
	assert_eq(Dialog.phase, Dialog.Phase.CLOSING)
	assert_true(window().visible, "still fading out")
	Dialog.advance(Dialog.FADE)
	assert_eq(Dialog.phase, Dialog.Phase.IDLE)
	assert_false(window().visible)

func test_default_hold_grows_with_the_line() -> void:
	assert_eq(Dialog.hold_for("hi", -1.0), Dialog.HOLD_BASE + Dialog.HOLD_PER_CHAR * 2)
	assert_eq(Dialog.hold_for("hi", 3.0), 3.0, "an explicit duration wins")
	assert_eq(Dialog.hold_for("hi", 0.0), 0.0)

func test_typewriter_runs_on_frames_and_freezes_while_paused() -> void:
	Dialog.say_as(fixed_speed_character(40.0), "A line that takes a good while to type out on its own.", 5.0)
	Dialog.advance(Dialog.FADE)
	await wait_process_frames(6)
	var before := window().revealed()
	assert_gt(before, 0, "the typewriter moves on its own")
	assert_lt(before, Dialog.current_text().length(), "and is not done yet")

	get_tree().paused = true
	await wait_process_frames(6)
	assert_eq(window().revealed(), before, "frozen under the pause, the dialog is a game effect")
	assert_true(Dialog.can_process(), "the autoload itself keeps running so lines can still be queued")
	assert_true(Dialog.say(BOMB, "queued while paused"))

	get_tree().paused = false
	await wait_process_frames(6)
	assert_gt(window().revealed(), before, "moves again after the pause")

func test_same_speaker_same_line_coalesces() -> void:
	assert_true(Dialog.say(FIGHTER, "Contact!"))
	assert_false(Dialog.say(FIGHTER, "Contact!"), "the copy on screen drops the repeat")
	assert_true(Dialog.say(BOMB, "Contact!"), "another speaker may say the same words")
	assert_false(Dialog.say(BOMB, "Contact!"), "a copy waiting in the queue drops the repeat")
	assert_eq(Dialog.queued_texts(), ["Contact!"])

	run_out()
	assert_false(Dialog.say(FIGHTER, "Contact!"), "said too recently")
	Dialog.advance(Dialog.COALESCE)
	assert_true(Dialog.say(FIGHTER, "Contact!"), "old enough to say again")

func test_empty_lines_are_dropped() -> void:
	assert_false(Dialog.say(FIGHTER, "   "))
	assert_false(Dialog.is_showing())

func test_priority_goes_ahead_of_waiting_lines_not_the_current_one() -> void:
	Dialog.say(FIGHTER, "first")
	Dialog.say(BOMB, "second")
	Dialog.say(FIGHTER, "third")
	Dialog.say(BOMB, "urgent", -1.0, 5)
	Dialog.say(FIGHTER, "also urgent", -1.0, 5)
	assert_eq(Dialog.current_text(), "first", "the line on screen keeps the window")
	assert_eq(Dialog.queued_texts(), ["urgent", "also urgent", "second", "third"], "priority first, then arrival order")

func test_interrupt_drops_a_speaker() -> void:
	Dialog.say(FIGHTER, "one")
	Dialog.say(FIGHTER, "two")
	Dialog.say(BOMB, "three")
	Dialog.say(FIGHTER, "four")

	Dialog.interrupt(FIGHTER)

	assert_eq(finished, [[FIGHTER, "one"]], "the fighter's line on screen was cut short")
	assert_eq(Dialog.current_text(), "three", "the bomb's line took the window")
	assert_eq(Dialog.queued_texts(), [], "the fighter's waiting lines are gone")

	Dialog.interrupt(BOMB)
	assert_eq(Dialog.phase, Dialog.Phase.CLOSING, "nothing left, the window slides out")

func test_clear_drops_everything() -> void:
	Dialog.say(FIGHTER, "one")
	Dialog.say(BOMB, "two")
	Dialog.clear()
	assert_false(Dialog.is_showing())
	assert_eq(Dialog.queued_texts(), [])
	assert_eq(finished, [[FIGHTER, "one"]])
	Dialog.advance(Dialog.FADE)
	assert_eq(empties, 1)
	assert_false(window().visible)

func test_a_line_said_while_closing_reopens_the_window() -> void:
	Dialog.say(FIGHTER, "one")
	Dialog.advance(Dialog.FADE)
	Dialog.clear()
	Dialog.advance(Dialog.FADE * 0.5)
	assert_eq(Dialog.phase, Dialog.Phase.CLOSING)
	Dialog.say(BOMB, "two")
	assert_eq(Dialog.phase, Dialog.Phase.OPENING, "slides back in from where it was")
	assert_eq(Dialog.current_text(), "two")

func test_talk_blip_plays_the_voice_on_the_menu_bus() -> void:
	var fighter := CharacterRegistry.find(FIGHTER)
	assert_ne(fighter.voice, &"", "the placeholder characters have a voice")
	assert_true(Sound.has(fighter.voice), "which is a Sound name")

	Dialog.say(FIGHTER, "Hello there, pilot.")
	Dialog.advance(Dialog.FADE)
	Sound.last_played = &""
	# two characters land in this step at the fighter's 44 per second
	Dialog.advance(0.05)
	assert_eq(Sound.last_played, fighter.voice, "a blip on the first letters")
	assert_eq(Dialog.blips, 1)
	assert_not_null(Dialog.last_blip)
	assert_eq(Dialog.last_blip.bus, Sound.MENU_BUS, "the blip stays clear of the world bus low pass")
	assert_eq(Dialog.last_blip.volume_db, Dialog.BLIP_VOLUME_DB, "soft")

	for i in 6:
		Dialog.advance(0.02)
	assert_gte(window().revealed(), 5, "several characters revealed since")
	assert_lte(Dialog.blips, 3, "one blip per BLIP_INTERVAL, not one per character")
	assert_gte(Dialog.blips, 2, "but it keeps ticking")

	var silent := fixed_speed_character(40.0)
	Dialog.clear()
	Dialog.advance(Dialog.FADE)
	Dialog.forget()
	Dialog.say_as(silent, "Quiet words.")
	Dialog.advance(Dialog.FADE)
	Sound.last_played = &""
	Dialog.advance(0.5)
	assert_eq(Sound.last_played, &"", "no voice, no blip")

# the window

func test_window_layout_and_layers() -> void:
	var w := window()
	assert_true(w is DialogWindow)
	assert_eq(w.layer, DialogWindow.LAYER)
	assert_eq(w.layer, 15)
	var pause_menu: CanvasLayer = load("res://game/scenes/ui/PauseMenu.tscn").instantiate()
	assert_lt(w.layer, pause_menu.layer, "under the pause menu")
	pause_menu.free()
	assert_eq(Dialog.process_mode, Node.PROCESS_MODE_ALWAYS)

	assert_eq(w.root.theme, PixelTheme.theme(), "the game's pixel theme")
	assert_eq(w.frame.anchor_left, 0.5)
	assert_eq(w.frame.anchor_right, 0.5)
	assert_eq(w.frame.anchor_top, 1.0)
	assert_eq(w.frame.anchor_bottom, 1.0, "anchored bottom center")
	assert_eq(w.frame.grow_vertical, Control.GROW_DIRECTION_BEGIN, "grows upward")
	assert_true(w.text_label.autowrap_mode != TextServer.AUTOWRAP_OFF, "long lines wrap")

	for control in [w.root, w.frame, w.icon_frame, w.icon, w.name_label, w.text_label]:
		assert_eq(control.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s never steals input" % control.name)

	assert_eq(w.icon.custom_minimum_size, Vector2(32, 32), "a 32 pixel face")
	assert_eq(w.icon.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)

	# hidden: fully faded and slid down SLIDE pixels below its resting spot
	assert_eq(w.shown, 0.0)
	assert_false(w.visible)
	assert_eq(w.frame.offset_bottom, -float(DialogWindow.MARGIN) + DialogWindow.SLIDE)
	assert_eq(w.frame.modulate.a, 0.0)

	# shown: resting MARGIN pixels above the bottom edge, opaque
	w.shown = 1.0
	assert_true(w.visible)
	assert_eq(w.frame.offset_bottom, -float(DialogWindow.MARGIN))
	assert_eq(w.frame.modulate.a, 1.0)
	w.shown = 0.0

func test_window_fits_a_narrow_viewport() -> void:
	var w := window()
	var viewport_width := w.root.size.x
	assert_gt(viewport_width, 0.0)
	var expected := minf(DialogWindow.WIDTH, viewport_width - DialogWindow.MARGIN * 2)
	assert_eq(w.frame.custom_minimum_size.x, expected, "as wide as WIDTH or the viewport minus the margins")
	assert_eq(w.frame.offset_left, -expected / 2.0)
	assert_eq(w.frame.offset_right, expected / 2.0)
	assert_true(expected <= viewport_width - DialogWindow.MARGIN * 2, "fits at 1152x648 and in the editor's taller window")
