extends GutTest

# ropes in the real game scene: every sprite with ropes has its rope_material
# and draws from a RopeRender child whose multimesh holds one instance per
# segment, and the rope cells show up on screen where the rope points are.
# needs a renderer, pending when headless. screenshots land in user://

const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")
const ROPE_MATERIAL := preload("res://game/shaders/regolith_rope_material.tres")

var main: Node

func before_each() -> void:
	if DisplayServer.get_name() == "headless":
		return

	main = load("res://game/scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main

	for i in 10:
		await wait_physics_frames(1)
		await wait_process_frames(1)

func after_each() -> void:
	if main:
		get_tree().current_scene = null
		main.free()
		main = null

func rope_sprites() -> Array:
	var out := []
	for sprite in get_tree().get_nodes_in_group("regolith"):
		if sprite is RegolithSprite and sprite.get_rope_count() > 0:
			out.append(sprite)
	for sprite in main.get_children():
		if sprite is RegolithSprite and sprite.get_rope_count() > 0 and not out.has(sprite):
			out.append(sprite)
	return out

func segments_of(sprite: RegolithSprite) -> int:
	var total := 0
	for i in sprite.get_rope_count():
		total += maxi(sprite.get_rope_points(i).size() - 1, 0)
	return total

func extents_of(sprite: RegolithSprite) -> Rect2:
	var rect := Rect2()
	var first := true
	for i in sprite.get_rope_count():
		for p in sprite.get_rope_points(i):
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	return rect

# the runner's own panel covers the game, hide it while grabbing the frame

func screenshot(name: String) -> Image:
	var layer: CanvasLayer = get_tree().root.find_child("GutLayer", true, false)
	if layer:
		layer.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	if layer:
		layer.visible = true
	var path := "user://%s.png" % name
	shot.save_png(path)
	gut.p("screenshot %s (%dx%d) canvas %s" % [ProjectSettings.globalize_path(path), shot.get_width(), shot.get_height(), get_viewport().get_canvas_transform()])
	return shot

# screen pixels within radius of the rope points, each once

func pixels_near_ropes(shot: Image, sprite: RegolithSprite, radius: int) -> Array:
	var canvas := get_viewport().get_canvas_transform()
	var seen := {}
	var out := []

	for i in sprite.get_rope_count():
		for p in sprite.get_rope_points(i):
			var screen := canvas * p
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var key := Vector2i(int(screen.x) + dx, int(screen.y) + dy)
					if key.x < 0 or key.y < 0 or key.x >= shot.get_width() or key.y >= shot.get_height():
						continue
					if seen.has(key):
						continue
					seen[key] = true
					out.append(key)

	return out

func count_orange(shot: Image, points: Array) -> int:
	var count := 0
	for key in points:
		var c := shot.get_pixel(key.x, key.y)
		if c.a > 0.5 and c.r > 0.55 and c.g > 0.35 and c.b < 0.45 and c.r > c.b + 0.3:
			count += 1
	return count

# pixels that differ between two frames, ropes drawn in one and hidden in
# the other, whatever colour the sprite's rope cells have

func count_changed(before: Image, after: Image, points: Array) -> int:
	var count := 0
	for key in points:
		var a := before.get_pixel(key.x, key.y)
		var b := after.get_pixel(key.x, key.y)
		if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.2:
			count += 1
	return count

func report(sprite: RegolithSprite) -> Dictionary:
	var render: Node = sprite.get_node_or_null("RopeRender")
	var out := {
		"render": render,
		"segments": segments_of(sprite),
		"extents": extents_of(sprite),
		"instances": -1,
		"visible": false,
		"material": null,
	}

	if render:
		out["instances"] = render.get_instance_count()
		out["visible"] = render.is_visible_in_tree()
		out["material"] = render.material

	gut.p("%s at %s: ropes %d segments %d extents %s render %s visible %s material %s instances %d rope_material %s" % [
		sprite.name, sprite.global_position, sprite.get_rope_count(), out["segments"], out["extents"],
		render, out["visible"], out["material"], out["instances"], sprite.rope_material])

	return out

func test_ropes_draw_in_main_scene() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a renderer, run from the editor")
		return

	var sprites := rope_sprites()
	gut.p("sprites with ropes: %d" % sprites.size())
	assert_gt(sprites.size(), 0, "Main has at least one sprite with ropes")

	var shot := await screenshot("rope_render")

	for sprite in sprites:
		var info := report(sprite)
		var render: Node = info["render"]

		assert_not_null(sprite.rope_material, "%s has its rope material" % sprite.name)
		assert_not_null(render, "%s has a RopeRender child" % sprite.name)
		if render == null:
			continue

		assert_true(info["visible"], "%s RopeRender is visible" % sprite.name)
		assert_eq(render.material, sprite.rope_material, "%s RopeRender draws with the sprite's rope material" % sprite.name)
		assert_gte(info["instances"], info["segments"], "%s multimesh holds every segment" % sprite.name)

	# hiding the render node takes the rope cells off the screen right
	# where the rope points are

	for sprite in sprites:
		var render: Node = sprite.get_node_or_null("RopeRender")
		if render:
			render.visible = false

	var hidden := await screenshot("rope_render_hidden")

	for sprite in sprites:
		var render: Node = sprite.get_node_or_null("RopeRender")
		if render:
			render.visible = true

	for sprite in sprites:
		var points := pixels_near_ropes(shot, sprite, 3)
		var changed := count_changed(hidden, shot, points)
		gut.p("%s: %d of %d pixels near the rope points are rope" % [sprite.name, changed, points.size()])
		assert_gt(changed, 4 * segments_of(sprite), "%s rope cells drawn near the rope points" % sprite.name)

# a rope wall added to the running scene draws its rope in the rope colour,
# and a material set later reaches the existing render child

func test_rope_wall_draws_in_rope_colour() -> void:
	if DisplayServer.get_name() == "headless":
		pending("needs a renderer, run from the editor")
		return

	var color := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var mask := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 48:
			if x < 8:
				color.set_pixel(x, y, Color(0.5, 0.5, 0.55, 1.0))
				mask.set_pixel(x, y, Color8(0, 100, 255, 255))
			elif y == 16:
				color.set_pixel(x, y, Color(0.9, 0.7, 0.2, 1.0))
				mask.set_pixel(x, y, Color8(250, 0, 255, 255))

	var wall := RegolithSprite.new()
	wall.texture = ImageTexture.create_from_image(color)
	wall.mask_texture = ImageTexture.create_from_image(mask)
	wall.material = SPRITE_MATERIAL
	wall.rope_material = ROPE_MATERIAL
	wall.dynamic = false
	wall.position = Vector2(-300, -100)
	main.add_child(wall)
	autofree(wall)

	for i in 3:
		await wait_physics_frames(1)
		await wait_process_frames(1)

	assert_eq(wall.get_rope_count(), 1)
	var render: Node = wall.get_node_or_null("RopeRender")
	assert_not_null(render, "rope wall has a RopeRender child")
	if render == null:
		return

	assert_eq(render.material, ROPE_MATERIAL)
	assert_gte(render.get_instance_count(), 2, "segments drawn")

	var shot := await screenshot("rope_render_wall")
	var points := pixels_near_ropes(shot, wall, 3)
	var orange := count_orange(shot, points)
	gut.p("wall: %d of %d pixels near the rope points are orange" % [orange, points.size()])
	assert_gt(orange, 20, "orange rope cells drawn near the rope points")

	var swapped: ShaderMaterial = ROPE_MATERIAL.duplicate()
	wall.rope_material = swapped
	await wait_process_frames(2)
	assert_eq(render.material, swapped, "a new material reaches the existing child")
	assert_gte(render.get_instance_count(), 2, "still drawn")
