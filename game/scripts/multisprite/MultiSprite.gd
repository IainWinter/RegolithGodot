extends Node2D
class_name MultiSprite

# a group of RegolithSprites laid out and jointed by a MultiSpriteEditor json,
# spawned as children so the whole thing drops into any scene. positions in
# the file are sim units around this node

@export_file("*.json") var file: String
@export var sprite_material: Material
@export var rope_material: Material

var sprites: Array[RegolithSprite] = []
var joints: Array[int] = []
var head: RegolithSprite
var snake_head: SnakeHead

func _ready() -> void:
	if file != "":
		spawn(file)

static func read_file(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

static func load_texture(path: String) -> Texture2D:
	if path.begins_with("res://"):
		return load(path) as Texture2D

	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image else null

static func load_image(path: String) -> Image:
	var texture := load_texture(path)
	return texture.get_image() if texture else null

static func mask_path_for(entry: Dictionary) -> String:
	if entry.has("mask"):
		return entry["mask"]

	var guess: String = entry["texture"].get_basename() + "_mask.png"
	return guess if ResourceLoader.exists(guess) or FileAccess.file_exists(guess) else ""

static func entry_vector(entry: Dictionary, key: String, ppu: float) -> Vector2:
	return Vector2(entry[key][0], entry[key][1]) * ppu

static func parse_joint(entry: Dictionary, ppu: float) -> Dictionary:
	var point := entry_vector(entry, "point", ppu)
	return {
		"type": entry.get("type", "pin"),
		"point": point,
		"point_b": entry_vector(entry, "point_b", ppu) if entry.has("point_b") else point,
		"distance": float(entry["distance"]) * ppu if entry.has("distance") else -1.0,
	}

static func spawn_joint(world: RegolithWorld, a: RegolithSprite, b: RegolithSprite, entry: Dictionary, ppu: float, origin := Transform2D.IDENTITY) -> int:
	var joint := parse_joint(entry, ppu)

	if joint["type"] != "distance":
		return world.add_joint(a, b, origin * joint["point"])

	return world.add_distance_joint(a, b, origin * joint["point"], origin * joint["point_b"], joint["distance"])

func spawn(path: String) -> bool:
	var data := read_file(path)
	var world := RegolithWorld.active()

	if data.is_empty() or world == null:
		push_warning("MultiSprite could not spawn %s" % path)
		return false

	var ppu := RegolithWorld.pixels_per_unit()

	for entry in data.get("sprites", []):
		var sprite := make_sprite(entry, ppu)
		if sprite:
			sprites.append(sprite)

	for entry in data.get("joints", []):
		var a: int = entry["a"]
		var b: int = entry["b"]
		if a < 0 or b < 0 or a >= sprites.size() or b >= sprites.size():
			continue

		var id := spawn_joint(world, sprites[a], sprites[b], entry, ppu, global_transform)
		if id >= 0:
			joints.append(id)

	var head_index := int(data.get("head", -1))
	if head_index >= 0 and head_index < sprites.size():
		head = sprites[head_index]
		snake_head = SnakeHead.new()
		head.add_child(snake_head)

	return true

func make_sprite(entry: Dictionary, ppu: float) -> RegolithSprite:
	var texture := load_texture(entry["texture"])
	if texture == null:
		push_warning("MultiSprite could not load " + str(entry["texture"]))
		return null

	var mask_path := mask_path_for(entry)

	var sprite := RegolithSprite.new()
	sprite.texture = texture
	sprite.mask_texture = load_texture(mask_path) if mask_path != "" else null
	sprite.material = sprite_material
	sprite.rope_material = rope_material
	sprite.dynamic = entry.get("dynamic", true)
	sprite.position = entry_vector(entry, "position", ppu)
	sprite.rotation = entry["rotation"]
	sprite.add_to_group("regolith")
	add_child(sprite)
	return sprite
