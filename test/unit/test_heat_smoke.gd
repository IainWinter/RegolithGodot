extends GutTest

# super hot cells smoke: the world lists cells at the white hot end of the
# heat ramp without scanning sprites (get_hot_cells), and the HeatSmoke node
# in Main polls it and puffs heat_smoke.tres through the EffectSpawner,
# capped per second

const HEAT_SMOKE_PROPS := preload("res://game/config/effects/heat_smoke.tres")

func make_texture() -> ImageTexture:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var filled := (x < 24 and y >= 4 and y < 28) or (x >= 40 and y >= 4 and y < 28) or (x >= 24 and x < 40 and y >= 14 and y < 18)
			if filled:
				img.set_pixel(x, y, Color(0.6, 0.4, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

func make_world() -> Array:
	var world := RegolithWorld.new()
	world.gravity = Vector2.ZERO
	world.pixels_per_cell = 3
	add_child_autofree(world)
	world.sprite_split.connect(func(_source, piece): autofree(piece))

	var sprite := RegolithSprite.new()
	sprite.texture = make_texture()
	sprite.position = Vector2(200, 150)
	add_child_autofree(sprite)
	await wait_physics_frames(2)
	return [world, sprite]

# heat 15, no damage so the cell stays
func heat(sprite: RegolithSprite, cell: Vector2i) -> void:
	sprite.burn_cell(cell, 255, 0)

func test_cold_sprite_has_no_hot_cells() -> void:
	var made: Array = await make_world()
	var world: RegolithWorld = made[0]
	assert_eq(world.get_hot_cells(12, 64).size(), 0)
	assert_eq(world.get_hot_cells(0, 64).size(), 0)

func test_hot_cell_is_listed_at_its_world_position() -> void:
	var made: Array = await make_world()
	var world: RegolithWorld = made[0]
	var sprite: RegolithSprite = made[1]
	heat(sprite, Vector2i(10, 10))

	var cells := world.get_hot_cells(12, 64)
	assert_eq(cells.size(), 1)
	var expected := sprite.cell_to_world(Vector2i(10, 10))
	assert_almost_eq(Vector2(cells[0].x, cells[0].y), expected, Vector2(0.01, 0.01))
	assert_eq(cells[0].z, 15.0, "full strength burn is heat 15")
	assert_true(sprite.has_cell(Vector2i(10, 10)), "no damage keeps the cell")

func test_weak_burn_is_not_white_hot() -> void:
	var made: Array = await make_world()
	var world: RegolithWorld = made[0]
	var sprite: RegolithSprite = made[1]
	# strength 170 is heat 10: glowing, not white hot
	sprite.burn_cell(Vector2i(10, 10), 170, 0)
	assert_eq(world.get_hot_cells(12, 64).size(), 0)
	assert_eq(world.get_hot_cells(10, 64).size(), 1)

func test_max_count_samples_down() -> void:
	var made: Array = await make_world()
	var world: RegolithWorld = made[0]
	var sprite: RegolithSprite = made[1]
	for x in range(4, 14):
		for y in range(8, 11):
			heat(sprite, Vector2i(x, y))

	assert_eq(world.get_hot_cells(12, 100).size(), 30)
	assert_eq(world.get_hot_cells(12, 5).size(), 5)
	assert_eq(world.get_hot_cells(12, 0).size(), 0)

func test_removed_cell_drops_out() -> void:
	var made: Array = await make_world()
	var world: RegolithWorld = made[0]
	var sprite: RegolithSprite = made[1]
	heat(sprite, Vector2i(10, 10))
	sprite.remove_cell(Vector2i(10, 10))
	await wait_process_frames(2)
	assert_eq(world.get_hot_cells(12, 64).size(), 0)

func test_hot_cells_follow_a_split_piece() -> void:
	var made: Array = await make_world()
	var world: RegolithWorld = made[0]
	var sprite: RegolithSprite = made[1]
	heat(sprite, Vector2i(50, 10))
	for y in range(14, 18):
		sprite.remove_cell(Vector2i(32, y))
	await wait_physics_frames(2)

	assert_eq(world.get_sprite_count(), 2, "split")
	assert_eq(world.get_hot_cells(12, 64).size(), 1, "hot cell kept on whichever side holds it")

func test_hot_cells_cool_off() -> void:
	var made: Array = await make_world()
	var world: RegolithWorld = made[0]
	var sprite: RegolithSprite = made[1]
	heat(sprite, Vector2i(10, 10))
	# heat 15..12 each drop one level per 0.25 s decay tick
	await wait_seconds(1.6)
	assert_eq(world.get_hot_cells(12, 64).size(), 0, "no longer white hot")
	await wait_seconds(1.2)
	assert_eq(world.get_hot_cells(0, 64).size(), 0, "below the listed floor")

# HeatSmoke in Main

var main: Node2D
var smoke: Node
var rock: RegolithSprite
var particles: ParticleEffect

func load_main() -> void:
	main = load("res://game/scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	smoke = main.get_node("HeatSmoke")
	rock = main.get_node("Rock")
	particles = (main.get_node("EffectSpawner") as EffectSpawner).particles
	await wait_physics_frames(3)

func after_each() -> void:
	if main != null and is_instance_valid(main):
		main.free()
	main = null

# heats up to count filled cells around the rock's middle, returns how many
func heat_rock(count: int) -> int:
	var center := rock.world_to_cell(EffectSpawner.effect_origin(rock))
	var heated := 0
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var cell := center + Vector2i(dx, dy)
			if heated < count and rock.has_cell(cell):
				heat(rock, cell)
				heated += 1
	return heated

func test_main_has_heat_smoke() -> void:
	await load_main()
	assert_not_null(smoke)
	assert_eq(smoke.props, HEAT_SMOKE_PROPS)
	assert_true(smoke.is_processing(), "polls on the drawn frame")

func test_hot_rock_smokes() -> void:
	await load_main()
	assert_gt(heat_rock(40), 30)
	await wait_seconds(0.5)
	assert_gt(smoke.puffs, 0, "white hot cells puff")
	assert_eq(particles.count_of(HEAT_SMOKE_PROPS), smoke.puffs, "each puff is one particle")

func test_cold_world_does_not_smoke() -> void:
	await load_main()
	await wait_seconds(0.5)
	assert_eq(smoke.puffs, 0)
	assert_eq(particles.count_of(HEAT_SMOKE_PROPS), 0)

func test_puffs_per_second_capped() -> void:
	await load_main()
	smoke.max_puffs_per_second = 10.0
	smoke.puffs_per_second_per_heat = 1000.0
	assert_gt(heat_rock(200), 100)

	var start := Time.get_ticks_msec()
	await wait_seconds(0.8)
	var seconds := (Time.get_ticks_msec() - start) / 1000.0
	assert_gt(smoke.puffs, 0)
	# the budget refills with frame time, allow a frame or two of slack
	assert_lte(smoke.puffs, int(ceil(10.0 * (seconds + 0.1))) + 1, "no more than the cap per second")
