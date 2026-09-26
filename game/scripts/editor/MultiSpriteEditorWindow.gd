extends CanvasLayer
class_name MultiSpriteEditorWindow

# the in game home of MultiSpriteEditor: a centered window over the dimmed
# game hosting the shared Control, plus Play, which writes the document to a
# scratch json and spawns it through a MultiSprite node so the running world
# solves the joints. Stop frees the spawn. arranging never touches the world,
# so the same editor Control also lives in the Godot editor's Sprites screen

const WINDOW_SIZE := Vector2(960, 600)
const WINDOW_MARGIN := 24
const MIN_SIZE := Vector2(560, 360)
const PLAY_FILE := "user://multisprite_play.json"

# json to open, empty starts a blank document
@export var path := ""
# where Play drops the MultiSprite, the parent when unset
@export var root: Node2D
@export var sprite_material: Material
@export var rope_material: Material

var editor: MultiSpriteEditor
var window: PanelContainer
var play_button: Button
var preview: MultiSprite
var ui_root: Control

signal closed

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	if root == null:
		root = get_parent() as Node2D

	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.theme = PixelTheme.theme()
	add_child(ui_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(dim)

	window = PanelContainer.new()
	window.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER, PixelTheme.LINE, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, 0, 0))
	ui_root.add_child(window)
	ui_root.resized.connect(layout_window)
	layout_window()

	editor = MultiSpriteEditor.new()
	editor.path = path
	editor.closed.connect(close)
	window.add_child(editor)

	play_button = Button.new()
	play_button.text = "Play"
	play_button.tooltip_text = "Drop the layout into the world and let it solve"
	play_button.focus_mode = Control.FOCUS_NONE
	play_button.pressed.connect(toggle_play)
	editor.host_actions.add_child(editor.section("World"))
	editor.host_actions.add_child(play_button)

func layout_window() -> void:
	var view := ui_root.size
	var wanted := WINDOW_SIZE.min(view - Vector2.ONE * (WINDOW_MARGIN * 2))
	wanted = wanted.max(MIN_SIZE).floor()
	window.size = wanted
	window.position = ((view - wanted) * 0.5).floor()

func playing() -> bool:
	return is_instance_valid(preview)

# where the spawn lands: the camera's view center, else the parent's origin
func play_origin() -> Vector2:
	var camera := root.get_viewport().get_camera_2d() if root and root.is_inside_tree() else null
	return camera.get_screen_center_position() if camera else Vector2.ZERO

func toggle_play() -> void:
	if playing():
		stop()
	else:
		play()

func play() -> void:
	if playing() or root == null or editor.doc.sprites.is_empty():
		return

	if RegolithWorld.active() == null:
		editor.message = "no world to play in"
		return

	if not editor.doc.save_to(PLAY_FILE):
		editor.message = "could not write " + PLAY_FILE
		return

	preview = MultiSprite.new()
	preview.file = PLAY_FILE
	preview.sprite_material = sprite_material
	preview.rope_material = rope_material
	preview.position = play_origin()
	root.add_child(preview)
	play_button.text = "Stop"
	editor.message = "playing"

func stop() -> void:
	if playing():
		preview.queue_free()
	preview = null
	play_button.text = "Play"
	editor.message = ""

func close() -> void:
	stop()
	closed.emit()
	queue_free()
