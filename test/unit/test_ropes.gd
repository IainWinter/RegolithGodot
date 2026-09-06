extends GutTest

# ropes: a wall on the left with a rope sticking out sideways. gravity swings
# it down, cutting the anchor detaches it, cutting the wall above the anchor
# moves it onto the split piece, and a bullet sweep cuts the rope itself

var world: RegolithWorld

func before_each() -> void:
	world = RegolithWorld.new()
	world.pixels_per_cell = 3
	world.gravity = Vector2(0, 4)
	add_child_autofree(world)
	world.sprite_split.connect(func(_source, piece): autofree(piece))

func after_each() -> void:
	# rope pieces cut loose by hit_ropes are spawned by the world without
	# a split signal, sweep any sprite still hanging under the test
	for child in get_children():
		if child is RegolithSprite:
			child.free()

func make_images(width: int, rope_row: int) -> Array:
	var color := Image.create(width, 48, false, Image.FORMAT_RGBA8)
	var mask := Image.create(width, 48, false, Image.FORMAT_RGBA8)

	for y in 48:
		for x in width:
			if x < 8:
				color.set_pixel(x, y, Color(0.5, 0.5, 0.55, 1.0))
				mask.set_pixel(x, y, Color8(0, 100, 255, 255))
			elif y == rope_row:
				color.set_pixel(x, y, Color(0.9, 0.7, 0.2, 1.0))
				mask.set_pixel(x, y, Color8(250, 0, 255, 255))

	return [color, mask]

func spawn_wall(width := 32, rope_row := 16) -> RegolithSprite:
	var images := make_images(width, rope_row)
	var wall := RegolithSprite.new()
	wall.texture = ImageTexture.create_from_image(images[0])
	wall.mask_texture = ImageTexture.create_from_image(images[1])
	wall.dynamic = false
	wall.position = Vector2(300, 100)
	add_child_autofree(wall)
	return wall

func sprites() -> Array:
	var out := []
	for child in get_children():
		if child is RegolithSprite:
			out.append(child)
	return out

func rope_holders() -> Array:
	return sprites().filter(func(s): return s.get_rope_count() > 0)

func rope_pieces() -> Array:
	return rope_holders().filter(func(s): return s.get_cell_count() == Vector2i(0, 0))

func cut_rows(sprite: RegolithSprite, first: int, last: int) -> void:
	for y in range(first, last + 1):
		for x in 8:
			sprite.remove_cell(Vector2i(x, y))

func settle(frames: int) -> void:
	for i in frames:
		await wait_process_frames(1)
		await wait_physics_frames(1)

func test_rope_is_scanned_from_mask() -> void:
	var wall := spawn_wall()
	await wait_physics_frames(3)
	assert_eq(wall.get_rope_count(), 1)
	assert_eq(wall.count_cells_of_type(RegolithSprite.CELL_ROPE), 0, "rope cells leave the grid and become the rope")
	assert_eq(wall.get_active_cell_count(), 8 * 48, "wall cells stay")
	assert_gt(wall.get_rope_points(0).size(), 2)

func test_rope_sags_under_gravity_but_keeps_shape() -> void:
	# ropes are shape stiff (solve_rope_shape), so a sideways rope only
	# sags a little instead of swinging down like a pendulum
	var wall := spawn_wall()
	await wait_physics_frames(3)
	var before: PackedVector2Array = wall.get_rope_points(0)
	await wait_physics_frames(120)
	var after: PackedVector2Array = wall.get_rope_points(0)
	assert_eq(after.size(), before.size())
	assert_almost_eq(after[0], before[0], Vector2(2, 2), "root stays anchored")
	assert_gt(after[-1].y, before[-1].y + 1.0, "tip sags")
	assert_lt(after[-1].y, before[-1].y + 24.0, "but holds its shape")
	assert_almost_eq(after[-1].x, before[-1].x, 6.0, "tip stays out sideways")

func test_cutting_anchor_detaches_rope_as_piece() -> void:
	var wall := spawn_wall()
	await wait_physics_frames(3)
	var before: PackedVector2Array = wall.get_rope_points(0)

	cut_rows(wall, 13, 19)
	await settle(3)

	assert_eq(wall.get_rope_count(), 0, "wall lost its rope")
	assert_eq(rope_holders().size(), 1)
	assert_eq(rope_pieces().size(), 1, "one rope piece spawned")

	var piece: RegolithSprite = rope_pieces()[0]
	var start: PackedVector2Array = piece.get_rope_points(0)
	assert_lt(start[0].distance_to(before[0]), 8.0, "loose rope started where it hung")

	await wait_physics_frames(60)
	var after: PackedVector2Array = piece.get_rope_points(0)
	assert_gt(after[0].y, start[0].y + 20.0, "loose rope falls")
	assert_gt(after[-1].y, start[-1].y + 20.0)

func test_rope_follows_split_piece() -> void:
	var wall := spawn_wall(32, 44)
	await wait_physics_frames(3)
	var hung: PackedVector2Array = wall.get_rope_points(0)

	cut_rows(wall, 36, 40)
	await settle(3)

	assert_eq(rope_holders().size(), 1, "rope on exactly one sprite")
	assert_eq(rope_pieces().size(), 0, "and that sprite has cells")

	var holder: RegolithSprite = rope_holders()[0]
	assert_ne(holder, wall, "rope moved onto the split piece")

	await wait_physics_frames(30)
	var points: PackedVector2Array = holder.get_rope_points(0)
	assert_lt(points[0].distance_to(hung[0]), 4.0, "still anchored where it hung")
	assert_lt(points[-1].distance_to(hung[-1]), 12.0, "holds its shape on the piece")

func test_bullet_sweep_cuts_rope() -> void:
	var wall := spawn_wall(48, 16)
	await settle(3)

	var points: PackedVector2Array = wall.get_rope_points(0)
	var root_point := points[0]
	var mid := root_point.lerp(points[-1], 0.5)

	assert_eq(world.hit_ropes(mid + Vector2(0, -30), mid + Vector2(0, -20), null), 0, "sweep above misses")
	assert_eq(world.hit_ropes(mid + Vector2(0, -20), mid + Vector2(0, 20), null), 1, "sweep through hits once")

	await settle(3)

	assert_eq(wall.get_rope_count(), 1, "wall keeps the anchored half")
	assert_eq(rope_pieces().size(), 1, "loose half became a rope piece")

	var head: PackedVector2Array = wall.get_rope_points(0)
	assert_lt(head[0].distance_to(root_point), 4.0)
	assert_lt(head[-1].x, mid.x + 6.0, "anchored half ends before the cut")

	var piece: RegolithSprite = rope_pieces()[0]
	var start: PackedVector2Array = piece.get_rope_points(0)
	assert_gt(start[0].x, mid.x - 6.0, "loose half starts past the cut")

	await wait_physics_frames(60)
	var after: PackedVector2Array = piece.get_rope_points(0)
	assert_gt(after[0].y, start[0].y + 20.0, "loose half falls")

func test_shooter_own_ropes_are_skipped() -> void:
	var wall := spawn_wall(48, 16)
	await settle(3)
	var root_point: Vector2 = wall.get_rope_points(0)[0]
	assert_eq(world.hit_ropes(root_point + Vector2(6, -20), root_point + Vector2(6, 20), wall), 0)
	assert_eq(wall.get_rope_count(), 1)
