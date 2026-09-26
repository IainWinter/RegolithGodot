extends CanvasLayer
class_name SpriteEditorWindow

# the in game home of SpriteEditor: a centered window floating over the dimmed,
# paused game so it reads as part of the game and not a separate tool. Main
# opens it on F2 with the png of the sprite under the mouse and pauses the
# tree, the X in the editor's title bar (or F2 again) closes it. the same
# SpriteEditor Control sits in the Godot editor's Sprites screen through the
# regolith_sprite_editor addon, which has no pause or dim

const WINDOW_SIZE := Vector2(816, 512)
const WINDOW_MARGIN := 24
const MIN_SIZE := Vector2(480, 320)

# png to open, empty starts a blank document
@export var path := ""

var editor: SpriteEditor
var root: Control
var window: PanelContainer

signal closed

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = PixelTheme.theme()
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	window = PanelContainer.new()
	window.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER, PixelTheme.LINE, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, 0, 0))
	root.add_child(window)
	root.resized.connect(layout_window)
	layout_window()

	editor = SpriteEditor.new()
	editor.path = path
	editor.closed.connect(close)
	window.add_child(editor)

# the window sits centered, shrinking when the viewport is smaller than it
func layout_window() -> void:
	var view := root.size
	var wanted := WINDOW_SIZE.min(view - Vector2.ONE * (WINDOW_MARGIN * 2))
	wanted = wanted.max(MIN_SIZE).floor()
	window.size = wanted
	window.position = ((view - wanted) * 0.5).floor()

func close() -> void:
	closed.emit()
	queue_free()
