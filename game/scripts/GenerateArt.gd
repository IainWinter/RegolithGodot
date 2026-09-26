extends SceneTree

# writes the generated sprite art under res://game/images/sprites: the
# sample rock and slab, and the gun parts from GunArt (mount and barrel
# color + mask pairs, the gun at 32 cells across, the turret at 96). run
# headless: godot --headless --path . -s game/scripts/GenerateArt.gd

const SPRITES_DIR := "res://game/images/sprites"
const GUN_ART := preload("res://game/scripts/enemies/GunArt.gd")
const GUN_CELLS := 32
const TURRET_CELLS := 96

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
	rock.save_png(SPRITES_DIR + "/rock.png")

	var slab := Image.create(160, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(160):
			var shade := rng.randf_range(0.8, 1.0)
			var band := 0.9 if (y / 8) % 2 == 0 else 1.0
			slab.set_pixel(x, y, Color(0.35 * shade * band, 0.4 * shade * band, 0.45 * shade * band, 1.0))
	slab.save_png(SPRITES_DIR + "/slab.png")

	write_gun("gun", GUN_CELLS)
	write_gun("turret", TURRET_CELLS)

	print("art written")
	quit()

func write_gun(prefix: String, cells: int) -> void:
	GUN_ART.write_pair(GUN_ART.mount(cells), SPRITES_DIR, prefix + "_mount")
	GUN_ART.write_pair(GUN_ART.barrel(cells), SPRITES_DIR, prefix + "_barrel")
