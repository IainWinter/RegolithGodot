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
	var editor := MultiSpriteEditor.new()
	add_child_autofree(editor)
	await get_tree().process_frame

	assert_true(editor.load_from(SNAKE))
	assert_eq(editor.filename, "snake")
	assert_eq(editor.doc.sprites.size(), 7)
	assert_eq(editor.doc.joints.size(), 12)
	assert_eq(editor.doc.head, 5)

	for joint in editor.doc.joints:
		assert_eq(joint["type"], "distance")
		assert_gt(float(joint["distance"]), 0.0)

	for i in editor.doc.sprites.size():
		assert_eq(editor.doc.size_cells(i), Vector2i(32, 32))
		assert_eq(editor.doc.padded_cells(i), Vector2i(32, 32))
		assert_true(editor.doc.sprites[i]["dynamic"])

	# the document knows which sprite sits under a point, like the world would
	var origin: Vector2 = editor.doc.transform_of(2).origin
	assert_eq(editor.doc.sprite_at(origin), 2, "the chunk's center cell belongs to sprite 2")
	assert_eq(editor.doc.sprite_at(origin + Vector2(0, 500)), -1, "nothing far away")

	var saved := "user://snake_roundtrip.json"
	assert_true(editor.save_to(saved))
	var data := MultiSprite.read_file(saved)
	assert_eq(data["sprites"].size(), 7)
	assert_eq(data["joints"].size(), 12)
	assert_eq(int(data["head"]), 5)
	assert_eq(data["joints"][0]["type"], "distance")
	assert_true(data["joints"][0].has("point_b"))
	assert_almost_eq(float(data["joints"][0]["distance"]), float(MultiSprite.read_file(SNAKE)["joints"][0]["distance"]), 0.01)
	assert_eq(data["sprites"][0]["mask"], "res://game/images/multisprites/snake_chunk_mask.png")
	assert_almost_eq(float(data["sprites"][2]["position"][0]), 0.09409, 0.0001)

	editor.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved))

func test_editor_edits_document() -> void:
	var editor := MultiSpriteEditor.new()
	add_child_autofree(editor)
	await get_tree().process_frame

	var a := editor.add_sprite("res://game/images/multisprites/snake_chunk.png", Vector2.ZERO)
	var b := editor.place_new_sprite("res://game/images/multisprites/snake_chunk.png")
	assert_eq([a, b], [0, 1])
	assert_eq(editor.doc.sprites[1]["position"], Vector2(1, 0), "the second lands one chunk to the right")
	assert_eq(editor.add_sprite("res://game/images/multisprites/missing.png"), -1)

	editor.set_mode(MultiSpriteEditor.Mode.JOINT)
	editor.on_pressed(Vector2.ZERO, MOUSE_BUTTON_LEFT)
	assert_eq(editor.joint_first, 0)
	editor.on_pressed(Vector2(16, 0), MOUSE_BUTTON_LEFT)
	assert_eq(editor.joint_first, -1)
	assert_eq(editor.doc.joints.size(), 1)
	assert_eq(editor.doc.joints[0]["a"], 0)
	assert_eq(editor.doc.joints[0]["b"], 1)
	assert_eq(editor.doc.joints[0]["point"], Vector2(0.5, 0))

	editor.set_mode(MultiSpriteEditor.Mode.MOVE)
	editor.on_pressed(Vector2(32, 0), MOUSE_BUTTON_LEFT)
	assert_eq(editor.selected, 1)
	editor.on_dragged(Vector2(64, 0))
	editor.on_released(Vector2(64, 0), MOUSE_BUTTON_LEFT)
	assert_eq(editor.doc.sprites[1]["position"], Vector2(2, 0))
	editor.rotate_selected(2)
	assert_almost_eq(float(editor.doc.sprites[1]["rotation"]), PI / 8.0, 0.0001)

	editor.doc.set_head(1)
	editor.remove_selected()
	assert_eq(editor.doc.sprites.size(), 1)
	assert_eq(editor.doc.joints.size(), 0, "joints on the removed sprite go with it")
	assert_eq(editor.doc.head, -1)

func test_editor_window_plays_document_in_world() -> void:
	var root := Node2D.new()
	add_child_autofree(root)

	var window := MultiSpriteEditorWindow.new()
	root.add_child(window)
	await get_tree().process_frame

	assert_true(window.editor.load_from(SNAKE))
	assert_false(window.playing())

	var before := world.get_sprite_count()
	window.toggle_play()
	await wait_physics_frames(2)
	assert_true(window.playing())
	assert_eq(world.get_sprite_count(), before + 7, "play spawns the layout into the live world")
	assert_eq(world.get_joint_count(), 24)
	assert_eq(window.preview.sprites.size(), 7)
	for sprite in window.preview.sprites:
		assert_true(sprite.is_dynamic())

	window.toggle_play()
	await wait_physics_frames(2)
	assert_false(window.playing())
	assert_eq(world.get_sprite_count(), before)
	assert_eq(world.get_joint_count(), 12)

	window.close()
	await get_tree().process_frame

# the gun and turret documents: a mount and a barrel on a pin that does
# not collide connected, the barrel reaching past the ring
func test_gun_documents_load_in_the_editor_document() -> void:
	for entry in [["gun", 32], ["turret", 96]]:
		var path := "res://game/images/multisprites/%s.json" % entry[0]
		var size: int = entry[1]
		var doc := MultiSpriteDocument.new()
		assert_true(doc.load_from(path), "%s opens" % path)
		assert_eq(doc.sprites.size(), 2)
		assert_eq(doc.sprites[0]["name"], "mount")
		assert_eq(doc.sprites[1]["name"], "barrel")
		assert_eq(doc.size_cells(0), Vector2i(size, size), "the mount art")
		assert_gt(doc.size_cells(1).x, size, "the barrel art is longer than the mount is wide")
		assert_eq(doc.joints.size(), 1)
		assert_eq(doc.joints[0]["type"], "pin")
		assert_eq(doc.joints[0]["collide"], false, "the parts do not collide with each other")

		# the barrel's art reaches past the ring: its far end in document
		# cells against the ring's outer radius around the pivot
		var pivot := doc.units_to_cells(doc.joints[0]["point"])
		var far: Vector2 = doc.transform_of(1) * (doc.art_offset(1) + Vector2(doc.size_cells(1).x, doc.size_cells(1).y * 0.5))
		assert_gt(far.distance_to(pivot), GunArt.layout(size)["ring_outer"] + 0.2 * size, "the tube sticks out well past the ring")
		assert_true(doc.has_cell(1, doc.local_cell(1, pivot)), "the barrel's hub sits on the pivot")

		var data := doc.to_data()
		assert_eq(int(data["root"]), 0, "top level keys ride along a save")
		assert_eq(data["muzzle"].size(), 2)
		assert_eq(data["joints"][0]["collide"], false)
		assert_eq(data["sprites"][1]["name"], "barrel")

# a pin between two overlapping sprites: collide false lets them rest,
# the default keeps contacts between them as before
func test_collide_connected_false_lets_overlapping_parts_rest() -> void:
	var drift := {}
	var contacts := {}

	for collide in [false, true]:
		var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		image.fill(Color.GRAY)
		var a := RegolithSprite.new()
		var b := RegolithSprite.new()
		a.position = Vector2(200, 600)
		b.position = Vector2(200 + 8 * 3, 600)
		add_child_autofree(a)
		add_child_autofree(b)
		a.load_from_images(image)
		b.load_from_images(image)

		var start_a := a.get_center_of_mass()
		var start_b := b.get_center_of_mass()
		var id := world.add_joint(a, b, (start_a + start_b) * 0.5, collide)
		assert_eq(world.get_joint_collide_connected(id), collide)
		contacts[collide] = 0

		for i in 60:
			await wait_physics_frames(1)
			contacts[collide] = maxi(contacts[collide], world.get_contact_count())

		drift[collide] = maxf(a.get_center_of_mass().distance_to(start_a), b.get_center_of_mass().distance_to(start_b))
		world.remove_joint(id)
		a.free()
		b.free()

	assert_eq(contacts[false], 0, "no contacts between them")
	assert_lt(drift[false], 3.0, "nothing moves")
	assert_gt(contacts[true], 0, "colliding connected keeps the contacts as before")

func test_editor_opens_the_gun_document() -> void:
	var editor := MultiSpriteEditor.new()
	add_child_autofree(editor)
	await get_tree().process_frame

	assert_true(editor.load_from("res://game/images/multisprites/turret.json"))
	assert_eq(editor.doc.sprites.size(), 2)
	assert_eq(editor.doc.joints[0]["collide"], false)
	editor.close()
