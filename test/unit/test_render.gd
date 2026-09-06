extends GutTest

# atlas upload: a flat colored sprite lands in atlas page 0 with its color.
# needs a real renderer, pending when headless

const SPRITE_MATERIAL := preload("res://shaders/regolith_sprite_material.tres")
const ROPE_MATERIAL := preload("res://shaders/regolith_rope_material.tres")

var world: RegolithWorld
var sprite: RegolithSprite

func before_each() -> void:
	world = RegolithWorld.new()
	world.pixels_per_cell = 3
	add_child_autofree(world)

	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.3, 0.2, 1.0))
	sprite = RegolithSprite.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.material = SPRITE_MATERIAL
	sprite.dynamic = false
	sprite.position = Vector2(240, 160)
	add_child_autofree(sprite)
	await wait_physics_frames(4)

func test_sprite_loads_all_cells() -> void:
	assert_eq(sprite.get_active_cell_count(), 64 * 32)
	assert_not_null(world.get_color_atlas())
	assert_not_null(world.get_mask_atlas())

func test_atlas_page_holds_sprite_color() -> void:
	if DisplayServer.get_name() == "headless":
		pending("atlas readback needs a renderer, run from the editor")
		return

	var atlas: Texture2DArray = world.get_color_atlas()
	var layer := atlas.get_layer_data(0)
	assert_eq(layer.get_size(), Vector2i(RegolithWorld.ATLAS_PAGE_SIZE, RegolithWorld.ATLAS_PAGE_SIZE))
	var px := layer.get_pixel(40, 20)
	assert_between(px.r8, 228, 231, "sprite red lands in the atlas")
	assert_between(px.g8, 75, 78, "green")
	assert_between(px.b8, 50, 52, "blue")
	assert_eq(px.a8, 255)

	var mask: Image = world.get_mask_atlas().get_layer_data(0)
	assert_ne(mask.get_pixel(40, 20).a, 0.0, "mask atlas has the cell")

# ropes draw from a canvas item whose rect the shader would otherwise leave
# at the sprite origin. with the origin far off screen the rope's tip must
# still show

func test_rope_draws_with_sprite_origin_off_screen() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a renderer, run from the editor")
		return

	var color := Image.create(160, 48, false, Image.FORMAT_RGBA8)
	var mask := Image.create(160, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 160:
			if x < 8:
				color.set_pixel(x, y, Color(0.5, 0.5, 0.55, 1.0))
				mask.set_pixel(x, y, Color8(0, 100, 255, 255))
			elif y == 16:
				color.set_pixel(x, y, Color(0.9, 0.7, 0.2, 1.0))
				mask.set_pixel(x, y, Color8(250, 0, 255, 255))

	var rope_wall := RegolithSprite.new()
	rope_wall.texture = ImageTexture.create_from_image(color)
	rope_wall.mask_texture = ImageTexture.create_from_image(mask)
	rope_wall.material = SPRITE_MATERIAL
	rope_wall.rope_material = ROPE_MATERIAL
	rope_wall.dynamic = false
	# 480 px wide, origin at x = -180 so only the rope's last stretch is in view
	rope_wall.position = Vector2(-180, 300)
	add_child_autofree(rope_wall)

	for i in 5:
		await wait_physics_frames(1)
		await wait_process_frames(1)

	assert_not_null(rope_wall.get_node_or_null("RopeRender"), "ropes draw from a child of their own")

	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	var orange := 0
	for y in shot.get_height():
		for x in shot.get_width():
			var c := shot.get_pixel(x, y)
			if c.r > 0.7 and c.g > 0.5 and c.b < 0.4:
				orange += 1

	assert_gt(orange, 20, "rope tip drawn with the origin off screen")
