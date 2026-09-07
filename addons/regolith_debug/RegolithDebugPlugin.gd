@tool
extends EditorPlugin

# puts the Debug Draw dock next to the inspector, draws the debug lines over
# the scene being edited, and links the dock to the running game through the
# editor debugger. the game's DebugDraw autoload says "regolith:ready" when it
# enters the tree and gets the dock's settings back, later changes in the dock
# push straight to every live session
#
# the editor keeps a RegolithDebugDraw of its own, hidden, never drawing
# itself: the dock's settings go to it so the editor's color map matches,
# AiGizmos walks the edited scene into it, collect() turns that into pixels
# and the viewport overlay draws them through the editor camera

const Dock := preload("res://addons/regolith_debug/RegolithDebugDock.gd")
const Debugger := preload("res://addons/regolith_debug/RegolithDebugDebugger.gd")
const Gizmos := preload("res://game/scripts/debug/AiGizmos.gd")

var dock: Control
var debugger: EditorDebuggerPlugin
var draw: RegolithDebugDraw
var gizmos: Node

func _enter_tree() -> void:
	dock = Dock.new()
	dock.name = "Debug Draw"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

	debugger = Debugger.new()
	debugger.dock = dock
	add_debugger_plugin(debugger)

	draw = RegolithDebugDraw.new()
	draw.visible = false
	add_child(draw)

	gizmos = Gizmos.new()
	gizmos.name = "AiGizmos"
	draw.add_child(gizmos)

	dock.changed.connect(debugger.push_all)
	dock.changed.connect(apply_to_editor_draw)
	apply_to_editor_draw(dock.settings)

	set_force_draw_over_forwarding_enabled()

func _exit_tree() -> void:
	remove_debugger_plugin(debugger)
	remove_control_from_docks(dock)
	dock.queue_free()
	draw.queue_free()

# the editor drawer takes the colors and switches but stays hidden, it sits in
# the editor ui canvas and drawing itself would land at the window origin
func apply_to_editor_draw(settings: Dictionary) -> void:
	var own := settings.duplicate()
	own.erase("visible")
	draw.apply_settings(own)
	draw.visible = false
	update_overlays()

func _process(_delta: float) -> void:
	if dock.settings.get("visible", false) and EditorInterface.get_edited_scene_root():
		update_overlays()

func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	if not dock.settings.get("visible", false):
		return

	var root := EditorInterface.get_edited_scene_root()

	if root == null:
		return

	gizmos.emit_scene(root)

	if draw.collect() == 0:
		return

	var to_screen := EditorInterface.get_editor_viewport_2d().global_canvas_transform
	overlay.draw_multiline_colors(to_screen * draw.get_points(), draw.get_colors(), 1.0)
