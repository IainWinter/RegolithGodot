@tool
extends Node2D
class_name MultiSpritePreview

# editor only: draws the parts of a MultiSprite document that the parent
# sprite does not show itself, so a scene whose extra parts are built at
# runtime (an EnemyGun's barrel) looks whole in the 2D viewport. the
# document is the parent's multisprite export (EnemyGun) or file export
# (MultiSprite), else this node's own file. the parent stands for the
# document's root entry and draws its own texture centered on its origin
# like RegolithSprite's editor preview, the other entries are drawn where
# the document puts them relative to it, joints as small rings. frees
# itself when the game runs

const JOINT_COLOR := Color(1.0, 0.8, 0.2, 0.9)

@export_file("*.json") var file: String:
	set(value):
		file = value
		queue_redraw()

func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return

	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED:
		queue_redraw()

func document_path() -> String:
	var parent := get_parent()

	if parent:
		for property in ["multisprite", "file"]:
			var value = parent.get(property)
			if value is String and value != "":
				return value

	return file

static func pixels_per_cell() -> float:
	var world := RegolithWorld.active()
	return float(world.pixels_per_cell) if world else 1.0

func _draw() -> void:
	var doc := MultiSpriteDocument.new()

	if not doc.load_from(document_path()):
		return

	var data := MultiSpriteDocument.read_file(document_path())
	if doc.sprites.is_empty():
		return

	var root := clampi(int(data.get("root", 0)), 0, doc.sprites.size() - 1)

	# document cells to this node's pixels: the root entry's frame, its art
	# centered on the origin as the parent's preview draws it
	var root_center := doc.art_offset(root) + Vector2(doc.size_cells(root)) * 0.5
	var ppc := pixels_per_cell()
	var to_local := Transform2D(0.0, Vector2(ppc, ppc), 0.0, -root_center * ppc) * doc.transform_of(root).affine_inverse()

	for i in doc.sprites.size():
		if i == root:
			continue

		var path: String = doc.sprites[i]["texture"]
		var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null

		if texture == null:
			continue

		draw_set_transform_matrix(to_local * doc.transform_of(i))
		draw_texture_rect(texture, Rect2(doc.art_offset(i), Vector2(doc.size_cells(i))), false)

	draw_set_transform_matrix(Transform2D.IDENTITY)

	for joint in doc.joints:
		draw_arc(to_local * doc.units_to_cells(joint["point"]), 2.0 * ppc, 0.0, TAU, 12, JOINT_COLOR, 1.0)
