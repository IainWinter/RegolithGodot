extends GutTest

# editor preview: an unloaded sprite with a texture shows the texture flat at
# the world's cell size. the atlas material discards every pixel while no atlas
# is bound, so the preview must not draw through it. the editor never loads a
# sprite, and Engine.set_editor_hint is not scriptable, so the test reaches the
# same state in the game: a sprite that gets its texture after ready stays
# unloaded. needs a renderer, pending when headless

const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")
const PIXELS_PER_CELL := 2

# the gut gui covers the right half of the window, keep sprites on the left
const SPRITE_POSITION := Vector2(300, 200)
const LOADED_POSITION := Vector2(300, 450)

var world: RegolithWorld
var sprite: RegolithSprite

func before_each() -> void:
	world = RegolithWorld.new()
	world.pixels_per_cell = PIXELS_PER_CELL
	add_child_autofree(world)

	# no texture at ready, the sprite stays unloaded like in the editor
	sprite = RegolithSprite.new()
	sprite.material = SPRITE_MATERIAL
	sprite.position = SPRITE_POSITION
	add_child_autofree(sprite)
	await wait_process_frames(1)
	sprite.texture = load("res://game/images/sprites/rock.png")

func _skip_headless() -> bool:
	if DisplayServer.get_name() == "headless":
		pending("viewport readback needs a renderer, run from the editor")
		return true
	return false

func _preview_rect(scale: int) -> Rect2i:
	var size := Vector2i(sprite.texture.get_size()) * scale
	return Rect2i(Vector2i(SPRITE_POSITION) - size / 2, size)

func _shot() -> Image:
	await wait_process_frames(2)
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

# rock pixels are brown, red over green over blue
func _is_brown(c: Color) -> bool:
	return c.r > 0.3 and c.r > c.g + 0.03 and c.g > c.b + 0.03

func _count(shot: Image, rect: Rect2i, test: Callable) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if test.call(shot.get_pixel(x, y)):
				n += 1
	return n

func test_unloaded_sprite_shows_its_texture() -> void:
	if _skip_headless():
		return

	assert_false(sprite.is_loaded(), "texture set after ready does not load")

	var shot: Image = await _shot()
	var rect := _preview_rect(PIXELS_PER_CELL)
	var brown := _count(shot, rect, _is_brown)
	assert_gt(brown, rect.size.x * rect.size.y / 4, "rock texture drawn in the sprite's rect")

func test_preview_scales_by_world_pixels_per_cell() -> void:
	if _skip_headless():
		return

	var shot: Image = await _shot()
	var inner := _preview_rect(1)
	var outer := _preview_rect(PIXELS_PER_CELL)

	# the rock fills its image to the edges, so the band outside the unscaled
	# rect only holds brown when the preview is scaled up
	var band := _count(shot, outer, _is_brown) - _count(shot, inner, _is_brown)
	assert_gt(band, 500, "preview scaled by pixels_per_cell")

func test_preview_redraws_when_texture_changes() -> void:
	if _skip_headless():
		return

	var img := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.9, 0.1, 1.0))
	sprite.texture = ImageTexture.create_from_image(img)

	var shot: Image = await _shot()
	var rect := _preview_rect(PIXELS_PER_CELL)
	var green := _count(shot, rect, func(c: Color) -> bool: return c.g > 0.7 and c.r < 0.3)
	assert_gt(green, rect.size.x * rect.size.y * 3 / 4, "new texture drawn")
	assert_eq(_count(shot, rect, _is_brown), 0, "old texture gone")

func test_loaded_sprite_draws_through_the_atlas_not_the_preview() -> void:
	if _skip_headless():
		return

	# a sprite with its texture at ready loads, its preview must not overdraw
	# the atlas draw. a flat blue texture in the atlas shows blue
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.2, 0.9, 1.0))
	var loaded := RegolithSprite.new()
	loaded.texture = ImageTexture.create_from_image(img)
	loaded.material = SPRITE_MATERIAL
	loaded.dynamic = false
	loaded.position = LOADED_POSITION
	add_child_autofree(loaded)
	await wait_physics_frames(4)
	assert_true(loaded.is_loaded())

	var shot: Image = await _shot()
	var rect := Rect2i(Vector2i(LOADED_POSITION) - Vector2i(64, 32), Vector2i(128, 64))
	var blue := _count(shot, rect, func(c: Color) -> bool: return c.b > 0.7 and c.r < 0.3)
	assert_gt(blue, rect.size.x * rect.size.y / 2, "loaded sprite drawn from the atlas")
