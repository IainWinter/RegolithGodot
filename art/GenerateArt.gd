extends SceneTree

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	var rock := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(96):
			var p := Vector2(x - 48, y - 32) / Vector2(46, 30)
			var edge := p.length() + rng.randf_range(-0.08, 0.08)
			if edge < 1.0:
				var shade := rng.randf_range(0.75, 1.0)
				rock.set_pixel(x, y, Color(0.55 * shade, 0.45 * shade, 0.38 * shade, 1.0))
	rock.save_png("res://art/sprites/rock.png")

	var slab := Image.create(160, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(160):
			var shade := rng.randf_range(0.8, 1.0)
			var band := 0.9 if (y / 8) % 2 == 0 else 1.0
			slab.set_pixel(x, y, Color(0.35 * shade * band, 0.4 * shade * band, 0.45 * shade * band, 1.0))
	slab.save_png("res://art/sprites/slab.png")

	print("art written")
	quit()
