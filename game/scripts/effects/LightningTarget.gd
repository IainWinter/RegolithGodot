extends RefCounted
class_name LightningTarget

# one end of a strike: a fixed point, a node followed while it is in the
# tree, or a cell riding on its sprite. made once at the strike() boundary
# from a Vector2, a Node2D or {"sprite": RegolithSprite, "cell": Vector2i}

var point := Vector2.ZERO
var node: Node2D
var sprite: RegolithSprite
var cell := Vector2i.ZERO

# null for anything that is not a target
static func make(value) -> LightningTarget:
	var target := LightningTarget.new()

	if value is Vector2:
		target.point = value
	elif value is Node2D and is_instance_valid(value):
		target.node = value
	elif value is Dictionary and value.get("sprite") is RegolithSprite and is_instance_valid(value["sprite"]):
		target.sprite = value["sprite"]
		target.cell = value.get("cell", Vector2i.ZERO)
	else:
		return null

	return target

func tracks() -> bool:
	return node != null or sprite != null

# world pixels, null once a followed node or sprite is gone
func position() -> Variant:
	if sprite != null:
		return sprite.cell_to_world(cell) if is_instance_valid(sprite) and sprite.is_inside_tree() else null

	if node != null:
		return node.global_position if is_instance_valid(node) and node.is_inside_tree() else null

	return point

# the same followed thing, fixed points never match
func equals(other: LightningTarget) -> bool:
	return tracks() and node == other.node and sprite == other.sprite and cell == other.cell
