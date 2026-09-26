extends SceneTree

# writes the placeholder character icons for the dialog window: each ship's
# color png out of game/images/sprites cropped to its opaque bounds, squared,
# and scaled nearest neighbor into a 32x32 png under game/images/characters.
# small ships scale up by a whole factor so their pixels stay crisp, big ones
# scale down (averaged, alpha snapped back to hard pixels). also prints the
# sprite's mean opaque color as a hint for the name color in the .tres
# files (the hulls are all grey so those were picked by hand). run once
# headless:
#   Godot_console.exe --headless --path . -s game/scripts/dialog/GenerateCharacterIcons.gd
# then --headless --import so the pngs get their .import files

const SIZE := 32
const OUT_DIR := "res://game/images/characters"
const SPRITE_DIR := "res://game/images/sprites"

# character id -> the sprite its face comes from
const SOURCES := {
	"fighter": "fighter.png",
	"bomb": "bomb.png",
	"base": "base.png",
	"station": "station.png",
	"boss_compass": "boss1.png",
	"boss_stingray": "boss1phase3.png",
	"player": "player.png",
}

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	for id in SOURCES:
		var source := Image.new()
		var path := "%s/%s" % [SPRITE_DIR, SOURCES[id]]

		if source.load(path) != OK:
			push_error("could not load %s" % path)
			continue

		var icon := make_icon(source)
		var out := "%s/%s.png" % [OUT_DIR, id]
		icon.save_png(out)
		print("%s <- %s  color %s" % [out, path, color_text(name_color(source))])

	print("icons written")
	quit()

static func make_icon(source: Image) -> Image:
	source.convert(Image.FORMAT_RGBA8)
	var bounds := source.get_used_rect()

	if bounds.size.x <= 0 or bounds.size.y <= 0:
		bounds = Rect2i(Vector2i.ZERO, source.get_size())

	var cropped := source.get_region(bounds)
	var side := maxi(cropped.get_width(), cropped.get_height())
	var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
	square.fill(Color.TRANSPARENT)
	square.blit_rect(cropped, Rect2i(Vector2i.ZERO, cropped.get_size()), (Vector2i(side, side) - cropped.get_size()) / 2)

	var icon := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	icon.fill(Color.TRANSPARENT)

	if side <= SIZE:
		# whole pixel scale up, centered
		var factor := maxi(1, SIZE / side)
		square.resize(side * factor, side * factor, Image.INTERPOLATE_NEAREST)
		icon.blit_rect(square, Rect2i(Vector2i.ZERO, square.get_size()), (Vector2i(SIZE, SIZE) - square.get_size()) / 2)
	else:
		# nearest on a 400 pixel hull keeps stray single pixels and drops the
		# mass, so average down then snap the alpha back to hard pixels
		square.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		for y in SIZE:
			for x in SIZE:
				var c := square.get_pixel(x, y)
				square.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0) if c.a > 0.3 else Color.TRANSPARENT)
		icon.blit_rect(square, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)

	return icon

# the mean of the opaque pixels, lifted so it reads as a name on the dark panel
static func name_color(source: Image) -> Color:
	var sum := Vector3.ZERO
	var count := 0

	for y in source.get_height():
		for x in source.get_width():
			var c := source.get_pixel(x, y)
			if c.a > 0.5:
				sum += Vector3(c.r, c.g, c.b)
				count += 1

	if count == 0:
		return Color.WHITE

	var mean := Color(sum.x / count, sum.y / count, sum.z / count)
	return Color.from_hsv(mean.h, clampf(mean.s, 0.45, 0.8), clampf(mean.v, 0.85, 1.0))

static func color_text(c: Color) -> String:
	return "Color(%.3f, %.3f, %.3f, 1)" % [c.r, c.g, c.b]
