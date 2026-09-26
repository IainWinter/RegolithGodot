@tool
extends Control
class_name SpriteEditor

# pixel editor, a port of the old imgui SpriteEditorTool built from Control
# nodes. edits a SpriteDocument backed by a png plus _mask.png pair on disk,
# the source files sprites are made from. it never touches a live
# RegolithSprite, sprites pick the change up when they next load the texture.
#
# this Control is the whole editor (title, sidebar, tools, canvas, status) and
# knows nothing about where it is hosted. SpriteEditorWindow floats it over
# the paused game (F2), the regolith_sprite_editor addon puts it in a main
# screen of the Godot editor. a host that owns the file dialogs sets
# host_files and answers load_requested / save_requested. looks come from
# PixelTheme. paths may be res:// or absolute, disk io goes through disk_path

enum Tool { PENCIL, ERASER, FILL, PICKER, SELECT, MOVE, RECT, LINE }

const TOOL_LABELS := [["Pen", "B"], ["Erase", "E"], ["Fill", "G"], ["Pick", "I"], ["Select", "M"], ["Move", "V"], ["Rect", "R"], ["Line", "L"]]
const MODE_LABELS := ["Paint", "Mask", "Class", "Glow"]
const SIDEBAR_WIDTH := 208
const PALETTE_COLUMNS := 8
const PALETTE_ROWS := 4
const SWATCH := 20
const ACCENT := PixelTheme.ACCENT

# the fixed first rows of the palette, the rest fills with colors in the sprite
const PALETTE_BASE: Array[Color] = [
	Color8(255, 255, 255), Color8(194, 195, 199), Color8(131, 118, 156), Color8(95, 87, 79),
	Color8(41, 40, 48), Color8(16, 14, 20), Color8(255, 241, 232), Color8(255, 236, 39),
	Color8(255, 163, 0), Color8(255, 0, 77), Color8(126, 37, 83), Color8(171, 82, 54),
	Color8(0, 228, 54), Color8(0, 135, 81), Color8(41, 173, 255), Color8(29, 43, 83),
]

static var clipboard := {}

# png to open on ready, empty starts a blank document
@export var path := ""
# the host pops its own file dialogs and answers the *_requested signals
@export var host_files := false
# the title bar close button, hosts that embed the editor for good hide it
@export var show_close := true

var doc := SpriteDocument.new(32, 32)
var canvas: SpriteCanvas

var tool := Tool.PENCIL
var brush_size := 1
var rect_filled := false
var layer_opacity := 0.5
var filename := "new_sprite"

var hover := Vector2i(-1, -1)
var last_paint_cell := Vector2i(-1, -1)

var sel_dragging := false
var sel_anchor := Vector2i.ZERO
var sel_start := Rect2i()
var sel_start_active := false

var shape_active := false
var shape_erase := false
var shape_start := Vector2i.ZERO
var shape_end := Vector2i.ZERO

var float_region := {}
var float_before := {}
var float_lifted := false
var float_drag := false
var float_pos := Vector2i.ZERO
var float_src := Vector2i.ZERO
var float_grab := Vector2i.ZERO

var root: Control
var mode_buttons: Array[Button] = []
var tool_buttons: Array[Button] = []
var type_buttons: Array[Button] = []
var class_buttons: Array[Button] = []
var mode_sections: Array[Control] = []
var color_button: ColorPickerButton
var hex_edit: LineEdit
var palette_grid: GridContainer
var palette_buttons: Array[Button] = []
var palette_colors: Array[Color] = []
var palette_dirty := true
var palette_shown := Color(-1, -1, -1, -1)
var brush_slider: HSlider
var brush_label: Label
var opacity_slider: HSlider
var size_x: SpinBox
var size_y: SpinBox
var name_edit: LineEdit
var zoom_label: Label
var status: Label
var undo_button: Button
var redo_button: Button
var paste_all_check: CheckBox
var file_dialog: FileDialog
var close_button: Button
var message := ""
# the file the document came from or was last saved to, "" for a new one
var file_path := ""

signal closed
signal load_requested
signal save_requested
# a png pair was written or read, path as given to save_to / load_from
signal saved(path: String)
signal loaded(path: String)

func _ready() -> void:
	build_ui()

	if path == "" or not load_from(path):
		canvas.fit_to_view()

func close() -> void:
	closed.emit()

# drops (files from the FileSystem dock in the Godot editor) belong to the
# host. the drop walk stops at the first mouse-stopping Control, so the editor
# and its canvas hand them up by hand
var drop_target: Control

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return drop_target != null and drop_target._can_drop_data(at, data)

func _drop_data(at: Vector2, data: Variant) -> void:
	if drop_target:
		drop_target._drop_data(at, data)

func build_ui() -> void:
	root = self
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = PixelTheme.theme()

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	column.add_child(build_title())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	column.add_child(body)

	body.add_child(build_sidebar())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	body.add_child(right)

	right.add_child(build_toolbar())

	canvas = SpriteCanvas.new()
	canvas.editor = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.cell_input.connect(canvas_input)
	canvas.cell_picked.connect(pick_at)
	canvas.hovered.connect(set_hover)
	right.add_child(canvas)

	right.add_child(build_status())

	for button in root.find_children("*", "BaseButton", true, false):
		button.focus_mode = Control.FOCUS_NONE

	for slider in root.find_children("*", "Slider", true, false):
		slider.focus_mode = Control.FOCUS_NONE

	if not host_files:
		file_dialog = FileDialog.new()
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.filters = PackedStringArray(["*.png ; PNG"])
		file_dialog.size = Vector2i(640, 420)
		file_dialog.current_dir = ProjectSettings.globalize_path("res://game/images/sprites")
		file_dialog.file_selected.connect(on_file_selected)
		add_child(file_dialog)

	set_mode(doc.mode)
	sync_ui()

func build_title() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.INK, PixelTheme.LINE, 0, 0, 0, PixelTheme.BORDER, 8, 4))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)

	var title := Label.new()
	title.text = "SPRITE"
	title.add_theme_font_size_override("font_size", PixelTheme.TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", ACCENT)
	row.add_child(title)

	name_edit = LineEdit.new()
	name_edit.text = filename
	name_edit.custom_minimum_size.x = 160
	name_edit.placeholder_text = "name"
	name_edit.text_changed.connect(func(t): filename = t)
	row.add_child(name_edit)

	row.add_child(action("Load", request_load, false))
	row.add_child(action("Save", request_save, false))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	close_button = action("X", close, false)
	close_button.tooltip_text = "Close (F2)"
	close_button.visible = show_close
	row.add_child(close_button)

	return bar

func build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = SIDEBAR_WIDTH
	panel.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER, PixelTheme.LINE, 0, 0, PixelTheme.BORDER, 0, 0, 0))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	scroll.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var history := HBoxContainer.new()
	box.add_child(history)
	undo_button = action("Undo", undo)
	redo_button = action("Redo", redo)
	history.add_child(undo_button)
	history.add_child(redo_button)

	var clip := HBoxContainer.new()
	box.add_child(clip)
	clip.add_child(action("Copy", copy_selection))
	clip.add_child(action("Cut", cut_selection))
	clip.add_child(action("Paste", paste_clipboard))
	clip.add_child(action("Dup", duplicate_selection))

	box.add_child(section("Layer"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 2)
	box.add_child(modes)
	var mode_group := ButtonGroup.new()
	for i in MODE_LABELS.size():
		var button := Button.new()
		button.text = MODE_LABELS[i]
		button.toggle_mode = true
		button.button_group = mode_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
		button.pressed.connect(func(): set_mode(i))
		modes.add_child(button)
		mode_buttons.append(button)

	var graphics := VBoxContainer.new()
	box.add_child(graphics)
	graphics.add_child(section("Color"))

	var color_row := HBoxContainer.new()
	graphics.add_child(color_row)
	color_button = ColorPickerButton.new()
	color_button.edit_alpha = true
	color_button.color = doc.paint_color
	color_button.custom_minimum_size = Vector2(SWATCH * 2, SWATCH + 2)
	color_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_button.color_changed.connect(func(c): doc.paint_color = c)
	color_button.picker_created.connect(setup_picker)
	color_row.add_child(color_button)
	hex_edit = LineEdit.new()
	hex_edit.custom_minimum_size.x = 84
	hex_edit.placeholder_text = "hex"
	hex_edit.text_submitted.connect(on_hex_submitted)
	color_row.add_child(hex_edit)

	palette_grid = GridContainer.new()
	palette_grid.columns = PALETTE_COLUMNS
	palette_grid.add_theme_constant_override("h_separation", 2)
	palette_grid.add_theme_constant_override("v_separation", 2)
	graphics.add_child(palette_grid)
	for i in PALETTE_COLUMNS * PALETTE_ROWS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(SWATCH, SWATCH)
		button.pressed.connect(func(): pick_palette(i))
		palette_grid.add_child(button)
		palette_buttons.append(button)
	mode_sections.append(graphics)

	var mask := VBoxContainer.new()
	box.add_child(mask)
	mask.add_child(section("Mask Type"))
	var type_grid := GridContainer.new()
	type_grid.columns = 2
	type_grid.add_theme_constant_override("h_separation", 2)
	type_grid.add_theme_constant_override("v_separation", 2)
	mask.add_child(type_grid)
	var type_group := ButtonGroup.new()
	for i in SpriteDocument.TYPE_COUNT:
		var button := swatch_button(SpriteDocument.TYPE_NAMES[i], SpriteDocument.TYPE_DISPLAY[i], type_group)
		button.pressed.connect(func(): doc.paint_type = i)
		type_grid.add_child(button)
		type_buttons.append(button)
	mode_sections.append(mask)

	var armor := VBoxContainer.new()
	box.add_child(armor)
	armor.add_child(section("Armor Class"))
	var class_grid := GridContainer.new()
	class_grid.columns = 4
	class_grid.add_theme_constant_override("h_separation", 2)
	class_grid.add_theme_constant_override("v_separation", 2)
	armor.add_child(class_grid)
	var class_group := ButtonGroup.new()
	for i in SpriteDocument.CLASS_COUNT:
		var button := swatch_button("%d" % i, SpriteDocument.CLASS_DISPLAY[i], class_group)
		button.pressed.connect(func(): doc.paint_class = i)
		class_grid.add_child(button)
		class_buttons.append(button)
	mode_sections.append(armor)

	var emission := VBoxContainer.new()
	box.add_child(emission)
	emission.add_child(section("Glow"))
	var hint := Label.new()
	hint.text = "Cells that glow. Left adds, right erases. Core cells always glow."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
	hint.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	emission.add_child(hint)
	mode_sections.append(emission)

	box.add_child(section("Overlay"))
	opacity_slider = HSlider.new()
	opacity_slider.min_value = 0.0
	opacity_slider.max_value = 1.0
	opacity_slider.step = 0.01
	opacity_slider.value = layer_opacity
	opacity_slider.value_changed.connect(func(v): layer_opacity = v)
	box.add_child(labeled("Opacity", opacity_slider))

	box.add_child(section("Paint"))
	box.add_child(check("Filled rect", rect_filled, func(on): rect_filled = on))
	paste_all_check = check("Paste all layers", doc.paste_all_layers, func(on): doc.paste_all_layers = on)
	box.add_child(paste_all_check)

	box.add_child(section("Canvas"))
	var size_row := HBoxContainer.new()
	box.add_child(size_row)
	size_x = spin(1, SpriteDocument.MAX_SIZE, doc.width)
	size_y = spin(1, SpriteDocument.MAX_SIZE, doc.height)
	size_row.add_child(size_x)
	var by := Label.new()
	by.text = "x"
	by.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	size_row.add_child(by)
	size_row.add_child(size_y)

	var canvas_row := HBoxContainer.new()
	box.add_child(canvas_row)
	canvas_row.add_child(action("Resize", func(): commit_float(); doc.resize_recorded(int(size_x.value), int(size_y.value)); canvas.fit_to_view()))
	canvas_row.add_child(action("Clear", func(): commit_float(); doc.clear_recorded()))

	return panel

func build_toolbar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER, PixelTheme.LINE, 0, 0, 0, PixelTheme.BORDER, 6, 3))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	panel.add_child(bar)

	var tool_group := ButtonGroup.new()
	for i in TOOL_LABELS.size():
		var button := Button.new()
		button.text = TOOL_LABELS[i][0]
		button.tooltip_text = "%s (%s)" % [TOOL_LABELS[i][0], TOOL_LABELS[i][1]]
		button.toggle_mode = true
		button.button_group = tool_group
		button.pressed.connect(func(): set_tool(i))
		bar.add_child(button)
		tool_buttons.append(button)

	bar.add_child(VSeparator.new())

	brush_label = Label.new()
	brush_label.text = "Brush 1"
	brush_label.custom_minimum_size.x = 56
	bar.add_child(brush_label)
	brush_slider = HSlider.new()
	brush_slider.min_value = 1
	brush_slider.max_value = 16
	brush_slider.step = 1
	brush_slider.value = brush_size
	brush_slider.custom_minimum_size.x = 80
	brush_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brush_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brush_slider.value_changed.connect(func(v): brush_size = int(v))
	bar.add_child(brush_slider)

	return panel

func build_status() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.INK, PixelTheme.LINE, 0, PixelTheme.BORDER, 0, 0, 6, 2))
	var row := HBoxContainer.new()
	panel.add_child(row)

	status = Label.new()
	status.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
	status.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(status)

	for button in [action("-", func(): canvas.zoom_by(1.0 / 1.25), false), action("+", func(): canvas.zoom_by(1.25), false), action("Fit", func(): canvas.fit_to_view(), false)]:
		button.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
		row.add_child(button)

	zoom_label = Label.new()
	zoom_label.custom_minimum_size.x = 48
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zoom_label.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
	zoom_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	row.add_child(zoom_label)

	return panel

func setup_picker() -> void:
	var picker := color_button.get_picker()
	picker.presets_visible = false
	picker.sampler_visible = false
	picker.can_add_swatches = false
	picker.color_modes_visible = false
	picker.picker_shape = ColorPicker.SHAPE_HSV_RECTANGLE

func on_hex_submitted(text: String) -> void:
	var html := text.strip_edges()
	if not html.begins_with("#"):
		html = "#" + html

	if Color.html_is_valid(html):
		doc.paint_color = Color.html(html)

	hex_edit.release_focus()

func pick_palette(i: int) -> void:
	if i < palette_colors.size():
		doc.paint_color = palette_colors[i]

# fixed base colors first, then the colors in the sprite by how often they
# appear. runs after every edit, sampling big sprites so it stays cheap
func refresh_palette() -> void:
	palette_dirty = false

	var counts := {}
	var total := doc.cell_count()
	var stride := maxi(1, ceili(total / 65536.0))
	var i := 0
	while i < total:
		var c := doc.get_cell_color(i)
		if c.a > 0.0:
			var key := c.to_rgba32()
			counts[key] = counts.get(key, 0) + 1
		i += stride

	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])

	palette_colors.clear()
	for c in PALETTE_BASE:
		palette_colors.append(c)

	var base_keys := {}
	for c in PALETTE_BASE:
		base_keys[c.to_rgba32()] = true

	for key in keys:
		if palette_colors.size() >= palette_buttons.size():
			break
		if base_keys.has(key):
			continue
		palette_colors.append(Color.hex(key))

	for b in palette_buttons.size():
		var button := palette_buttons[b]
		button.visible = b < palette_colors.size()

	palette_shown = Color(-1, -1, -1, -1)

func highlight_palette() -> void:
	palette_shown = doc.paint_color

	for b in palette_colors.size():
		var c := palette_colors[b]
		var picked := c.is_equal_approx(doc.paint_color)
		var button := palette_buttons[b]
		button.add_theme_stylebox_override("normal", PixelTheme.box(c, ACCENT if picked else PixelTheme.INK, 2, 2, 2, 2, 0, 0))
		button.add_theme_stylebox_override("hover", PixelTheme.box(c, PixelTheme.TEXT, 2, 2, 2, 2, 0, 0))
		button.add_theme_stylebox_override("pressed", PixelTheme.box(c, ACCENT, 2, 2, 2, 2, 0, 0))
		button.add_theme_stylebox_override("hover_pressed", PixelTheme.box(c, ACCENT, 2, 2, 2, 2, 0, 0))

func section(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
	label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	return label

func labeled(text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 48
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row

func spin(min_value: float, max_value: float, value: float) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = min_value
	box.max_value = max_value
	box.value = value
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

func action(text: String, on_press: Callable, expand := true) -> Button:
	var button := Button.new()
	button.text = text
	if expand:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_press)
	return button

func check(text: String, value: bool, on_toggle: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = value
	box.toggled.connect(on_toggle)
	return box

func swatch_button(text: String, color: Color, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)

	var shown := color if color.a > 0.0 else PixelTheme.PAPER_SUNKEN
	var lum := 0.299 * shown.r + 0.587 * shown.g + 0.114 * shown.b
	var ink := PixelTheme.ACCENT_TEXT if lum > 0.5 else Color.WHITE
	for state in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, ink)

	button.add_theme_stylebox_override("normal", PixelTheme.box(shown, PixelTheme.INK, 2, 2, 2, 2, 4, 1))
	button.add_theme_stylebox_override("hover", PixelTheme.box(shown.lightened(0.15), PixelTheme.TEXT, 2, 2, 2, 2, 4, 1))
	button.add_theme_stylebox_override("pressed", PixelTheme.box(shown, ACCENT, 2, 2, 2, 2, 4, 1))
	button.add_theme_stylebox_override("hover_pressed", PixelTheme.box(shown.lightened(0.15), ACCENT, 2, 2, 2, 2, 4, 1))
	return button

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		sync_ui()

func sync_ui() -> void:
	if root == null:
		return

	for i in mode_buttons.size():
		mode_buttons[i].set_pressed_no_signal(i == doc.mode)

	for i in tool_buttons.size():
		tool_buttons[i].set_pressed_no_signal(i == tool)

	for i in type_buttons.size():
		type_buttons[i].set_pressed_no_signal(i == doc.paint_type)

	for i in class_buttons.size():
		class_buttons[i].set_pressed_no_signal(i == doc.paint_class)

	if color_button.color != doc.paint_color:
		color_button.color = doc.paint_color

	if not hex_edit.has_focus():
		var html := doc.paint_color.to_html(doc.paint_color.a < 1.0)
		if hex_edit.text != html:
			hex_edit.text = html

	if doc.color_dirty and not doc.editing():
		palette_dirty = true

	if palette_dirty and not doc.editing():
		refresh_palette()

	if palette_shown != doc.paint_color:
		highlight_palette()

	if int(brush_slider.value) != brush_size:
		brush_slider.set_value_no_signal(brush_size)
	brush_label.text = "Brush %d" % brush_size

	if paste_all_check.button_pressed != doc.paste_all_layers:
		paste_all_check.set_pressed_no_signal(doc.paste_all_layers)

	undo_button.disabled = not doc.can_undo()
	redo_button.disabled = not doc.can_redo()
	zoom_label.text = "%d%%" % int(round(canvas.view_zoom * 100.0))
	status.text = status_text()

func status_text() -> String:
	var parts: Array[String] = []

	if hover.x >= 0:
		parts.append("%d, %d" % [hover.x, hover.y])
		var i := doc.index(hover.x, hover.y)
		match doc.mode:
			SpriteDocument.Mode.GRAPHICS:
				var c := doc.get_cell_color(i)
				parts.append("%d %d %d %d" % [c.r8, c.g8, c.b8, c.a8])
			SpriteDocument.Mode.MASK:
				parts.append(SpriteDocument.TYPE_NAMES[doc.get_cell_type(i)])
			SpriteDocument.Mode.CLASS:
				parts.append("class %d" % doc.get_cell_class(i))
			_:
				parts.append("emission on" if doc.get_cell_emissive(i) else "emission off")
	else:
		parts.append("-, -")

	parts.append("%d x %d" % [doc.width, doc.height])

	if doc.selection_active:
		parts.append("sel %d x %d at %d, %d" % [doc.selection.size.x, doc.selection.size.y, doc.selection.position.x, doc.selection.position.y])

	if has_float():
		parts.append("floating")

	if not message.is_empty():
		parts.append(message)

	return "   ".join(parts)

func typing() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return owner is LineEdit or owner is TextEdit

func set_mode(mode: int) -> void:
	if mode != doc.mode:
		commit_float()
		doc.mode = mode as SpriteDocument.Mode

	for i in mode_sections.size():
		mode_sections[i].visible = i == doc.mode

func set_tool(next: int) -> void:
	if next == tool:
		return

	commit_float()
	tool = next as Tool
	shape_active = false
	sel_dragging = false
	last_paint_cell = Vector2i(-1, -1)

func tool_uses_brush() -> bool:
	return tool == Tool.PENCIL or tool == Tool.ERASER or tool == Tool.RECT or tool == Tool.LINE

func set_hover(x: int, y: int) -> void:
	hover = Vector2i(x, y) if doc.in_bounds(x, y) else Vector2i(-1, -1)

func pick_at(x: int, y: int) -> void:
	doc.pick_at(x, y)

func undo() -> void:
	cancel_float()
	doc.undo()

func redo() -> void:
	cancel_float()
	doc.redo()

func canvas_input(hovered: bool, gx: int, gy: int, left_click: bool, right_click: bool, left_down: bool, right_down: bool) -> void:
	if doc.width <= 0:
		return

	message = ""

	if has_float():
		var inside := float_rect().has_point(Vector2i(gx, gy))

		if left_click and inside:
			float_drag = true
			float_grab = Vector2i(gx, gy) - float_pos
		elif left_click:
			commit_float()
			return

		if float_drag:
			if left_down:
				float_pos = Vector2i(gx, gy) - float_grab
				doc.selection.position = float_pos
			else:
				float_drag = false

		return

	match tool:
		Tool.SELECT:
			if left_click:
				sel_dragging = true
				sel_anchor = Vector2i(gx, gy)
				sel_start_active = Controls.held(Controls.SPRITE_SELECT_ADD) and doc.selection_active
				sel_start = doc.selection

			if sel_dragging:
				doc.set_selection(sel_anchor.x, sel_anchor.y, gx, gy)

				if sel_start_active:
					if doc.selection_active:
						var merged := doc.selection.merge(sel_start)
						doc.set_selection(merged.position.x, merged.position.y, merged.end.x - 1, merged.end.y - 1)
					else:
						doc.selection = sel_start
						doc.selection_active = true

				if not left_down:
					sel_dragging = false
			return

		Tool.MOVE:
			if left_click and doc.selection_active and doc.cell_selected(gx, gy):
				lift_selection()
				if has_float():
					float_drag = true
					float_grab = Vector2i(gx, gy) - float_pos
			return

		Tool.PICKER:
			if left_click:
				pick_at(gx, gy)
			return

		Tool.FILL:
			if left_click or right_click:
				doc.begin_edit()
				doc.flood_fill_at(gx, gy, right_click)
				doc.end_edit()
			return

		Tool.RECT, Tool.LINE:
			if not shape_active and (left_click or right_click):
				shape_active = true
				shape_erase = right_click
				shape_start = Vector2i(gx, gy)
				shape_end = shape_start

			if shape_active:
				shape_end = Vector2i(gx, gy)

				if not left_down and not right_down:
					doc.begin_edit()
					if tool == Tool.RECT:
						doc.paint_rect(shape_start.x, shape_start.y, shape_end.x, shape_end.y, brush_size, rect_filled, shape_erase)
					else:
						doc.paint_line(shape_start.x, shape_start.y, shape_end.x, shape_end.y, brush_size, shape_erase)
					doc.end_edit()
					shape_active = false
			return

	var any_down := left_down or right_down

	if hovered and any_down and not doc.editing():
		doc.begin_edit()

	if hovered and any_down:
		var erase := right_down or tool == Tool.ERASER

		if last_paint_cell.x >= 0:
			doc.paint_line(last_paint_cell.x, last_paint_cell.y, gx, gy, brush_size, erase)
		else:
			doc.paint_brush(gx, gy, brush_size, erase)

		if doc.in_bounds(gx, gy):
			last_paint_cell = Vector2i(gx, gy)
	else:
		last_paint_cell = Vector2i(-1, -1)

	if doc.editing() and not any_down:
		doc.end_edit()

func has_float() -> bool:
	return not SpriteDocument.region_empty(float_region)

func float_rect() -> Rect2i:
	return Rect2i(float_pos, Vector2i(float_region["w"], float_region["h"]))

func reset_float() -> void:
	float_region = {}
	float_before = {}
	float_drag = false
	float_lifted = false

func select_all() -> void:
	commit_float()
	doc.select_all()

func deselect() -> void:
	doc.deselect()
	sel_dragging = false

func clear_selected_region() -> void:
	if not doc.selection_active:
		return

	doc.begin_edit()
	doc.clear_region(doc.selection)
	doc.end_edit()

func copy_selection() -> void:
	commit_float()
	if doc.selection_active:
		clipboard = doc.copy_region(doc.selection)

func cut_selection() -> void:
	commit_float()
	if doc.selection_active:
		clipboard = doc.copy_region(doc.selection)
		clear_selected_region()

func paste_clipboard() -> void:
	if SpriteDocument.region_empty(clipboard):
		return

	commit_float()
	float_region = clipboard.duplicate(true)
	float_before = doc.snapshot()
	float_lifted = false

	if doc.selection_active:
		float_pos = doc.selection.position
	else:
		float_pos = Vector2i(floori(canvas.view_offset.x) - float_region["w"] / 2, floori(canvas.view_offset.y) - float_region["h"] / 2)

	float_src = float_pos
	float_drag = false
	tool = Tool.MOVE
	doc.set_selection(float_pos.x, float_pos.y, float_pos.x + float_region["w"] - 1, float_pos.y + float_region["h"] - 1)

func duplicate_selection() -> void:
	commit_float()
	if not doc.selection_active:
		return

	float_region = doc.copy_region(doc.selection)
	float_before = doc.snapshot()
	float_lifted = false
	float_pos = doc.selection.position
	float_src = float_pos
	float_drag = false
	tool = Tool.MOVE

func lift_selection() -> void:
	if not doc.selection_active or has_float():
		return

	float_region = doc.copy_region(doc.selection)
	float_before = doc.snapshot()
	float_pos = doc.selection.position
	float_src = float_pos
	float_lifted = true
	doc.clear_region(doc.selection)

func commit_float() -> void:
	if not has_float():
		float_drag = false
		float_lifted = false
		return

	doc.write_region(float_region, float_pos.x, float_pos.y)

	var after := doc.snapshot()
	if not SpriteDocument.snapshots_equal(float_before, after):
		doc.push_history(float_before, after)

	doc.set_selection(float_pos.x, float_pos.y, float_pos.x + float_region["w"] - 1, float_pos.y + float_region["h"] - 1)
	reset_float()

func cancel_float() -> void:
	if not has_float():
		return

	if float_lifted:
		doc.write_region(float_region, float_src.x, float_src.y)

	doc.set_selection(float_src.x, float_src.y, float_src.x + float_region["w"] - 1, float_src.y + float_region["h"] - 1)
	reset_float()

func nudge(dx: int, dy: int) -> void:
	if has_float():
		float_pos += Vector2i(dx, dy)
		doc.selection.position = float_pos
	elif doc.selection_active:
		var s := doc.selection
		doc.set_selection(s.position.x + dx, s.position.y + dy, s.end.x - 1 + dx, s.end.y - 1 + dy)

# the key bindings in match order, redo ahead of undo so Ctrl+Shift+Z is
# a redo. Controls.pressed keeps Ctrl combos apart from the bare keys
func key_bindings() -> Array:
	return [
		[Controls.SPRITE_REDO, redo],
		[Controls.SPRITE_UNDO, undo],
		[Controls.SPRITE_SELECT_ALL, select_all],
		[Controls.SPRITE_COPY, copy_selection],
		[Controls.SPRITE_CUT, cut_selection],
		[Controls.SPRITE_PASTE, paste_clipboard],
		[Controls.SPRITE_DUPLICATE, duplicate_selection],
		[Controls.SPRITE_FIT, canvas.fit_to_view],
		[Controls.SPRITE_PENCIL, set_tool.bind(Tool.PENCIL)],
		[Controls.SPRITE_ERASER, set_tool.bind(Tool.ERASER)],
		[Controls.SPRITE_FILL, set_tool.bind(Tool.FILL)],
		[Controls.SPRITE_PICKER, set_tool.bind(Tool.PICKER)],
		[Controls.SPRITE_SELECT, set_tool.bind(Tool.SELECT)],
		[Controls.SPRITE_MOVE, set_tool.bind(Tool.MOVE)],
		[Controls.SPRITE_RECT, set_tool.bind(Tool.RECT)],
		[Controls.SPRITE_LINE, set_tool.bind(Tool.LINE)],
		[Controls.SPRITE_DESELECT, drop_float_or_deselect],
		[Controls.SPRITE_DELETE, drop_float_or_clear],
		[Controls.SPRITE_COMMIT, commit_float],
		[Controls.SPRITE_ZOOM_IN, canvas.zoom_by.bind(1.25)],
		[Controls.SPRITE_ZOOM_OUT, canvas.zoom_by.bind(1.0 / 1.25)],
		[Controls.SPRITE_BRUSH_SMALLER, resize_brush.bind(-1)],
		[Controls.SPRITE_BRUSH_BIGGER, resize_brush.bind(1)],
		[Controls.SPRITE_NUDGE_LEFT, nudge.bind(-1, 0)],
		[Controls.SPRITE_NUDGE_RIGHT, nudge.bind(1, 0)],
		[Controls.SPRITE_NUDGE_UP, nudge.bind(0, -1)],
		[Controls.SPRITE_NUDGE_DOWN, nudge.bind(0, 1)],
	]

func drop_float_or_deselect() -> void:
	if has_float():
		cancel_float()
	else:
		deselect()

func drop_float_or_clear() -> void:
	if has_float():
		cancel_float()
	else:
		clear_selected_region()

func resize_brush(step: int) -> void:
	brush_size = maxi(1, brush_size - 1) if step < 0 else mini(16, brush_size + 1)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or not is_visible_in_tree() or typing():
		return

	for binding in key_bindings():
		if Controls.pressed(event, binding[0], true):
			binding[1].call()
			get_viewport().set_input_as_handled()
			return

func request_load() -> void:
	if host_files:
		load_requested.emit()
	else:
		show_dialog(FileDialog.FILE_MODE_OPEN_FILE)

func request_save() -> void:
	if host_files:
		save_requested.emit()
	else:
		show_dialog(FileDialog.FILE_MODE_SAVE_FILE)

func show_dialog(mode: FileDialog.FileMode) -> void:
	file_dialog.file_mode = mode
	file_dialog.title = "Save sprite" if mode == FileDialog.FILE_MODE_SAVE_FILE else "Load sprite"
	if mode == FileDialog.FILE_MODE_SAVE_FILE:
		file_dialog.current_file = filename + ".png"
	file_dialog.popup_centered()

static func mask_path(path: String) -> String:
	return path.get_basename() + "_mask.png"

# where a res:// or user:// path lives on disk, other paths pass through
static func disk_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path

func on_file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		save_to(path)
	else:
		load_from(path)

# writes the color png and, when the document has cells, the _mask.png next to
# it, a stale mask file goes away. path is res:// or absolute
func save_to(path: String) -> bool:
	commit_float()

	if doc.width <= 0 or doc.height <= 0:
		return false

	if path.get_extension().to_lower() != "png":
		path += ".png"

	var on_disk := disk_path(path)
	var err := doc.to_color_image().save_png(on_disk)
	if err != OK:
		message = "could not save " + path.get_file()
		return false

	if doc.has_mask():
		err = doc.to_mask_image().save_png(mask_path(on_disk))
	elif FileAccess.file_exists(mask_path(on_disk)):
		DirAccess.remove_absolute(mask_path(on_disk))

	filename = path.get_file().get_basename()
	name_edit.text = filename
	file_path = path
	message = "saved " + path.get_file()
	saved.emit(path)
	return err == OK

func load_from(path: String) -> bool:
	var on_disk := disk_path(path)
	if not FileAccess.file_exists(on_disk):
		message = "could not load " + path.get_file()
		return false

	var color := Image.load_from_file(on_disk)
	if color == null:
		message = "could not load " + path.get_file()
		return false

	var mask: Image = null
	if FileAccess.file_exists(mask_path(on_disk)):
		mask = Image.load_from_file(mask_path(on_disk))

	reset_float()
	doc.from_images(color, mask)
	palette_dirty = true
	filename = path.get_file().get_basename()
	name_edit.text = filename
	size_x.value = doc.width
	size_y.value = doc.height
	canvas.fit_to_view()
	file_path = path
	message = "loaded " + path.get_file()
	loaded.emit(path)
	return true
