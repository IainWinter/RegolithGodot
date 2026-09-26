extends GutTest

# opening the sprite editor from the main scene the way f2 does: the tree
# pauses, the editor window opens the png the sprite under the mouse (or the
# player) was loaded from in the shared SpriteEditor Control, edits never reach
# the live sprite, close resumes

var main: Node2D

func before_each() -> void:
	main = load("res://game/scenes/Main.tscn").instantiate()
	add_child_autofree(main)
	await wait_physics_frames(3)

func after_each() -> void:
	get_tree().paused = false

func test_open_editor_pauses_and_opens_player_source() -> void:
	main.open_editor()
	await wait_process_frames(1)

	var rock: RegolithSprite = main.get_node("Rock")
	var start := rock.global_position
	rock.linear_velocity = Vector2(5, 0)
	await wait_physics_frames(10)
	assert_eq(rock.global_position, start, "world is frozen while editing")

	var window: SpriteEditorWindow = main.editor
	assert_not_null(window)
	assert_true(get_tree().paused)

	var editor: SpriteEditor = window.editor
	assert_not_null(editor, "the window hosts the shared SpriteEditor Control")
	var player: RegolithSprite = get_tree().get_first_node_in_group("player")
	assert_eq(window.path, ProjectSettings.globalize_path(player.texture.resource_path))
	assert_eq(editor.path, ProjectSettings.globalize_path(player.texture.resource_path))
	assert_eq(editor.filename, "player")
	assert_eq(Vector2i(editor.doc.width, editor.doc.height), Vector2i(player.texture.get_size()))
	assert_gt(editor.doc.mask.count(RegolithSprite.CELL_CORE), 0, "player mask has core cells")

func test_source_path_comes_from_texture() -> void:
	var rock: RegolithSprite = main.get_node("Rock")
	assert_eq(main.sprite_source_path(rock), ProjectSettings.globalize_path(rock.texture.resource_path))
	assert_eq(main.sprite_source_path(null), "")

	var blank := RegolithSprite.new()
	assert_eq(main.sprite_source_path(blank), "", "no texture, nothing to open")
	blank.free()

func test_open_twice_keeps_one_editor() -> void:
	main.open_editor()
	var first = main.editor
	main.open_editor()
	assert_eq(main.editor, first)

func test_editing_document_leaves_live_sprite_alone() -> void:
	main.open_editor()
	await wait_process_frames(1)
	var editor: SpriteEditor = main.editor.editor
	var player: RegolithSprite = get_tree().get_first_node_in_group("player")
	var before := player.get_active_cell_count()

	editor.doc.mode = SpriteDocument.Mode.MASK
	editor.doc.begin_edit()
	editor.doc.paint_rect(0, 0, 3, 3, 1, true, true)
	editor.doc.end_edit()
	await wait_process_frames(2)

	assert_eq(player.get_active_cell_count(), before, "the editor edits a document, not the sprite")

func test_close_resumes_world() -> void:
	main.open_editor()
	await wait_process_frames(1)
	main.editor.editor.close()
	await wait_process_frames(1)

	assert_null(main.editor)
	assert_false(get_tree().paused)

	var rock: RegolithSprite = main.get_node("Rock")
	var start := rock.global_position
	rock.linear_velocity = Vector2(5, 0)
	await wait_physics_frames(30)
	assert_gt(rock.global_position.x, start.x + 5.0, "physics runs again")

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func test_f2_toggles_the_editor_through_the_action() -> void:
	var f2 := key(KEY_F2)
	assert_true(f2.is_action_pressed(Controls.EDITOR_TOGGLE), "F2 is the editor toggle action")
	var hotkeys := main.get_node("Hotkeys")

	hotkeys._unhandled_input(f2)
	await wait_process_frames(1)
	assert_not_null(main.editor, "F2 opens the sprite editor")
	assert_true(get_tree().paused)

	hotkeys._unhandled_input(f2)
	await wait_process_frames(2)
	assert_null(main.editor, "F2 again closes it")

func test_f3_toggles_the_debug_panel_through_the_action() -> void:
	var f3 := key(KEY_F3)
	assert_true(f3.is_action_pressed(Controls.DEBUG_PANEL), "F3 is the debug panel action")
	var hotkeys := main.get_node("Hotkeys")

	hotkeys._unhandled_input(f3)
	await wait_process_frames(1)
	assert_not_null(main.debug_panel, "F3 opens the debug panel")
	var fold: FoldableContainer = main.debug_panel.controls_fold
	assert_not_null(fold, "the panel carries the controls list")
	assert_true(fold.folded, "folded until asked for")
	assert_true(main.debug_panel.controls_list.rows.has(Controls.EDITOR_TOGGLE))

	hotkeys._unhandled_input(f3)
	await wait_process_frames(1)
	assert_null(main.debug_panel, "F3 again closes it")
