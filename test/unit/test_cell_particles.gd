extends GutTest

# no cell ever just vanishes. every cell a commit removes, every rope pixel
# a cut drops and every rope too small to keep is reported through
# cells_removed and spawned into the world's GPUParticles2D child. the
# counts must match what actually went away

const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")
const CELL_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const ROPE_MATERIAL := preload("res://game/shaders/regolith_rope_material.tres")

var world: RegolithWorld
var particles: GPUParticles2D
var removed := 0
var batches := 0

func before_each() -> void:
	removed = 0
	batches = 0
	world = RegolithWorld.new()
	world.pixels_per_cell = 3
	world.gravity = Vector2(0, 4)
	world.cells_removed.connect(func(_sprite, count): removed += count; batches += 1)
	add_child_autofree(world)
	world.sprite_split.connect(func(_source, piece): autofree(piece))

	particles = GPUParticles2D.new()
	particles.process_material = CELL_MATERIAL
	world.add_child(particles)

func after_each() -> void:
	for child in get_children():
		if child is RegolithSprite:
			child.free()

func make_images(rope_len: int) -> Array:
	var w := 8 + rope_len
	var color := Image.create(w, 48, false, Image.FORMAT_RGBA8)
	var mask := Image.create(w, 48, false, Image.FORMAT_RGBA8)

	for y in 48:
		for x in w:
			if x < 8:
				color.set_pixel(x, y, Color(0.5, 0.5, 0.55, 1.0))
				mask.set_pixel(x, y, Color8(0, 100, 255, 255))
			elif y == 16:
				color.set_pixel(x, y, Color(0.9, 0.7, 0.2, 1.0))
				mask.set_pixel(x, y, Color8(250, 0, 255, 255))

	return [color, mask]

func spawn_wall(rope_len := 24) -> RegolithSprite:
	var images := make_images(rope_len)
	var wall := RegolithSprite.new()
	wall.texture = ImageTexture.create_from_image(images[0])
	wall.mask_texture = ImageTexture.create_from_image(images[1])
	wall.rope_material = ROPE_MATERIAL
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

func total_cells() -> int:
	var n := 0
	for s in sprites():
		n += s.get_active_cell_count()
	return n

func settle(frames: int) -> void:
	for i in frames:
		await wait_process_frames(1)
		await wait_physics_frames(1)

func test_world_finds_its_particle_child_and_never_emits_on_its_own() -> void:
	await wait_process_frames(1)
	assert_same(world.get_cell_particles(), particles)
	assert_false(particles.emitting, "only spawn feeds it")
	assert_eq(particles.fixed_fps, 0, "steps every drawn frame")

func test_spawning_with_no_node_in_the_tree_does_nothing() -> void:
	world.remove_child(particles)
	particles.free()
	world.spawn_cell_particle(Vector2(10, 10), Vector2(1, 0), Color.RED, 0.0)
	var wall := spawn_wall()
	await settle(3)
	wall.remove_cell(Vector2i(3, 30))
	await settle(3)
	assert_eq(removed, 1, "the cell still counts as gone")

func test_hole_cells_all_become_particles() -> void:
	var wall := spawn_wall()
	await settle(3)

	var before := total_cells()
	for y in range(30, 40):
		for x in range(2, 6):
			wall.remove_cell(Vector2i(x, y))
	await settle(3)

	assert_eq(removed, 40)
	assert_eq(removed, before - total_cells(), "signal count matches cells lost")
	assert_eq(batches, 1, "one batch per commit")

func test_split_cut_cells_all_become_particles() -> void:
	var wall := spawn_wall()
	await settle(3)

	var before := total_cells()
	for y in range(20, 24):
		for x in 8:
			wall.remove_cell(Vector2i(x, y))
	await settle(3)

	assert_eq(sprites().size(), 2, "wall split in two")
	assert_eq(removed, 32)
	assert_eq(removed, before - total_cells(), "the piece keeps its cells, only the cut ones go")

func test_rope_cut_gap_pixels_become_particles() -> void:
	var wall := spawn_wall()
	await settle(3)

	var points: PackedVector2Array = wall.get_rope_points(0)
	var mid: Vector2 = points[0].lerp(points[-1], 0.5)
	assert_eq(world.hit_ropes(mid + Vector2(0, -20), mid + Vector2(0, 20), null), 1)
	await settle(3)

	assert_between(removed, 1, 4, "the gap is a cell or so wide")
	assert_eq(batches, 1)

func test_short_rope_bursts_into_one_pixel_per_drawn_cell() -> void:
	var stub := spawn_wall(2)
	await settle(3)
	assert_eq(stub.get_rope_count(), 1)

	var before := total_cells()
	for y in range(13, 20):
		for x in 8:
			stub.remove_cell(Vector2i(x, y))
	await settle(3)

	var lost := before - total_cells()
	assert_eq(lost, 8 * 7, "the cut rows are gone")
	assert_between(removed - lost, 1, 3, "two rope cells burst, one pixel each")
	assert_eq(sprites().filter(func(s): return s.get_cell_count() == Vector2i(0, 0)).size(), 0, "no rope piece for a stub")

func test_particles_fly_out_of_a_hit_block() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a renderer, run from the editor")
		return

	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.1, 0.1, 1.0))

	var block := RegolithSprite.new()
	block.texture = ImageTexture.create_from_image(img)
	block.material = SPRITE_MATERIAL
	block.dynamic = false
	block.position = Vector2(400, 300)
	add_child_autofree(block)
	await settle(3)

	for y in range(8, 40):
		for x in range(8, 40):
			block.remove_cell(Vector2i(x, y))
	await settle(30)

	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	var block_rect := Rect2(400 - 76, 300 - 76, 152, 152)
	var outside := 0
	for y in range(0, shot.get_height(), 2):
		for x in range(0, shot.get_width(), 2):
			var c := shot.get_pixel(x, y)
			if c.r > 0.5 and c.g < 0.3 and not block_rect.has_point(Vector2(x, y)):
				outside += 1

	assert_eq(removed, 32 * 32)
	assert_gt(outside, 50, "red cell particles left the block")
