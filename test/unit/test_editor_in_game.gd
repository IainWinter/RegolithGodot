extends GutTest

# opening the sprite editor from the main scene the way f2 does: the tree
# pauses, the editor targets a live sprite, apply writes back, close resumes

var main: Node2D

func before_each() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(main)
	await wait_physics_frames(3)

func after_each() -> void:
	get_tree().paused = false

func test_open_editor_pauses_and_targets_sprite() -> void:
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
	assert_not_null(editor.target)
	assert_true(editor.target.is_loaded())
	assert_eq(Vector2i(editor.doc.width, editor.doc.height), editor.target.get_color_image().get_size())
	assert_gt(editor.doc.mask.count(RegolithSprite.CELL_CORE), 0, "target sprite has core cells")

func test_open_twice_keeps_one_editor() -> void:
	main.open_editor()
	var first = main.editor
	main.open_editor()
	assert_eq(main.editor, first)

func test_apply_changes_live_sprite() -> void:
	main.open_editor()
	await wait_process_frames(1)
	var editor: SpriteEditor = main.editor
	var before := editor.target.get_active_cell_count()

	editor.doc.mode = SpriteDocument.Mode.MASK
	editor.doc.begin_edit()
	editor.doc.paint_rect(0, 0, 3, 3, 1, true, true)
	editor.doc.end_edit()
	editor.apply_to_target()

	assert_lt(editor.target.get_active_cell_count(), before)

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
