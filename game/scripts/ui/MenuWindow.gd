extends CanvasLayer
class_name MenuWindow

# the shared shape of the in game menus (pause, death): a full screen root
# with the PixelTheme, a dim over the game, and one Frame container holding
# a Column of a title and buttons. the Frame is the one node to swap when
# the menus get their generated pipe frames, the script only asks it to
# hold the Column. runs while the tree is paused. keyboard and gamepad move
# focus through the buttons (ui_up / ui_down, wrapping), ui_accept presses,
# disabled placeholders are skipped. the scene lays the nodes out, the
# script styles them and reports presses through chosen(button name)

signal chosen(button: StringName)

const BUTTON_WIDTH := 180
const FRAME_PAD := 16

@onready var root: Control = $Root
@onready var frame: Container = $Root/Frame
@onready var column: VBoxContainer = $Root/Frame/Column

var buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.theme = PixelTheme.theme()
	style()
	wire_buttons()
	focus_first()
	# the hover sound is for moving the cursor, not for opening
	for button in buttons:
		if not button.disabled:
			button.focus_entered.connect(on_focus_entered)

func style() -> void:
	if frame is PanelContainer:
		frame.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER, PixelTheme.LINE, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, FRAME_PAD, FRAME_PAD))

	column.add_theme_constant_override("separation", 6)

	for child in column.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", PixelTheme.TITLE_FONT_SIZE)
			child.add_theme_color_override("font_color", PixelTheme.ACCENT)
			child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif child is Button:
			child.custom_minimum_size.x = BUTTON_WIDTH
			# the theme hides focus, a menu needs to show where the cursor is
			child.add_theme_stylebox_override("focus", PixelTheme.box(Color.TRANSPARENT, PixelTheme.ACCENT, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, 8, 3))

func wire_buttons() -> void:
	buttons.clear()

	for child in column.get_children():
		if child is Button:
			buttons.append(child)

	var active: Array[Button] = []

	for button in buttons:
		if button.disabled:
			button.focus_mode = Control.FOCUS_NONE
			continue

		active.append(button)
		button.pressed.connect(on_pressed.bind(button))

	# wrap the cursor around the ends
	for i in active.size():
		var button := active[i]
		button.focus_neighbor_top = button.get_path_to(active[(i - 1 + active.size()) % active.size()])
		button.focus_neighbor_bottom = button.get_path_to(active[(i + 1) % active.size()])
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom

func focus_first() -> void:
	for button in buttons:
		if not button.disabled:
			button.grab_focus()
			return

func focused_button() -> Button:
	var owner_control := root.get_viewport().gui_get_focus_owner() if root.is_inside_tree() else null
	return owner_control as Button if owner_control in buttons else null

func button_named(button_name: StringName) -> Button:
	for button in buttons:
		if button.name == button_name:
			return button
	return null

func on_pressed(button: Button) -> void:
	Sound.play(&"ui_click")
	chosen.emit(button.name)

func on_focus_entered() -> void:
	Sound.play(&"ui_hover")
