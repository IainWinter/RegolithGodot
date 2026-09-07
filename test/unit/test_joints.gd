extends GutTest

# joints between sprites: pins hold a shared point, pins to static sprites
# hold dynamic ones, joints drop with their sprite and follow split pieces.
# velocities are sim units per second, one unit is 32 cells

var world: RegolithWorld
var cell_px := 3.0

func before_each() -> void:
	world = RegolithWorld.new()
	world.gravity = Vector2.ZERO
	world.pixels_per_cell = int(cell_px)
	add_child_autofree(world)
	world.sprite_split.connect(func(_source, piece): autofree(piece))

func block_texture(size: Vector2i) -> ImageTexture:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.4, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

func dumbbell_texture() -> ImageTexture:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var filled := (x < 24 and y >= 4 and y < 28) or (x >= 40 and y >= 4 and y < 28) or (x >= 24 and x < 40 and y >= 14 and y < 18)
			if filled:
				img.set_pixel(x, y, Color(0.6, 0.4, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

func spawn(texture: Texture2D, position: Vector2, dynamic := true) -> RegolithSprite:
	var sprite := RegolithSprite.new()
	sprite.texture = texture
	sprite.dynamic = dynamic
	sprite.position = position
	add_child_autofree(sprite)
	return sprite

func spawn_pair(dynamic_a := true) -> Array:
	var a := spawn(block_texture(Vector2i(16, 16)), Vector2(200, 150), dynamic_a)
	var b := spawn(block_texture(Vector2i(16, 16)), Vector2(200 + 16 * cell_px, 150))
	return [a, b, Vector2(200 + 8 * cell_px, 150)]

func anchor_gap(id: int) -> float:
	var anchors := world.get_joint_anchors(id)
	assert_eq(anchors.size(), 2, "joint %d is alive" % id)
	return anchors[0].distance_to(anchors[1]) if anchors.size() == 2 else INF

func test_pinned_sprites_stay_at_shared_point() -> void:
	var pair := spawn_pair()
	await wait_physics_frames(2)

	var id: int = world.add_joint(pair[0], pair[1], pair[2])
	assert_gt(id, 0)
	assert_eq(world.get_joint_count(), 1)
	assert_eq(world.get_joint_type(id), RegolithWorld.JOINT_PIN)

	var b_start: Vector2 = pair[1].global_position
	pair[0].linear_velocity = Vector2(0, 1)
	await wait_physics_frames(60)

	assert_lt(anchor_gap(id), cell_px, "anchors stay within a cell")
	assert_gt(pair[1].global_position.distance_to(b_start), 10.0, "the pin drags the other sprite along")

func test_pin_to_static_holds_dynamic() -> void:
	var pair := spawn_pair(false)
	await wait_physics_frames(2)

	var id: int = world.add_joint(pair[0], pair[1], pair[2])
	var pin: Vector2 = pair[2]
	var a_start: Vector2 = pair[0].global_position

	pair[1].linear_velocity = Vector2(3, 0)
	await wait_physics_frames(60)

	assert_eq(pair[0].global_position, a_start, "static sprite never moves")
	assert_lt(world.get_joint_anchors(id)[1].distance_to(pin), cell_px, "dynamic anchor stays on the pin")
	assert_almost_eq(pair[1].global_position.distance_to(pin), 8 * cell_px, cell_px, "dynamic sprite swings around the pin instead of flying off")

func test_distance_joint_keeps_anchors_within_rest() -> void:
	var a := spawn(block_texture(Vector2i(16, 16)), Vector2(200, 150))
	var b := spawn(block_texture(Vector2i(16, 16)), Vector2(200 + 24 * cell_px, 150))
	await wait_physics_frames(2)

	var point_a := Vector2(200 + 8 * cell_px, 150)
	var point_b := Vector2(200 + 16 * cell_px, 150)
	var id: int = world.add_distance_joint(a, b, point_a, point_b)
	assert_gt(id, 0)
	assert_eq(world.get_joint_type(id), RegolithWorld.JOINT_DISTANCE)
	assert_almost_eq(anchor_gap(id), 8 * cell_px, 0.01)

	b.linear_velocity = Vector2(3, 0)
	await wait_physics_frames(60)

	assert_lt(anchor_gap(id), 8 * cell_px + cell_px, "the rope length holds")
	assert_gt(a.global_position.x, 210.0, "a gets pulled along")

func test_freed_sprite_drops_joint() -> void:
	var a := spawn(block_texture(Vector2i(16, 16)), Vector2(200, 150))
	var b := RegolithSprite.new()
	b.texture = block_texture(Vector2i(16, 16))
	b.position = Vector2(200 + 16 * cell_px, 150)
	add_child(b)
	await wait_physics_frames(2)

	var id: int = world.add_joint(a, b, Vector2(200 + 8 * cell_px, 150))
	assert_eq(world.get_joint_count(), 1)
	assert_eq(world.get_joint_sprites(id).size(), 2)

	b.free()
	await wait_physics_frames(1)

	assert_eq(world.get_joint_count(), 0)
	assert_eq(world.get_joint_sprites(id).size(), 0)
	assert_eq(world.get_joint_anchors(id).size(), 0)

func test_joint_follows_split_piece() -> void:
	var dumbbell := spawn(dumbbell_texture(), Vector2(200, 150))
	var block := spawn(block_texture(Vector2i(16, 16)), Vector2(200 + 42 * cell_px, 150))
	await wait_physics_frames(2)

	var pin := Vector2(200 + 33 * cell_px, 150)
	var id: int = world.add_joint(dumbbell, block, pin)
	assert_gt(id, 0)

	for y in range(14, 18):
		dumbbell.remove_cell(Vector2i(32, y))
	await wait_physics_frames(2)

	assert_eq(world.get_sprite_count(), 3)
	assert_eq(world.get_joint_count(), 1, "the joint survives the split")

	var sprites := world.get_joint_sprites(id)
	assert_eq(sprites.size(), 2)
	var holder: RegolithSprite = sprites[0]
	var anchor: Vector2 = world.get_joint_anchors(id)[0]
	assert_true(holder.has_cell(holder.world_to_cell(anchor - Vector2(1.5 * cell_px, 0))), "the anchor hangs off a cell of the sprite it is joined to")
	assert_lt(anchor_gap(id), cell_px, "the anchors still meet after the move")
	assert_lt(anchor.distance_to(pin), 3.0 * cell_px, "the anchor stayed near the pin")

	var holder_start: Vector2 = holder.global_position
	block.linear_velocity = Vector2(0, 0.5)
	await wait_physics_frames(60)

	assert_lt(anchor_gap(id), cell_px, "the piece and block stay pinned")
	assert_gt(holder.global_position.distance_to(holder_start), 5.0, "the lobe holding the pin followed the block")

func test_joint_with_destroyed_anchor_drops() -> void:
	var pair := spawn_pair()
	await wait_physics_frames(2)

	var b: RegolithSprite = pair[1]
	var pin := b.cell_to_world(Vector2i(2, 8))
	var id: int = world.add_joint(pair[0], b, pin)
	assert_eq(world.get_joint_count(), 1)

	for y in 16:
		b.remove_cell(Vector2i(8, y))
	await wait_physics_frames(2)

	assert_eq(world.get_joint_count(), 1, "the joint moved to the half holding the anchor")
	var holder: RegolithSprite = world.get_joint_sprites(id)[1]
	var anchor: Vector2 = world.get_joint_anchors(id)[1]
	assert_true(holder.has_cell(holder.world_to_cell(anchor)))
	assert_lt(anchor.distance_to(pin), cell_px)

	for y in 16:
		for x in range(0, 8):
			holder.remove_cell(Vector2i(x, y))
	await wait_physics_frames(2)

	assert_eq(world.get_joint_count(), 0, "no cells left to hold the anchor")
