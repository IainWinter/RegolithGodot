extends SceneTree

# writes the small and large item textures next to the medium one copied
# from the original (item_medium.png, 6x6) in the same grey so the props'
# tint colors them. run headless:
# godot --headless --path . -s game/scripts/items/GenerateItemArt.gd

const BASE := Color8(169, 169, 169)
const LIGHT := Color8(186, 186, 186)
const SHINE := Color8(209, 209, 209)

func _init() -> void:
	var small := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var small_rows := [
		".BB.",
		"BBLB",
		"BSLB",
		".BB.",
	]
	paint(small, small_rows)
	small.save_png("res://game/images/items/item_small.png")

	var large := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var large_rows := [
		"..BBBB..",
		".BBBBBB.",
		"BBBLSBBB",
		"BBLSSLBB",
		"BBBLSLBB",
		"BBBBLBBB",
		".BBBBBB.",
		"..BBBB..",
	]
	paint(large, large_rows)
	large.save_png("res://game/images/items/item_large.png")

	print("item art written")
	quit()

static func paint(image: Image, rows: Array) -> void:
	for y in rows.size():
		var row: String = rows[y]

		for x in row.length():
			match row[x]:
				"B":
					image.set_pixel(x, y, BASE)
				"L":
					image.set_pixel(x, y, LIGHT)
				"S":
					image.set_pixel(x, y, SHINE)
