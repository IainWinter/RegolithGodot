extends GutTest

# opening the sprite editor from the main scene the way f2 does: the tree
# pauses, the editor opens the png the sprite under the mouse (or the player)
# was loaded from, edits never reach the live sprite, close resumes

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

	var editor: SpriteEditor = main.editor
	assert_not_null(editor)
	assert_true(get_tree().paused)

	var player: RegolithSprite = get_tree().get_first_node_in_group("player")
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
	var editor: SpriteEditor = main.editor
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
	main.editor.close()
	await wait_process_frames(1)

	assert_null(main.editor)
	assert_false(get_tree().paused)

	var rock: RegolithSprite = main.get_node("Rock")
	var start := rock.global_position
	rock.linear_velocity = Vector2(5, 0)
	await wait_physics_frames(30)
	assert_gt(rock.global_position.x, start.x + 5.0, "physics runs again")
