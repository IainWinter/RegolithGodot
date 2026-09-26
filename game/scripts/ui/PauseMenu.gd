extends MenuWindow
class_name PauseMenu

# the pause menu, shown by GameState in PAUSED over the frozen game. Resume
# and Quit work, Controls swaps the frame for a page listing every binding
# (ControlsList over Controls.describe()) with a Back button, Options and
# Main Menu are placeholders until their scenes exist.
# scene: res://game/scenes/ui/PauseMenu.tscn

signal resume_pressed
signal options_pressed
signal main_menu_pressed
signal quit_pressed

const CONTROLS_SIZE := Vector2(520, 360)
const CONTROLS_MARGIN := 24

var controls_page: PanelContainer
var controls_list: ControlsList
var back_button: Button

func _ready() -> void:
	super()
	chosen.connect(on_chosen)

func on_chosen(button: StringName) -> void:
	match button:
		&"Resume": resume_pressed.emit()
		&"Controls": show_controls()
		&"Options": options_pressed.emit()
		&"MainMenu": main_menu_pressed.emit()
		&"Quit": quit_pressed.emit()

func is_showing_controls() -> bool:
	return controls_page != null and controls_page.visible

func show_controls() -> void:
	if controls_page == null:
		build_controls_page()

	frame.visible = false
	controls_page.visible = true
	back_button.grab_focus()

func hide_controls() -> void:
	if controls_page:
		controls_page.visible = false

	frame.visible = true
	var controls := button_named(&"Controls")

	if controls:
		controls.grab_focus()

func build_controls_page() -> void:
	controls_page = PanelContainer.new()
	controls_page.name = "ControlsPage"
	controls_page.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER, PixelTheme.LINE, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, FRAME_PAD, FRAME_PAD))
	controls_page.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	controls_page.grow_horizontal = Control.GROW_DIRECTION_BOTH
	controls_page.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(controls_page)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	controls_page.add_child(page)

	var title := Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", PixelTheme.TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", PixelTheme.ACCENT)
	page.add_child(title)

	controls_list = ControlsList.new()
	var view := root.get_viewport_rect().size if root.is_inside_tree() else CONTROLS_SIZE
	controls_list.custom_minimum_size = CONTROLS_SIZE.min(view - Vector2.ONE * (CONTROLS_MARGIN * 2 + FRAME_PAD * 2)).max(Vector2(200, 120))
	page.add_child(controls_list)

	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "Back"
	back_button.custom_minimum_size.x = BUTTON_WIDTH
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.add_theme_stylebox_override("focus", PixelTheme.box(Color.TRANSPARENT, PixelTheme.ACCENT, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, 8, 3))
	back_button.pressed.connect(func():
		Sound.play(&"ui_click")
		hide_controls())
	page.add_child(back_button)
