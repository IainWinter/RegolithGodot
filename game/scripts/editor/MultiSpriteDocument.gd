@tool
extends RefCounted
class_name MultiSpriteDocument

# the data behind MultiSpriteEditor: the json a MultiSprite node spawns from,
# held as plain dictionaries so the editor works without a RegolithWorld (the
# Godot editor never starts one). sprites carry texture, optional mask, position
# in sim units, rotation and dynamic; joints a, b, type (pin or distance with
# point_b and distance), point in units and collide (false when the two
# must not touch); head names the sprite that gets a SnakeHead. a sprite
# may carry a name (an EnemyGun finds its mount and barrel by it) and any
# other top level key (root, muzzle) rides along untouched. geometry follows RegolithSprite: the node origin is the center of
# the chunk padded grid and the art sits at the grid's top left, so cell space
# here is what the world shows at one pixel per cell

const UNIT_CELLS := RegolithWorld.CELLS_PER_CHUNK

var sprites: Array[Dictionary] = []
var joints: Array[Dictionary] = []
var head := -1
# top level keys this editor does not edit, written back as they came
var extras := {}

# texture path to Image, null when the file could not be read
var images := {}

signal changed

func touch() -> void:
	changed.emit()

func clear() -> void:
	sprites.clear()
	joints.clear()
	head = -1
	extras = {}
	touch()

# files

static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

# res:// pngs go through the importer so the editor and the game agree, other
# paths are read straight from disk
static func load_image(path: String) -> Image:
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		var texture := load(path) as Texture2D
		return texture.get_image() if texture else null

	var on_disk := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	return Image.load_from_file(on_disk) if FileAccess.file_exists(on_disk) else null

static func mask_path_for(entry: Dictionary) -> String:
	if entry.has("mask"):
		return entry["mask"]

	var guess: String = entry["texture"].get_basename() + "_mask.png"
	return guess if ResourceLoader.exists(guess) or FileAccess.file_exists(guess) else ""

static func to_pair(v: Vector2) -> Array:
	return [snappedf(v.x, 0.00001), snappedf(v.y, 0.00001)]

static func from_pair(value, fallback := Vector2.ZERO) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback

func from_data(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	sprites.clear()
	joints.clear()
	head = -1
	extras = {}

	for key in data:
		if not key in ["sprites", "joints", "head"]:
			extras[key] = data[key]

	for entry in data.get("sprites", []):
		if not (entry is Dictionary) or not entry.has("texture"):
			continue
		var sprite := {
			"texture": String(entry["texture"]),
			"position": from_pair(entry.get("position")),
			"rotation": float(entry.get("rotation", 0.0)),
			"dynamic": bool(entry.get("dynamic", true)),
		}
		if entry.has("mask"):
			sprite["mask"] = String(entry["mask"])
		if entry.has("name"):
			sprite["name"] = String(entry["name"])
		sprites.append(sprite)

	for entry in data.get("joints", []):
		if not (entry is Dictionary):
			continue
		var a := int(entry.get("a", -1))
		var b := int(entry.get("b", -1))
		if a < 0 or b < 0 or a >= sprites.size() or b >= sprites.size():
			continue
		var point := from_pair(entry.get("point"))
		var joint := {
			"a": a,
			"b": b,
			"type": String(entry.get("type", "pin")),
			"point": point,
			"point_b": from_pair(entry.get("point_b"), point),
			"distance": float(entry.get("distance", -1.0)),
		}
		if entry.has("collide"):
			joint["collide"] = bool(entry["collide"])
		joints.append(joint)

	var h := int(data.get("head", -1))
	head = h if h >= 0 and h < sprites.size() else -1

	touch()
	return true

func to_data() -> Dictionary:
	var data := extras.duplicate(true)
	data["sprites"] = []
	data["joints"] = []

	for sprite in sprites:
		var entry := {
			"texture": sprite["texture"],
			"position": to_pair(sprite["position"]),
			"rotation": snappedf(sprite["rotation"], 0.00001),
			"dynamic": sprite["dynamic"],
		}
		if sprite.has("mask"):
			entry["mask"] = sprite["mask"]
		if sprite.has("name"):
			entry["name"] = sprite["name"]
		data["sprites"].append(entry)

	for joint in joints:
		var entry := {
			"a": joint["a"],
			"b": joint["b"],
			"point": to_pair(joint["point"]),
			"type": joint["type"],
		}
		if joint["type"] == "distance":
			entry["point_b"] = to_pair(joint["point_b"])
			entry["distance"] = snappedf(joint["distance"], 0.00001)
		if joint.has("collide"):
			entry["collide"] = joint["collide"]
		data["joints"].append(entry)

	if head >= 0 and head < sprites.size():
		data["head"] = head

	return data

func load_from(path: String) -> bool:
	return from_data(read_file(path))

func save_to(path: String) -> bool:
	var on_disk := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var file := FileAccess.open(on_disk, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(to_data(), "  "))
	file.close()
	return true

# sprites

func add_sprite(texture: String, position := Vector2.ZERO, rotation := 0.0, extra := {}) -> int:
	if image_for(texture) == null:
		return -1

	var sprite := {
		"texture": texture,
		"position": position,
		"rotation": rotation,
		"dynamic": bool(extra.get("dynamic", true)),
	}
	if extra.has("mask"):
		sprite["mask"] = String(extra["mask"])

	sprites.append(sprite)
	touch()
	return sprites.size() - 1

# drops a sprite, the joints on it and renumbers the rest
func remove_sprite(i: int) -> void:
	if i < 0 or i >= sprites.size():
		return

	sprites.remove_at(i)

	for j in range(joints.size() - 1, -1, -1):
		var joint := joints[j]
		if joint["a"] == i or joint["b"] == i:
			joints.remove_at(j)
			continue
		if joint["a"] > i:
			joint["a"] -= 1
		if joint["b"] > i:
			joint["b"] -= 1

	if head == i:
		head = -1
	elif head > i:
		head -= 1

	touch()

func remove_last() -> void:
	remove_sprite(sprites.size() - 1)

func add_pin_joint(a: int, b: int, point: Vector2) -> int:
	if a < 0 or b < 0 or a >= sprites.size() or b >= sprites.size() or a == b:
		return -1

	joints.append({"a": a, "b": b, "type": "pin", "point": point, "point_b": point, "distance": -1.0})
	touch()
	return joints.size() - 1

func add_distance_joint(a: int, b: int, point_a: Vector2, point_b: Vector2) -> int:
	if a < 0 or b < 0 or a >= sprites.size() or b >= sprites.size() or a == b:
		return -1

	joints.append({"a": a, "b": b, "type": "distance", "point": point_a, "point_b": point_b, "distance": point_a.distance_to(point_b)})
	touch()
	return joints.size() - 1

func clear_joints() -> void:
	joints.clear()
	touch()

func set_head(i: int) -> void:
	head = i if i >= 0 and i < sprites.size() else -1
	touch()

# geometry, in cells

func image_for(texture: String) -> Image:
	if not images.has(texture):
		images[texture] = load_image(texture)
	return images[texture]

func image_of(i: int) -> Image:
	return image_for(sprites[i]["texture"])

func mask_image_of(i: int) -> Image:
	var path := mask_path_for(sprites[i])
	return image_for(path) if path != "" else null

func size_cells(i: int) -> Vector2i:
	var image := image_of(i)
	return Vector2i(image.get_width(), image.get_height()) if image else Vector2i.ZERO

# the chunk padded grid the world builds around the art
func padded_cells(i: int) -> Vector2i:
	var size := size_cells(i)
	return Vector2i(ceili(size.x / float(UNIT_CELLS)) * UNIT_CELLS, ceili(size.y / float(UNIT_CELLS)) * UNIT_CELLS)

# where the art's top left sits relative to the node origin
func art_offset(i: int) -> Vector2:
	return -Vector2(padded_cells(i)) * 0.5

func transform_of(i: int) -> Transform2D:
	return Transform2D(sprites[i]["rotation"], sprites[i]["position"] * UNIT_CELLS)

func cells_to_units(point: Vector2) -> Vector2:
	return point / UNIT_CELLS

func units_to_cells(point: Vector2) -> Vector2:
	return point * UNIT_CELLS

# the art cell under a point in cell space, (-1, -1) outside the art
func local_cell(i: int, point: Vector2) -> Vector2i:
	var local := transform_of(i).affine_inverse() * point - art_offset(i)
	var cell := Vector2i(floori(local.x), floori(local.y))
	var size := size_cells(i)
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return Vector2i(-1, -1)
	return cell

# a cell the world would build: mask pixel when there is a mask, else color alpha
func has_cell(i: int, cell: Vector2i) -> bool:
	if cell.x < 0:
		return false

	var mask := mask_image_of(i)
	if mask and mask.get_width() == size_cells(i).x and mask.get_height() == size_cells(i).y:
		return mask.get_pixelv(cell).a > 0.0

	return image_of(i).get_pixelv(cell).a > 0.0

# the topmost sprite with a cell under the point, else the topmost whose art
# covers it, else -1
func sprite_at(point: Vector2) -> int:
	var fallback := -1

	for i in range(sprites.size() - 1, -1, -1):
		var cell := local_cell(i, point)
		if cell.x < 0:
			continue
		if has_cell(i, cell):
			return i
		if fallback < 0:
			fallback = i

	return fallback

# the art rectangles of every sprite in cell space, for fitting the view
func bounds() -> Rect2:
	var rect := Rect2()
	var first := true

	for i in sprites.size():
		var t := transform_of(i)
		var offset := art_offset(i)
		var size := Vector2(size_cells(i))
		for corner in [offset, offset + Vector2(size.x, 0), offset + size, offset + Vector2(0, size.y)]:
			var p: Vector2 = t * corner
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)

	return rect
