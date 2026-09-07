@tool
extends EditorPlugin

# puts the Debug Draw dock next to the inspector and links it to the running
# game through the editor debugger. the game's RegolithDebugDraw says
# "regolith:ready" when it enters the tree and gets the dock's settings back,
# later changes in the dock push straight to every live session

const Dock := preload("res://addons/regolith_debug/RegolithDebugDock.gd")
const Debugger := preload("res://addons/regolith_debug/RegolithDebugDebugger.gd")

var dock: Control
var debugger: EditorDebuggerPlugin

func _enter_tree() -> void:
	dock = Dock.new()
	dock.name = "Debug Draw"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

	debugger = Debugger.new()
	debugger.dock = dock
	add_debugger_plugin(debugger)

	dock.changed.connect(debugger.push_all)

func _exit_tree() -> void:
	remove_debugger_plugin(debugger)
	remove_control_from_docks(dock)
	dock.queue_free()
