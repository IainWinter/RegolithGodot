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

func test_impulse_cap_limits_speed_and_spin() -> void:
	# a hit far too big for this sprite, capped so it only nudges it
	sprite.apply_impulse(Vector2(0, -50), sprite.global_position + Vector2(-60, 0), 2.0, 1.5)
	assert_almost_eq(sprite.linear_velocity.length(), 2.0, 0.01, "speed change capped")
	assert_almost_eq(absf(sprite.angular_velocity), 1.5, 0.01, "spin change capped on its own")

func test_impulse_cap_leaves_small_hits_alone() -> void:
	sprite.apply_impulse(Vector2(0, -0.01), sprite.global_position + Vector2(-10, 0), 2.0, 1.5)
	var uncapped := RegolithSprite.new()
	uncapped.texture = make_texture()
	uncapped.position = Vector2(200, 400)
	add_child_autofree(uncapped)
	await wait_physics_frames(2)
	uncapped.apply_impulse(Vector2(0, -0.01), uncapped.global_position + Vector2(-10, 0))
	assert_almost_eq(sprite.angular_velocity, uncapped.angular_velocity, 0.0001, "cap does nothing under the limit")

func test_world_clamps_runaway_spin_and_speed() -> void:
	sprite.angular_velocity = 200.0
	sprite.linear_velocity = Vector2(500, 0)
	await wait_physics_frames(1)
	assert_lt(absf(sprite.angular_velocity), 8.0 + 0.01, "spin clamped to the world limit")
	assert_lt(sprite.linear_velocity.length(), 64.0 + 0.01, "speed clamped to the world limit")

func test_burn_cell_with_damage_removes_it() -> void:
	var before := sprite.get_active_cell_count()
	sprite.burn_cell(Vector2i(10, 10), 255, 1)
	await wait_physics_frames(1)
	assert_false(sprite.has_cell(Vector2i(10, 10)))
	assert_eq(sprite.get_active_cell_count(), before - 1)
	assert_eq(world.get_sprite_count(), 1, "still one body")
