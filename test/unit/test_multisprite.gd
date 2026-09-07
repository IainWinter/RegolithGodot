extends GutTest

# the snake multisprite: seven chunk segments chained by distance joints,
# spawned by a MultiSprite node from art/multisprites/snake.json

const SNAKE := "res://game/images/multisprites/snake.json"

var world: RegolithWorld
var multi: MultiSprite

func before_each() -> void:
	world = RegolithWorld.new()
	world.gravity = Vector2.ZERO
	world.pixels_per_cell = 3
	add_child_autofree(world)
	world.sprite_split.connect(func(_source, piece): autofree(piece))

	multi = MultiSprite.new()
	multi.file = SNAKE
	multi.position = Vector2(600, 300)
	add_child_autofree(multi)
	await wait_physics_frames(2)

func chain() -> Array:
	return [6, 0, 1, 2, 3, 4, 5].map(func(i): return multi.sprites[i])

func test_snake_json_loads() -> void:
	var data := MultiSprite.read_file(SNAKE)
	assert_eq(data["sprites"].size(), 7)
	assert_eq(data["joints"].size(), 12)

	assert_eq(multi.sprites.size(), 7)
	assert_eq(multi.joints.size(), 12)
	assert_eq(world.get_sprite_count(), 7)
	assert_eq(world.get_joint_count(), 12)
	assert_eq(multi.head, multi.sprites[5])
	assert_not_null(multi.snake_head)
	assert_eq(multi.snake_head.get_parent(), multi.head)

	for sprite in multi.sprites:
		assert_true(sprite.is_loaded())
		assert_true(sprite.is_dynamic())
		assert_true(sprite.is_in_group("regolith"))
		assert_eq(sprite.get_cell_count(), Vector2i(32, 32))
		assert_eq(sprite.count_cells_of_type(RegolithSprite.CELL_JOINT1), 36)

	assert_almost_eq(multi.sprites[2].global_position, Vector2(600, 300) + Vector2(0.09409, 0.03609) * RegolithWorld.pixels_per_unit(), Vector2(0.5, 0.5))

func test_joints_are_distance_joints_on_joint_cells() -> void:
	for id in multi.joints:
		assert_eq(world.get_joint_type(id), RegolithWorld.JOINT_DISTANCE)

		var sprites := world.get_joint_sprites(id)
		var anchors := world.get_joint_anchors(id)
		assert_eq(sprites.size(), 2)
		assert_eq(anchors.size(), 2)

		for i in 2:
			var sprite: RegolithSprite = sprites[i]
			var type: int = sprite.get_cell_type(sprite.world_to_cell(anchors[i]))
			assert_between(type, RegolithSprite.CELL_JOINT1, RegolithSprite.CELL_JOINT4, "anchor %d of joint %d sits on a joint cell" % [i, id])

func test_segments_stay_jointed_after_moving() -> void:
	var ppu := RegolithWorld.pixels_per_unit()
	var rests := {}
	for id in multi.joints:
		var anchors := world.get_joint_anchors(id)
		rests[id] = anchors[0].distance_to(anchors[1])

	multi.head.linear_velocity = Vector2(4.0, 3.0)
	await wait_physics_frames(60)

	assert_gt(multi.head.global_position.distance_to(Vector2(600, 300) + Vector2(3.85021, 0.2371) * ppu), 1.0 * ppu, "the head moved")
	assert_eq(world.get_joint_count(), 12)

	var cell_px := ppu / RegolithWorld.CELLS_PER_CHUNK
	for id in multi.joints:
		var anchors := world.get_joint_anchors(id)
		assert_eq(anchors.size(), 2)
		assert_lt(anchors[0].distance_to(anchors[1]), rests[id] + 2.0 * cell_px, "joint %d holds its rest distance" % id)

	var segments := chain()
	for i in segments.size() - 1:
		var gap: float = segments[i].global_position.distance_to(segments[i + 1].global_position)
		assert_lt(gap, 1.6 * ppu, "segment %d follows its neighbour" % i)

	assert_gt(segments[0].linear_velocity.length(), 0.1, "the tail was dragged along")

func test_editor_loads_and_saves_snake() -> void:
	var root := Node2D.new()
	add_child_autofree(root)

	var editor := MultiSpriteEditor.new()
	editor.world = world
	root.add_child(editor)

	editor.load_from(SNAKE)
	assert_eq(editor.sprites.size(), 7)
	assert_eq(editor.joints.size(), 12)
	assert_eq(editor.head, 5)

	for id in editor.joints:
		assert_eq(world.get_joint_type(id), RegolithWorld.JOINT_DISTANCE)

	for sprite in editor.sprites:
		assert_false(sprite.is_dynamic(), "arranged while static")
		assert_eq(sprite.get_cell_count(), Vector2i(32, 32))

	var saved := "user://snake_roundtrip.json"
	editor.save_to(saved)
	var data := MultiSprite.read_file(saved)
	assert_eq(data["sprites"].size(), 7)
	assert_eq(data["joints"].size(), 12)
	assert_eq(int(data["head"]), 5)
	assert_eq(data["joints"][0]["type"], "distance")
	assert_true(data["joints"][0].has("point_b"))
	assert_almost_eq(float(data["joints"][0]["distance"]), float(MultiSprite.read_file(SNAKE)["joints"][0]["distance"]), 0.01)
	assert_eq(data["sprites"][0]["mask"], "res://game/images/multisprites/snake_chunk_mask.png")

	editor.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved))
