extends GutTest

# SpriteDocument: buffers, paint ops, fill, regions, history, png codec

var doc: SpriteDocument

func before_each() -> void:
	doc = SpriteDocument.new(16, 12)

func fill_block(rect: Rect2i, type: int, cell_class: int, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := doc.index(x, y)
			doc.set_cell_color(i, color)
			doc.set_cell_type(i, type)
			doc.set_cell_class(i, cell_class)

func test_new_document_is_empty() -> void:
	assert_eq(doc.width, 16)
	assert_eq(doc.height, 12)
	assert_eq(doc.cell_count(), 192)
	assert_false(doc.has_mask())
	assert_eq(doc.get_cell_type(doc.index(3, 3)), RegolithSprite.CELL_EMPTY)

func test_cell_accessors_round_trip() -> void:
	var i := doc.index(4, 5)
	doc.set_cell_color(i, Color(1, 0.5, 0, 1))
	doc.set_cell_type(i, RegolithSprite.CELL_CORE)
	doc.set_cell_class(i, 5)
	doc.set_cell_emissive(i, true)
	assert_eq(doc.get_cell_color(i), Color8(255, 128, 0, 255))
	assert_eq(doc.get_cell_type(i), RegolithSprite.CELL_CORE)
	assert_eq(doc.get_cell_class(i), 5)
	assert_true(doc.get_cell_emissive(i))

func test_clearing_type_clears_class_bits() -> void:
	var i := doc.index(1, 1)
	doc.set_cell_type(i, RegolithSprite.CELL_FILLED)
	doc.set_cell_class(i, 3)
	doc.set_cell_emissive(i, true)
	doc.set_cell_type(i, RegolithSprite.CELL_EMPTY)
	assert_eq(doc.get_cell_class(i), 0)
	assert_false(doc.get_cell_emissive(i))

func test_pencil_paints_selected_cells_only() -> void:
	doc.mode = SpriteDocument.Mode.GRAPHICS
	doc.paint_color = Color(0, 1, 0, 1)
	doc.set_selection(0, 0, 3, 3)
	doc.paint_at(2, 2, false)
	doc.paint_at(6, 6, false)
	assert_eq(doc.get_cell_color(doc.index(2, 2)), Color(0, 1, 0, 1))
	assert_eq(doc.get_cell_color(doc.index(6, 6)).a, 0.0, "outside selection untouched")

func test_brush_size_covers_square() -> void:
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_FILLED
	doc.paint_brush(5, 5, 3, false)
	var count := 0
	for i in doc.cell_count():
		if doc.get_cell_type(i) != RegolithSprite.CELL_EMPTY:
			count += 1
	assert_eq(count, 9)
	assert_eq(doc.get_cell_type(doc.index(4, 4)), RegolithSprite.CELL_FILLED)
	assert_eq(doc.get_cell_type(doc.index(6, 6)), RegolithSprite.CELL_FILLED)

func test_line_is_continuous() -> void:
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_FILLED
	doc.paint_line(0, 0, 10, 4, 1, false)
	for x in 11:
		var hit := false
		for y in 12:
			if doc.get_cell_type(doc.index(x, y)) != RegolithSprite.CELL_EMPTY:
				hit = true
		assert_true(hit, "column %d painted" % x)

func test_rect_outline_and_filled() -> void:
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_FILLED
	doc.paint_rect(2, 2, 6, 6, 1, false, false)
	assert_eq(doc.get_cell_type(doc.index(2, 4)), RegolithSprite.CELL_FILLED, "edge")
	assert_eq(doc.get_cell_type(doc.index(4, 4)), RegolithSprite.CELL_EMPTY, "hollow middle")
	doc.paint_rect(2, 2, 6, 6, 1, true, false)
	assert_eq(doc.get_cell_type(doc.index(4, 4)), RegolithSprite.CELL_FILLED, "filled middle")

func test_flood_fill_mask_stops_at_other_types() -> void:
	fill_block(Rect2i(2, 2, 8, 6), RegolithSprite.CELL_FILLED, 0, Color.WHITE)
	doc.set_cell_type(doc.index(4, 4), RegolithSprite.CELL_CORE)
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_WEAKPOINT1
	doc.flood_fill_at(3, 3, false)
	assert_eq(doc.get_cell_type(doc.index(9, 7)), RegolithSprite.CELL_WEAKPOINT1)
	assert_eq(doc.get_cell_type(doc.index(4, 4)), RegolithSprite.CELL_CORE)
	assert_eq(doc.get_cell_type(doc.index(12, 10)), RegolithSprite.CELL_EMPTY)

func test_flood_fill_class_skips_empty_cells() -> void:
	fill_block(Rect2i(2, 2, 8, 6), RegolithSprite.CELL_FILLED, 0, Color.WHITE)
	doc.mode = SpriteDocument.Mode.CLASS
	doc.paint_class = 7
	doc.flood_fill_at(3, 3, false)
	assert_eq(doc.get_cell_class(doc.index(9, 7)), 7)
	assert_eq(doc.get_cell_class(doc.index(0, 0)), 0)

func test_flood_fill_graphics_matches_color() -> void:
	fill_block(Rect2i(0, 0, 4, 4), RegolithSprite.CELL_FILLED, 0, Color.RED)
	fill_block(Rect2i(4, 0, 4, 4), RegolithSprite.CELL_FILLED, 0, Color.BLUE)
	doc.mode = SpriteDocument.Mode.GRAPHICS
	doc.paint_color = Color.GREEN
	doc.flood_fill_at(1, 1, false)
	assert_eq(doc.get_cell_color(doc.index(3, 3)), Color.GREEN)
	assert_eq(doc.get_cell_color(doc.index(4, 3)), Color.BLUE)

func test_emission_paint_keeps_class() -> void:
	fill_block(Rect2i(0, 0, 2, 2), RegolithSprite.CELL_FILLED, 6, Color.WHITE)
	doc.mode = SpriteDocument.Mode.EMISSION
	doc.paint_at(1, 1, false)
	assert_true(doc.get_cell_emissive(doc.index(1, 1)))
	assert_eq(doc.get_cell_class(doc.index(1, 1)), 6)
	doc.paint_at(1, 1, true)
	assert_false(doc.get_cell_emissive(doc.index(1, 1)))
	assert_eq(doc.get_cell_class(doc.index(1, 1)), 6)

func test_pick_reads_current_layer() -> void:
	fill_block(Rect2i(0, 0, 1, 1), RegolithSprite.CELL_JOINT2, 4, Color.YELLOW)
	doc.mode = SpriteDocument.Mode.GRAPHICS
	doc.pick_at(0, 0)
	assert_eq(doc.paint_color, Color.YELLOW)
	doc.mode = SpriteDocument.Mode.MASK
	doc.pick_at(0, 0)
	assert_eq(doc.paint_type, RegolithSprite.CELL_JOINT2)
	doc.mode = SpriteDocument.Mode.CLASS
	doc.pick_at(0, 0)
	assert_eq(doc.paint_class, 4)

func test_selection_is_clamped_to_canvas() -> void:
	doc.set_selection(-5, -5, 40, 40)
	assert_true(doc.selection_active)
	assert_eq(doc.selection, Rect2i(0, 0, 16, 12))
	doc.set_selection(20, 20, 30, 30)
	assert_false(doc.selection_active, "fully outside deactivates")

func test_copy_region_and_write_back() -> void:
	fill_block(Rect2i(1, 1, 3, 2), RegolithSprite.CELL_CORE, 2, Color.RED)
	var region := doc.copy_region(Rect2i(1, 1, 3, 2))
	assert_eq(region["w"], 3)
	assert_eq(region["h"], 2)
	assert_eq(region["mask"].size(), 6)
	doc.paste_all_layers = true
	doc.write_region(region, 10, 8)
	assert_eq(doc.get_cell_type(doc.index(12, 9)), RegolithSprite.CELL_CORE)
	assert_eq(doc.get_cell_class(doc.index(12, 9)), 2)
	assert_eq(doc.get_cell_color(doc.index(12, 9)), Color.RED)

func test_clear_region_respects_layer_mode() -> void:
	fill_block(Rect2i(0, 0, 2, 2), RegolithSprite.CELL_FILLED, 3, Color.RED)
	doc.mode = SpriteDocument.Mode.GRAPHICS
	doc.clear_region(Rect2i(0, 0, 2, 2))
	assert_eq(doc.get_cell_color(doc.index(0, 0)).a, 0.0, "color cleared")
	assert_eq(doc.get_cell_type(doc.index(0, 0)), RegolithSprite.CELL_FILLED, "mask kept")
	doc.paste_all_layers = true
	doc.clear_region(Rect2i(0, 0, 2, 2))
	assert_eq(doc.get_cell_type(doc.index(0, 0)), RegolithSprite.CELL_EMPTY, "all layers cleared")

func test_resize_keeps_top_left_content() -> void:
	fill_block(Rect2i(0, 0, 4, 4), RegolithSprite.CELL_FILLED, 1, Color.RED)
	doc.resize(8, 8)
	assert_eq(doc.width, 8)
	assert_eq(doc.get_cell_type(doc.index(3, 3)), RegolithSprite.CELL_FILLED)
	assert_eq(doc.get_cell_type(doc.index(7, 7)), RegolithSprite.CELL_EMPTY)
	doc.resize(2, 2)
	assert_eq(doc.cell_count(), 4)
	assert_eq(doc.get_cell_type(doc.index(1, 1)), RegolithSprite.CELL_FILLED)

func test_resize_is_capped() -> void:
	doc.resize(9999, 9999)
	assert_eq(doc.width, SpriteDocument.MAX_SIZE)
	assert_eq(doc.height, SpriteDocument.MAX_SIZE)

func test_undo_redo_stroke() -> void:
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_FILLED
	doc.begin_edit()
	doc.paint_at(1, 1, false)
	doc.end_edit()
	assert_true(doc.can_undo())
	assert_false(doc.can_redo())
	doc.undo()
	assert_eq(doc.get_cell_type(doc.index(1, 1)), RegolithSprite.CELL_EMPTY)
	assert_true(doc.can_redo())
	doc.redo()
	assert_eq(doc.get_cell_type(doc.index(1, 1)), RegolithSprite.CELL_FILLED)

func test_empty_edit_is_not_recorded() -> void:
	doc.begin_edit()
	doc.end_edit()
	assert_false(doc.can_undo())

func test_new_edit_clears_redo() -> void:
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_FILLED
	doc.begin_edit()
	doc.paint_at(1, 1, false)
	doc.end_edit()
	doc.undo()
	doc.begin_edit()
	doc.paint_at(2, 2, false)
	doc.end_edit()
	assert_false(doc.can_redo())

func test_history_limit() -> void:
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_FILLED
	for i in SpriteDocument.HISTORY_LIMIT + 10:
		doc.begin_edit()
		doc.paint_at(i % doc.width, i / doc.width, (i / doc.cell_count()) % 2 == 1)
		doc.end_edit()
	assert_eq(doc.undo_stack.size(), SpriteDocument.HISTORY_LIMIT)

func test_resize_and_clear_are_undoable() -> void:
	fill_block(Rect2i(0, 0, 2, 2), RegolithSprite.CELL_FILLED, 0, Color.RED)
	doc.resize_recorded(20, 20)
	doc.clear_recorded()
	assert_false(doc.has_mask())
	doc.undo()
	assert_true(doc.has_mask())
	assert_eq(doc.width, 20)
	doc.undo()
	assert_eq(doc.width, 16)

func test_mask_image_round_trip_keeps_type_class_emission() -> void:
	fill_block(Rect2i(0, 0, 4, 4), RegolithSprite.CELL_FILLED, 2, Color.RED)
	doc.set_cell_type(doc.index(1, 1), RegolithSprite.CELL_ROPE)
	doc.set_cell_type(doc.index(2, 2), RegolithSprite.CELL_WEAKPOINT3)
	doc.set_cell_class(doc.index(2, 2), 7)
	doc.set_cell_emissive(doc.index(3, 3), true)

	var before := doc.snapshot()
	var other := SpriteDocument.new()
	other.from_images(doc.to_color_image(), doc.to_mask_image())
	assert_true(SpriteDocument.snapshots_equal(before, other.snapshot()))

func test_mask_image_matches_engine_encoding() -> void:
	fill_block(Rect2i(0, 0, 1, 1), RegolithSprite.CELL_CORE, 3, Color.RED)
	doc.set_cell_emissive(0, true)
	var px := doc.to_mask_image().get_pixel(0, 0)
	assert_eq(px.r8, 0)
	assert_eq(px.g8, 200, "core code in green")
	assert_eq(px.b8, 252, "255 minus class in blue")
	assert_eq(px.a8, 254, "emission flag in alpha")

func test_from_images_without_mask_fills_visible_pixels() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.set_pixel(1, 1, Color.RED)
	image.set_pixel(2, 2, Color(0, 0, 0, 1))
	doc.from_images(image, null)
	assert_eq(doc.width, 4)
	assert_eq(doc.get_cell_type(doc.index(1, 1)), RegolithSprite.CELL_FILLED)
	assert_eq(doc.get_cell_type(doc.index(2, 2)), RegolithSprite.CELL_EMPTY, "opaque black is not a cell")
	assert_eq(doc.get_cell_type(doc.index(0, 0)), RegolithSprite.CELL_EMPTY)

func test_decode_mask_pixel_table() -> void:
	assert_eq(SpriteDocument.decode_mask_pixel(0, 100, 255), RegolithSprite.CELL_FILLED)
	assert_eq(SpriteDocument.decode_mask_pixel(0, 253, 255), RegolithSprite.CELL_WEAKPOINT4)
	assert_eq(SpriteDocument.decode_mask_pixel(150, 0, 255), RegolithSprite.CELL_JOINT3)
	assert_eq(SpriteDocument.decode_mask_pixel(250, 0, 255), RegolithSprite.CELL_ROPE)
	assert_eq(SpriteDocument.decode_mask_pixel(250, 0, 0), RegolithSprite.CELL_EMPTY, "blue zero means empty")

func test_display_images_have_document_size() -> void:
	assert_eq(doc.mask_display_image().get_size(), Vector2i(16, 12))
	assert_eq(doc.class_display_image().get_size(), Vector2i(16, 12))
	assert_eq(doc.emission_display_image().get_size(), Vector2i(16, 12))
