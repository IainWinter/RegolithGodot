@tool
extends EditorPlugin

# puts the Debug Draw dock next to the inspector, autoloads a RegolithDebugDraw
# so every scene renders lines without a node placed by hand, and links the
# dock to the running game through the editor debugger. the autoloaded drawer
# says "regolith:ready" when it enters the tree and gets the dock's settings
# back, later changes in the dock push straight to every live session.
#
# also owns an off-tree RegolithDebugDraw whose settings mirror the dock, and
# uses it as the source of truth when painting edit-time gizmos so the same
# filter/color the dock applies at runtime applies in the viewport overlay

const Dock := preload("res://addons/regolith_debug/RegolithDebugDock.gd")
const Debugger := preload("res://addons/regolith_debug/RegolithDebugDebugger.gd")

const AUTOLOAD_NAME := "RegolithDebugDrawAuto"
const AUTOLOAD_PATH := "res://addons/regolith_debug/RegolithDebugDrawAutoload.gd"

var dock: Control
var debugger: EditorDebuggerPlugin
var settings_source: RegolithDebugDraw

func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)

func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)

func _enter_tree() -> void:
	dock = Dock.new()
	dock.name = "Debug Draw"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

	debugger = Debugger.new()
	debugger.dock = dock
	add_debugger_plugin(debugger)

	settings_source = RegolithDebugDraw.new()

	dock.changed.connect(_on_dock_changed)
	_on_dock_changed(dock.settings)

	# _forward_canvas_draw_over_viewport only fires while the plugin is
	# handling the current selection; the "force" variant fires on every
	# viewport redraw regardless, so gizmos show without anything selected
	set_force_draw_over_forwarding_enabled()

func _exit_tree() -> void:
	remove_debugger_plugin(debugger)
	remove_control_from_docks(dock)
	dock.queue_free()
	settings_source.free()

func _on_dock_changed(settings: Dictionary) -> void:
	settings_source.apply_settings(settings)
	debugger.push_all(settings)

func _process(_delta: float) -> void:
	update_overlays()

# _forward_canvas_force_draw_over_viewport fires regardless of selection —
# enabled in _enter_tree via set_force_draw_over_forwarding_enabled — so
# gizmos render whether or not an object is picked in the scene tree
func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not dock.settings.get("visible", true):
		return

	var gizmos := EditorGizmos.new()
	gizmos.overlay = overlay
	gizmos.xform = EditorInterface.get_editor_viewport_2d().global_canvas_transform
	gizmos.source = settings_source

	_walk(root, gizmos, Transform2D.IDENTITY)

# `current` is the nearest Node2D ancestor's global_transform, threaded down
# so scripts on plain Node children draw in their host's local space.
# _is_tool_script filters out placeholder instances from non-@tool scripts
# in instanced sub-scenes, so we can walk the whole tree
func _walk(node: Node, gizmos: RegolithGizmos, current: Transform2D) -> void:
	var t: Transform2D = (node as Node2D).global_transform if node is Node2D else current
	if node.has_method("draw_gizmos") and _is_tool_script(node):
		gizmos.transform = t
		node.draw_gizmos(gizmos)
	for child in node.get_children():
		_walk(child, gizmos, t)

# non-@tool scripts run as placeholders at edit time and crash if called.
# Script.is_tool() isn't exposed reliably, so check the source directly
func _is_tool_script(node: Node) -> bool:
	var script := node.get_script() as Script
	if script == null or not script.has_source_code():
		return false
	return script.get_source_code().strip_edges().begins_with("@tool")
