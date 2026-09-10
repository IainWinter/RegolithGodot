extends Node

# each frame, walks the current scene and calls draw_gizmos(g) on every node
# that has the method. lives as a child of a RegolithDebugDraw and pushes
# into its line lists so the dock's filters and colors apply

var draw: RegolithDebugDraw
var gizmos := RuntimeGizmos.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# run before the drawer so pushed gizmos land in debug_render() ahead of
	# its gather+clear pass in the same frame
	process_priority = -100
	gizmos.draw = draw

func _process(_delta: float) -> void:
	if draw == null or not draw.is_visible_in_tree():
		return

	var scene := get_tree().current_scene
	if scene == null:
		return

	_walk(scene, Transform2D.IDENTITY)

# `current` is the nearest Node2D ancestor's global_transform, threaded down
# so scripts on plain Node children draw in their host's local space
func _walk(node: Node, current: Transform2D) -> void:
	var t: Transform2D = (node as Node2D).global_transform if node is Node2D else current
	if node.has_method("draw_gizmos"):
		gizmos.transform = t
		node.draw_gizmos(gizmos)
	for child in node.get_children():
		_walk(child, t)
