extends GutTest

# RockGenerator images and spawned rocks, RockSpawner keeping a belt around
# a target: fills to max_rocks outside the view, frees rocks that drift away.
# the belt asks the StableSpawner under the test for its rocks

const PROPS := preload("res://game/config/rocks/default_rock.tres")
const MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")

var world: RegolithWorld
var stable: StableSpawner

func before_each() -> void:
	world = RegolithWorld.new()
	world.gravity = Vector2.ZERO
	add_child_autofree(world)
	stable = StableSpawner.new()
	stable.sprite_material = MATERIAL
	add_child_autofree(stable)

func mask_type(mask: Image, x: int, y: int) -> int:
	var p := mask.get_pixel(x, y)
	return SpriteDocument.decode_mask_pixel(p.r8, p.g8, p.b8)

func test_generate_gives_asked_size_with_a_filled_middle_and_empty_corners() -> void:
	var images := RockGenerator.generate(5, Vector2i(64, 64), PROPS)
	var color: Image = images["color"]
	var mask: Image = images["mask"]

	assert_eq(color.get_size(), Vector2i(64, 64))
	assert_eq(mask.get_size(), Vector2i(64, 64))
	assert_eq(color.get_pixel(32, 32).a8, 255, "middle is rock")
	assert_eq(mask_type(mask, 32, 32), RegolithSprite.CELL_FILLED)

	for corner in [Vector2i(0, 0), Vector2i(63, 0), Vector2i(0, 63), Vector2i(63, 63)]:
		assert_eq(color.get_pixel(corner.x, corner.y).a8, 0, "corner %s is empty" % corner)
		assert_eq(mask_type(mask, corner.x, corner.y), RegolithSprite.CELL_EMPTY)

	var filled := 0
	var mismatches := 0
	for y in 64:
		for x in 64:
			var is_rock := color.get_pixel(x, y).a8 == 255
			var is_filled := mask_type(mask, x, y) == RegolithSprite.CELL_FILLED
			if is_rock:
				filled += 1
			if is_rock != is_filled:
				mismatches += 1

	assert_eq(mismatches, 0, "mask filled cells match the color alpha")
	assert_between(filled, 64 * 64 / 4, 64 * 64 * 3 / 4, "a rough disc fills a good part of the image")

func test_generate_is_deterministic_for_a_seed() -> void:
	var a := RockGenerator.generate(11, Vector2i(32, 32), PROPS)
	var b := RockGenerator.generate(11, Vector2i(32, 32), PROPS)
	var c := RockGenerator.generate(12, Vector2i(32, 32), PROPS)
	assert_eq(a["color"].get_data(), b["color"].get_data())
	assert_ne(a["color"].get_data(), c["color"].get_data())

func test_ore_paints_tinted_cells_with_the_ore_class() -> void:
	var tint := Color8(255, 90, 70)
	var images := RockGenerator.generate(3, Vector2i(96, 96), PROPS, tint)
	var color: Image = images["color"]
	var mask: Image = images["mask"]

	var ore_cells := 0
	for y in 96:
		for x in 96:
			if mask.get_pixel(x, y) == SpriteDocument.encode_mask_pixel(RegolithSprite.CELL_FILLED, PROPS.ore_class):
				ore_cells += 1
				assert_eq(color.get_pixel(x, y), Color8(255, 90, 70, 255), "ore cell at %d,%d is tinted" % [x, y])
				if color.get_pixel(x, y) != Color8(255, 90, 70, 255):
					return

	assert_gt(ore_cells, 0, "some ore cells")
	assert_lt(ore_cells, 96 * 96 / 4, "ore is a few clusters, not the whole rock")

func test_make_rock_picks_a_whole_number_of_chunks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9

	for i in 6:
		var images := RockGenerator.make_rock(rng, PROPS)
		var size: Vector2i = images["color"].get_size()
		var chunks: int = images["chunks"]
		assert_between(chunks, PROPS.min_chunks, PROPS.max_chunks)
		assert_eq(size, Vector2i.ONE * chunks * RegolithWorld.CELLS_PER_CHUNK)
		assert_eq(images["mask"].get_size(), size)

func test_generate_without_a_source_texture_still_fills() -> void:
	var plain: RockProps = PROPS.duplicate()
	plain.source_texture = null
	var images := RockGenerator.generate(4, Vector2i(32, 32), plain)
	assert_eq(images["color"].get_pixel(16, 16).a8, 255)
	assert_gt(images["color"].get_pixel(16, 16).r8, 0, "grey noise colors the rock")

func test_spawn_rock_loads_a_moving_sprite_into_the_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2

	var rock := RockGenerator.spawn_rock(self, world, Vector2(300, 200), rng, PROPS, MATERIAL)
	autofree(rock)

	assert_not_null(rock)
	assert_true(rock.is_loaded())
	assert_gt(rock.get_active_cell_count(), 0)
	assert_eq(world.get_sprite_count(), 1)
	assert_true(rock.is_in_group("regolith"))
	assert_true(rock.is_dynamic())
	assert_eq(rock.material, MATERIAL)
	assert_gt(rock.get_mass(), 0.0)
	assert_gt(rock.linear_velocity.length(), 0.0, "drifts")
	assert_eq(rock.global_position, Vector2(300, 200))

	var cells := rock.get_active_cell_count()
	await wait_physics_frames(3)
	assert_eq(rock.get_active_cell_count(), cells, "a solid rock keeps its cells")
	assert_ne(rock.global_position, Vector2(300, 200), "moved with its velocity")
	assert_eq(world.get_sprite_count(), 1)

func test_spawn_rock_without_a_world_in_the_tree_gives_null() -> void:
	var rng := RandomNumberGenerator.new()
	var loose := RegolithWorld.new()
	autofree(loose)
	assert_null(RockGenerator.spawn_rock(self, loose, Vector2.ZERO, rng, PROPS, MATERIAL))

func make_spawner(target: Node2D) -> RockSpawner:
	var spawner := RockSpawner.new()
	spawner.target = target
	spawner.props = PROPS
	spawner.max_rocks = 3
	spawner.spawn_interval = 0.0
	spawner.seed = 3
	spawner.view_radius_units = 2.0
	spawner.view_margin_units = 0.5
	spawner.radius_units = 8.0
	spawner.despawn_radius_units = 12.0
	add_child_autofree(spawner)
	return spawner

func test_spawner_fills_to_max_rocks_outside_the_view() -> void:
	var target := Node2D.new()
	target.position = Vector2(100, 50)
	add_child_autofree(target)

	var spawner := make_spawner(target)
	watch_signals(spawner)
	await wait_physics_frames(12)

	assert_eq(spawner.rocks.size(), 3)
	assert_eq(world.get_sprite_count(), 3)
	assert_signal_emit_count(spawner, "rock_spawned", 3)

	var ppu := RegolithWorld.pixels_per_unit()
	for rock in spawner.rocks:
		assert_true(rock.is_loaded())
		assert_gt(rock.get_active_cell_count(), 0)
		var distance: float = target.global_position.distance_to(rock.global_position)
		assert_gt(distance, spawner.view_radius(), "rock outside the view")
		assert_lt(distance, spawner.radius_units * ppu + 1.0, "rock inside the belt")

	for a in spawner.rocks:
		for b in spawner.rocks:
			if a != b:
				var halves: float = (Steering.half_extent_units(a).x + Steering.half_extent_units(b).x) * ppu
				assert_gt(a.global_position.distance_to(b.global_position), halves - 1.0)

	await wait_physics_frames(6)
	assert_eq(spawner.rocks.size(), 3, "stays at max")

func test_spawner_frees_a_rock_that_drifts_away_and_spawns_another() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var spawner := make_spawner(target)
	await wait_physics_frames(12)
	assert_eq(spawner.rocks.size(), 3)

	var runaway: RegolithSprite = spawner.rocks[0]
	var runaway_id := runaway.get_instance_id()
	runaway.linear_velocity = Vector2(2000.0, 0.0)
	await wait_physics_frames(4)

	assert_false(is_instance_valid(runaway), "freed once past the despawn radius")

	await wait_physics_frames(6)
	assert_eq(spawner.rocks.size(), 3, "a new rock took its place")
	assert_eq(world.get_sprite_count(), 3)
	for rock in spawner.rocks:
		assert_ne(rock.get_instance_id(), runaway_id, "the runaway is gone from the list")

func test_spawner_waits_for_a_world() -> void:
	remove_child(world)
	var spawner := make_spawner(null)
	await wait_physics_frames(6)
	assert_eq(spawner.rocks.size(), 0, "no world, no rocks")
	assert_null(spawner.world)

	add_child(world)
	await wait_physics_frames(12)
	assert_eq(spawner.rocks.size(), 3, "rocks once a world arrived")

func test_spawner_falls_back_to_the_player_group() -> void:
	var player := RegolithSprite.new()
	player.add_to_group("player")
	player.position = Vector2(-500, 300)
	add_child_autofree(player)

	var spawner := make_spawner(null)
	await wait_physics_frames(12)

	assert_eq(spawner.target, player)
	for rock in spawner.rocks:
		assert_lt(player.global_position.distance_to(rock.global_position), spawner.radius_units * RegolithWorld.pixels_per_unit() + 1.0)

func test_spawn_rock_enters_the_tree_at_its_spot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var holder := Node2D.new()
	holder.position = Vector2(40, -30)
	holder.rotation = 0.3
	add_child_autofree(holder)

	var seen := {}
	var on_added := func(node: Node) -> void:
		if node is RegolithSprite and not seen.has("position"):
			seen["position"] = node.global_position
			seen["rotation"] = node.global_rotation
	get_tree().node_added.connect(on_added)

	var spot := Vector2(1200, -800)
	var rock := RockGenerator.spawn_rock(holder, world, spot, rng, PROPS, MATERIAL)
	get_tree().node_added.disconnect(on_added)
	autofree(rock)

	assert_true(seen.has("position"), "saw the rock enter the tree")
	if not seen.has("position"):
		return
	assert_almost_eq(seen["position"], spot, Vector2.ONE * 0.01, "at its spot when it entered the tree")
	assert_almost_eq(seen["rotation"], rock.global_rotation, 0.001, "at its rotation when it entered the tree")
	assert_almost_eq(rock.global_position, spot, Vector2.ONE * 0.01)
	assert_true(rock.is_loaded())

func test_main_scene_spawner_keeps_its_rocks() -> void:
	remove_child(world)
	world.free()
	world = null

	var main: Node2D = load("res://game/scenes/Main.tscn").instantiate()
	add_child_autofree(main)

	var spawner: RockSpawner = main.find_child("RockSpawner")
	var player: Node2D = main.find_child("Player")
	var ppu := RegolithWorld.pixels_per_unit()

	var frame := 0
	while spawner.rocks.is_empty() and frame < 12:
		await wait_physics_frames(1)
		frame += 1

	assert_eq(spawner.rocks.size(), 1, "a rock within a few frames")
	if spawner.rocks.is_empty():
		return

	var first: RegolithSprite = spawner.rocks[0]
	assert_true(first.is_loaded(), "fresh rock is loaded")
	var cells := first.get_active_cell_count()
	assert_gt(cells, 0, "fresh rock has cells")
	var first_distance := player.global_position.distance_to(first.global_position) / ppu
	assert_gt(first_distance, spawner.view_radius() / ppu, "spawned outside the view")
	assert_lt(first_distance, spawner.despawn_radius_units, "spawned inside the despawn radius")

	await wait_physics_frames(30)
	frame += 30
	assert_true(is_instance_valid(first) and first.is_loaded(), "the first rock is still loaded 30 frames later")
	if is_instance_valid(first):
		assert_eq(first.get_active_cell_count(), cells, "and keeps its cells")
		assert_true(first in spawner.rocks, "and is still listed")

	await wait_physics_frames(60 - frame)
	assert_gt(spawner.rocks.size(), 1, "rocks keep coming")
	var alive: Array = spawner.rocks.duplicate()
	var count_60 := alive.size()

	await wait_physics_frames(60)

	var despawn := spawner.despawn_radius_units * ppu
	for rock in alive:
		if not is_instance_valid(rock):
			fail_test("a rock alive at frame 60 was freed by frame 120")
		elif player.global_position.distance_to(rock.global_position) <= despawn:
			assert_true(rock in spawner.rocks, "a rock inside the despawn radius stays listed")

	assert_gte(spawner.rocks.size(), count_60, "the belt does not shrink")
