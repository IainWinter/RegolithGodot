extends RegolithDebugDraw

# registered as an autoload by RegolithDebugPlugin so every scene gets the
# debug draw without needing a node placed in the scene tree. ALWAYS so filter
# and color edits from the editor dock repaint while the game is paused.
#
# a child GizmoWalker runs each frame, walks the current scene, and calls
# draw_gizmos(g) on every node that has it. so any @tool script can push
# its debug shapes without a separate collector node

const GizmoWalker := preload("res://addons/regolith_debug/GizmoWalker.gd")

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	var walker := GizmoWalker.new()
	walker.draw = self
	add_child(walker)
