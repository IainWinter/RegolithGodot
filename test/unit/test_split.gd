extends GutTest

# a dumbbell shaped sprite: cut the bridge and it splits into two bodies

var world: RegolithWorld
var sprite: RegolithSprite

func make_texture() -> ImageTexture:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var filled := (x < 24 and y >= 4 and y < 28) or (x >= 40 and y >= 4 and y < 28) or (x >= 24 and x < 40 and y >= 14 and y < 18)
			if filled:
				img.set_pixel(x, y, Color(0.6, 0.4, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

func before_each() -> void:
	world = RegolithWorld.new()
	world.gravity = Vector2.ZERO
	world.pixels_per_cell = 3
	add_child_autofree(world)
	world.sprite_split.connect(func(_source, piece): autofree(piece))

	sprite = RegolithSprite.new()
	sprite.texture = make_texture()
	sprite.position = Vector2(200, 150)
	add_child_autofree(sprite)
	await wait_physics_frames(2)

func cut_bridge() -> void:
	for y in range(14, 18):
		sprite.remove_cell(Vector2i(32, y))

func test_texture_loads_into_cells() -> void:
	assert_eq(sprite.get_active_cell_count(), 24 * 24 * 2 + 16 * 4)
	assert_eq(sprite.get_cell_count(), Vector2i(64, 32))
	assert_gt(sprite.get_mass(), 0.0)
	assert_eq(world.get_sprite_count(), 1)

	var cell := sprite.world_to_cell(Vector2(200, 150))
	assert_true(sprite.has_cell(cell), "center of the bridge is a cell")

func test_cutting_bridge_splits_sprite() -> void:
	watch_signals(world)
	var pieces := []
	world.sprite_split.connect(func(_source, piece): pieces.append(piece))

	cut_bridge()
	await wait_physics_frames(2)

	assert_signal_emitted(world, "sprite_split")
	assert_eq(world.get_sprite_count(), 2)
	assert_eq(pieces.size(), 1)
	var total: int = sprite.get_active_cell_count() + pieces[0].get_active_cell_count()
	assert_eq(total, 24 * 24 * 2 + 16 * 4 - 4, "no cells lost besides the four removed")

func test_impulse_moves_and_spins() -> void:
	var start := sprite.global_position
	sprite.apply_impulse(Vector2(0, -2), sprite.global_position + Vector2(-10, 0))
	await wait_physics_frames(30)
	assert_ne(sprite.global_position, start)
	assert_ne(sprite.global_rotation, 0.0, "off center impulse spins it")
	assert_ne(sprite.linear_velocity, Vector2.ZERO)

func test_burn_cell_with_damage_removes_it() -> void:
	var before := sprite.get_active_cell_count()
	sprite.burn_cell(Vector2i(10, 10), 255, 1)
	await wait_physics_frames(1)
	assert_false(sprite.has_cell(Vector2i(10, 10)))
	assert_eq(sprite.get_active_cell_count(), before - 1)
	assert_eq(world.get_sprite_count(), 1, "still one body")
