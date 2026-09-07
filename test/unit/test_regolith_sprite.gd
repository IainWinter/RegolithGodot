extends GutTest

# RegolithSprite cell editing api, image export and reload, joints

var world: RegolithWorld
var sprite: RegolithSprite

func before_each() -> void:
	world = RegolithWorld.new()
	world.pixels_per_cell = 3
	add_child_autofree(world)

	sprite = RegolithSprite.new()
	sprite.dynamic = false
	add_child_autofree(sprite)
	await wait_process_frames(1)

func paint_sample() -> void:
	sprite.create_blank(Vector2i(40, 24))
	sprite.fill_rect(Rect2i(4, 4, 20, 10), Color(0.5, 0.4, 0.3), RegolithSprite.CELL_FILLED, 0)
	sprite.set_cell(Vector2i(10, 10), Color(1, 0.5, 0), RegolithSprite.CELL_CORE, 3)
	sprite.set_cell(Vector2i(38, 22), Color(0.2, 0.9, 0.2), RegolithSprite.CELL_FILLED, 5)
	sprite.clear_cell(Vector2i(5, 5))
	sprite.clear_rect(Rect2i(20, 4, 4, 2))

func test_create_blank_rounds_up_to_chunks() -> void:
	sprite.create_blank(Vector2i(40, 24))
	assert_true(sprite.is_loaded())
	assert_eq(sprite.get_cell_count(), Vector2i(64, 32), "size rounds up to whole chunks")
	assert_eq(sprite.get_active_cell_count(), 0)

func test_paint_and_clear_cells() -> void:
	paint_sample()
	assert_eq(sprite.get_active_cell_count(), 192)
	assert_eq(sprite.count_cells_of_type(RegolithSprite.CELL_CORE), 1)
	assert_eq(sprite.get_cell_type(Vector2i(10, 10)), RegolithSprite.CELL_CORE)
	assert_eq(sprite.get_cell_class(Vector2i(10, 10)), 3)
	assert_eq(sprite.get_cell_color(Vector2i(10, 10)), Color8(255, 128, 0, 255))
	assert_eq(sprite.get_cell_class(Vector2i(38, 22)), 5)
	assert_false(sprite.has_cell(Vector2i(5, 5)), "clear_cell")
	assert_false(sprite.has_cell(Vector2i(21, 4)), "clear_rect")

func test_images_reload_into_another_sprite() -> void:
	paint_sample()

	var color := sprite.get_color_image()
	var mask := sprite.get_mask_image()
	assert_eq(color.get_size(), Vector2i(40, 24))
	assert_eq(mask.get_size(), Vector2i(40, 24))
	assert_eq(mask.get_pixel(10, 10).g8, 200, "core code in green")
	assert_eq(mask.get_pixel(10, 10).b8, 252, "class 3 in blue")
	assert_eq(color.get_pixel(10, 10), Color8(255, 128, 0, 255))

	var copy := RegolithSprite.new()
	copy.dynamic = false
	copy.position = Vector2(400, 0)
	add_child_autofree(copy)
	copy.load_from_images(color, mask)

	assert_eq(copy.get_active_cell_count(), 192)
	assert_eq(copy.count_cells_of_type(RegolithSprite.CELL_CORE), 1)
	assert_eq(copy.get_cell_class(Vector2i(10, 10)), 3)
	assert_eq(copy.get_cell_class(Vector2i(38, 22)), 5)

func test_commit_drops_isolated_cell() -> void:
	paint_sample()
	await wait_physics_frames(3)
	assert_eq(sprite.get_active_cell_count(), 191, "the lone cell at 38,22 falls away")
	assert_eq(world.get_sprite_count(), 1, "a single cell is too small to become a piece")
	assert_false(sprite.has_cell(Vector2i(38, 22)))
	assert_eq(sprite.get_mass(), 0.0, "static sprites have no mass")

func test_joints_add_and_remove() -> void:
	paint_sample()
	var other := RegolithSprite.new()
	other.dynamic = false
	other.position = Vector2(400, 0)
	add_child_autofree(other)
	other.create_blank(Vector2i(8, 8))
	other.fill_rect(Rect2i(0, 0, 8, 8), Color.WHITE, RegolithSprite.CELL_FILLED, 0)
	await wait_physics_frames(2)

	var joint := world.add_joint(sprite, other, other.global_position)
	assert_gte(joint, 0)
	assert_eq(world.get_joint_count(), 1)
	assert_eq(world.get_joint_anchors(joint)[0], other.global_position)
	world.remove_joint(joint)
	assert_eq(world.get_joint_count(), 0)
