extends GutTest

# SpriteEditor: opening from a RegolithSprite, tool interaction through
# canvas_input, selection and float, files, applying back to the sprite

var world: RegolithWorld
var sprite: RegolithSprite
var editor: SpriteEditor

func before_each() -> void:
	world = RegolithWorld.new()
	world.pixels_per_cell = 3
	add_child_autofree(world)

	sprite = RegolithSprite.new()
	sprite.dynamic = false
	sprite.editing = true
	add_child_autofree(sprite)

	await get_tree().process_frame

	sprite.create_blank(Vector2i(16, 12))
	sprite.fill_rect(Rect2i(2, 2, 8, 6), Color(0.5, 0.4, 0.3), RegolithSprite.CELL_FILLED, 2)
	sprite.set_cell(Vector2i(4, 4), Color(1, 0.5, 0), RegolithSprite.CELL_CORE, 5)

	editor = SpriteEditor.new()
	editor.target = sprite
	add_child_autofree(editor)
	await get_tree().process_frame

func press(x: int, y: int, right := false) -> void:
	editor.canvas_input(true, x, y, not right, right, not right, right)

func drag(x: int, y: int, right := false) -> void:
	editor.canvas_input(true, x, y, false, false, not right, right)

func release(x: int, y: int) -> void:
	editor.canvas_input(true, x, y, false, false, false, false)

func stroke(from: Vector2i, to: Vector2i, right := false) -> void:
	press(from.x, from.y, right)
	drag(to.x, to.y, right)
	release(to.x, to.y)

func test_open_reads_sprite_into_document() -> void:
	var doc := editor.doc
	assert_eq(Vector2i(doc.width, doc.height), Vector2i(16, 12))
	assert_eq(doc.get_cell_type(doc.index(4, 4)), RegolithSprite.CELL_CORE)
	assert_eq(doc.get_cell_class(doc.index(4, 4)), 5)
	assert_true(doc.get_cell_emissive(doc.index(4, 4)), "engine marks core cells emissive")
	assert_eq(doc.get_cell_class(doc.index(2, 2)), 2)
	assert_eq(doc.get_cell_type(doc.index(0, 0)), RegolithSprite.CELL_EMPTY)

func test_open_without_sprite_gives_blank_canvas() -> void:
	var blank := SpriteEditor.new()
	add_child_autofree(blank)
	await get_tree().process_frame
	assert_eq(blank.doc.width, 32)
	assert_true(blank.apply_button.disabled)

func test_pencil_stroke_interpolates_and_records_undo() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.GRAPHICS
	doc.paint_color = Color.GREEN
	editor.set_tool(SpriteEditor.Tool.PENCIL)
	stroke(Vector2i(0, 0), Vector2i(3, 0))
	assert_eq(doc.get_cell_color(doc.index(2, 0)), Color.GREEN)
	assert_true(doc.can_undo())
	editor.undo()
	assert_eq(doc.get_cell_color(doc.index(2, 0)).a, 0.0)

func test_right_button_erases_with_pencil() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.MASK
	editor.set_tool(SpriteEditor.Tool.PENCIL)
	stroke(Vector2i(3, 3), Vector2i(3, 3), true)
	assert_eq(doc.get_cell_type(doc.index(3, 3)), RegolithSprite.CELL_EMPTY)

func test_eraser_tool() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.MASK
	editor.set_tool(SpriteEditor.Tool.ERASER)
	editor.brush_size = 3
	stroke(Vector2i(5, 5), Vector2i(5, 5))
	assert_eq(doc.get_cell_type(doc.index(4, 4)), RegolithSprite.CELL_EMPTY)
	assert_eq(doc.get_cell_type(doc.index(6, 6)), RegolithSprite.CELL_EMPTY)
	assert_eq(doc.get_cell_type(doc.index(7, 7)), RegolithSprite.CELL_FILLED)

func test_fill_tool_single_undo_entry() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_WEAKPOINT1
	editor.set_tool(SpriteEditor.Tool.FILL)
	press(3, 3)
	release(3, 3)
	assert_eq(doc.get_cell_type(doc.index(9, 7)), RegolithSprite.CELL_WEAKPOINT1)
	assert_eq(doc.undo_stack.size(), 1)

func test_rect_tool_filled_and_line_tool() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.GRAPHICS
	doc.paint_color = Color.RED
	editor.rect_filled = true
	editor.set_tool(SpriteEditor.Tool.RECT)
	stroke(Vector2i(12, 8), Vector2i(14, 10))
	assert_eq(doc.get_cell_color(doc.index(13, 9)), Color.RED)
	assert_false(editor.shape_active)

	editor.set_tool(SpriteEditor.Tool.LINE)
	stroke(Vector2i(0, 11), Vector2i(5, 11))
	assert_eq(doc.get_cell_color(doc.index(3, 11)), Color.RED)

func test_picker_tool_sets_paint_color() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.GRAPHICS
	editor.set_tool(SpriteEditor.Tool.PICKER)
	press(4, 4)
	release(4, 4)
	assert_eq(doc.paint_color, doc.get_cell_color(doc.index(4, 4)))

func test_select_tool_drag_sets_selection() -> void:
	editor.set_tool(SpriteEditor.Tool.SELECT)
	stroke(Vector2i(12, 8), Vector2i(14, 10))
	assert_true(editor.doc.selection_active)
	assert_eq(editor.doc.selection, Rect2i(12, 8, 3, 3))

func test_copy_paste_creates_float_then_commit_writes() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.MASK
	doc.set_selection(2, 2, 4, 4)
	editor.copy_selection()
	assert_eq(SpriteEditor.clipboard["w"], 3)

	doc.deselect()
	editor.paste_clipboard()
	assert_true(editor.has_float())
	assert_eq(editor.tool, SpriteEditor.Tool.MOVE)

	editor.float_pos = Vector2i(12, 8)
	editor.commit_float()
	assert_false(editor.has_float())
	assert_eq(doc.get_cell_type(doc.index(13, 9)), RegolithSprite.CELL_FILLED)
	assert_eq(doc.selection, Rect2i(12, 8, 3, 3), "selection follows the committed float")

	editor.undo()
	assert_eq(doc.get_cell_type(doc.index(13, 9)), RegolithSprite.CELL_EMPTY)

func test_click_outside_float_commits_it() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.MASK
	doc.set_selection(2, 2, 3, 3)
	editor.duplicate_selection()
	editor.float_pos = Vector2i(12, 8)
	press(0, 0)
	assert_false(editor.has_float())
	assert_eq(doc.get_cell_type(doc.index(12, 8)), RegolithSprite.CELL_FILLED)

func test_move_tool_lifts_drags_and_drops() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.MASK
	doc.set_selection(2, 2, 3, 3)
	editor.set_tool(SpriteEditor.Tool.MOVE)
	press(2, 2)
	assert_true(editor.has_float())
	assert_true(editor.float_lifted)
	assert_eq(doc.get_cell_type(doc.index(2, 2)), RegolithSprite.CELL_EMPTY, "lifted cells cleared")
	drag(12, 8)
	release(12, 8)
	editor.commit_float()
	assert_eq(doc.get_cell_type(doc.index(12, 8)), RegolithSprite.CELL_FILLED)
	assert_eq(doc.get_cell_type(doc.index(13, 9)), RegolithSprite.CELL_FILLED)

func test_cancel_lifted_float_restores_source() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.MASK
	doc.set_selection(2, 2, 3, 3)
	editor.set_tool(SpriteEditor.Tool.MOVE)
	press(2, 2)
	drag(12, 8)
	release(12, 8)
	editor.cancel_float()
	assert_false(editor.has_float())
	assert_eq(doc.get_cell_type(doc.index(2, 2)), RegolithSprite.CELL_FILLED)
	assert_eq(doc.get_cell_type(doc.index(12, 8)), RegolithSprite.CELL_EMPTY)

func test_nudge_moves_selection_and_float() -> void:
	var doc := editor.doc
	doc.set_selection(2, 2, 3, 3)
	editor.nudge(1, 0)
	assert_eq(doc.selection.position, Vector2i(3, 2))
	editor.duplicate_selection()
	editor.nudge(0, 2)
	assert_eq(editor.float_pos, Vector2i(3, 4))

func test_changing_tool_commits_float() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.MASK
	doc.set_selection(2, 2, 3, 3)
	editor.duplicate_selection()
	editor.float_pos = Vector2i(12, 8)
	editor.set_tool(SpriteEditor.Tool.PENCIL)
	assert_false(editor.has_float())
	assert_eq(doc.get_cell_type(doc.index(12, 8)), RegolithSprite.CELL_FILLED)

func test_set_mode_shows_matching_sidebar_section() -> void:
	editor.set_mode(SpriteDocument.Mode.CLASS)
	assert_eq(editor.doc.mode, SpriteDocument.Mode.CLASS)
	for i in editor.mode_sections.size():
		assert_eq(editor.mode_sections[i].visible, i == SpriteDocument.Mode.CLASS, "section %d" % i)

func test_clear_selected_region_with_all_layers() -> void:
	var doc := editor.doc
	doc.paste_all_layers = true
	doc.set_selection(2, 2, 3, 3)
	editor.clear_selected_region()
	assert_eq(doc.get_cell_type(doc.index(2, 2)), RegolithSprite.CELL_EMPTY)
	assert_eq(doc.get_cell_color(doc.index(2, 2)).a, 0.0)
	assert_true(doc.can_undo())

func test_apply_writes_document_into_sprite() -> void:
	var doc := editor.doc
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_WEAKPOINT2
	doc.begin_edit()
	doc.paint_at(9, 7, false)
	doc.set_cell_class(doc.index(9, 7), 7)
	doc.end_edit()

	doc.mode = SpriteDocument.Mode.GRAPHICS
	doc.paint_color = Color.RED
	doc.paint_at(13, 9, false)

	editor.apply_to_target()
	assert_eq(sprite.get_cell_type(Vector2i(9, 7)), RegolithSprite.CELL_WEAKPOINT2)
	assert_eq(sprite.get_cell_class(Vector2i(9, 7)), 7)
	assert_eq(sprite.get_cell_color(Vector2i(2, 2)), doc.get_cell_color(doc.index(2, 2)))
	assert_false(sprite.has_cell(Vector2i(13, 9)), "color without mask is not a cell")

	var filled := 0
	for i in doc.cell_count():
		if doc.get_cell_type(i) != RegolithSprite.CELL_EMPTY:
			filled += 1
	assert_eq(sprite.get_active_cell_count(), filled)

func test_save_and_load_png_pair() -> void:
	var path := ProjectSettings.globalize_path("res://test/unit/tmp_roundtrip.png")
	var before := editor.doc.snapshot()

	assert_true(editor.save_to(path))
	assert_true(FileAccess.file_exists(SpriteEditor.mask_path(path)))

	editor.doc.clear()
	assert_true(editor.load_from(path))
	assert_true(SpriteDocument.snapshots_equal(before, editor.doc.snapshot()))
	assert_eq(editor.filename, "tmp_roundtrip")

	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(SpriteEditor.mask_path(path))

func test_save_without_mask_removes_stale_mask_file() -> void:
	var path := ProjectSettings.globalize_path("res://test/unit/tmp_nomask.png")
	assert_true(editor.save_to(path))
	assert_true(FileAccess.file_exists(SpriteEditor.mask_path(path)))

	editor.doc.clear()
	assert_true(editor.save_to(path))
	assert_false(FileAccess.file_exists(SpriteEditor.mask_path(path)))

	DirAccess.remove_absolute(path)

func test_close_emits_closed() -> void:
	watch_signals(editor)
	editor.close()
	assert_signal_emitted(editor, "closed")

func test_status_text_reports_hover_cell() -> void:
	editor.set_mode(SpriteDocument.Mode.CLASS)
	editor.set_hover(4, 4)
	assert_string_contains(editor.status_text(), "4, 4")
	assert_string_contains(editor.status_text(), "class 5")
	editor.set_hover(99, 99)
	assert_eq(editor.hover, Vector2i(-1, -1))
