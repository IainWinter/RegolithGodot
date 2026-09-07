extends CanvasLayer
class_name SpriteEditor

# in game pixel editor, a port of the old imgui SpriteEditorTool built from
# Control nodes. edits a SpriteDocument, applies it to a RegolithSprite in the
# world, saves and loads png plus _mask.png pairs. runs with the tree paused

enum Tool { PENCIL, ERASER, FILL, PICKER, SELECT, MOVE, RECT, LINE }

const TOOL_LABELS := [["Pencil", "B"], ["Eraser", "E"], ["Fill", "G"], ["Picker", "I"], ["Select", "M"], ["Move", "V"], ["Rect", "R"], ["Line", "L"]]
const MODE_LABELS := ["Graphics", "Mask", "Class", "Emission"]
const SIDEBAR_WIDTH := 340
const ACCENT := Color8(90, 150, 255)

static var clipboard := {}

@export var target: RegolithSprite

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
var color_picker: ColorPicker
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
var apply_button: Button
var paste_all_check: CheckBox
var file_dialog: FileDialog
var message := ""

signal closed

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	build_ui()

	if target:
		open(target)
	else:
		canvas.fit_to_view()

func open(sprite: RegolithSprite) -> void:
	target = sprite

	if target and target.is_loaded():
		doc.from_images(target.get_color_image(), target.get_mask_image())
		if target.texture:
			filename = target.texture.resource_path.get_file().get_basename()
	else:
		doc.resize(32, 32)
		doc.clear()
		doc.clear_history()

	name_edit.text = filename
	size_x.value = doc.width
	size_y.value = doc.height
	apply_button.disabled = target == null
	canvas.fit_to_view()
	sync_ui()

func apply_to_target() -> void:
	if target == null:
		return

	commit_float()
	target.load_from_images(doc.to_color_image(), doc.to_mask_image() if doc.has_mask() else null)
	message = "applied to " + target.name

func close() -> void:
	closed.emit()
	queue_free()

# ui

func build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.color = Color8(30, 31, 36)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 0)
	root.add_child(split)

	split.add_child(build_sidebar())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	split.add_child(right)

	right.add_child(build_toolbar())

	canvas = SpriteCanvas.new()
	canvas.editor = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(canvas)

	var status_panel := PanelContainer.new()
	right.add_child(status_panel)
	var status_row := HBoxContainer.new()
	status_panel.add_child(status_row)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 13)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(status)
	status_row.add_child(action("-", func(): canvas.zoom_by(1.0 / 1.25), false))
	status_row.add_child(action("+", func(): canvas.zoom_by(1.25), false))
	status_row.add_child(action("Fit", func(): canvas.fit_to_view(), false))
	zoom_label = Label.new()
	zoom_label.custom_minimum_size.x = 56
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_row.add_child(zoom_label)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png ; PNG"])
	file_dialog.size = Vector2i(760, 500)
	file_dialog.current_dir = ProjectSettings.globalize_path("res://art/sprites")
	file_dialog.file_selected.connect(on_file_selected)
	root.add_child(file_dialog)

	for button in root.find_children("*", "BaseButton", true, false):
		button.focus_mode = Control.FOCUS_NONE

	for slider in root.find_children("*", "Slider", true, false):
		slider.focus_mode = Control.FOCUS_NONE

	set_mode(doc.mode)
	sync_ui()

func build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = SIDEBAR_WIDTH

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	scroll.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Sprite"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	name_edit = LineEdit.new()
	name_edit.text = filename
	name_edit.custom_minimum_size.x = 150
	name_edit.placeholder_text = "name"
	name_edit.text_changed.connect(func(t): filename = t)
	head.add_child(name_edit)

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
		button.pressed.connect(func(): set_mode(i))
		modes.add_child(button)
		mode_buttons.append(button)

	# graphics
	var graphics := VBoxContainer.new()
	box.add_child(graphics)
	graphics.add_child(section("Color"))
	color_picker = ColorPicker.new()
	color_picker.edit_alpha = true
	color_picker.presets_visible = false
	color_picker.sampler_visible = false
	color_picker.can_add_swatches = false
	color_picker.color_modes_visible = false
	color_picker.color = doc.paint_color
	color_picker.color_changed.connect(func(c): doc.paint_color = c)
	graphics.add_child(color_picker)
	mode_sections.append(graphics)

	# mask
	var mask := VBoxContainer.new()
	box.add_child(mask)
	mask.add_child(section("Mask Type"))
	var type_grid := GridContainer.new()
	type_grid.columns = 2
	mask.add_child(type_grid)
	var type_group := ButtonGroup.new()
	for i in SpriteDocument.TYPE_COUNT:
		var button := swatch_button(SpriteDocument.TYPE_NAMES[i], SpriteDocument.TYPE_DISPLAY[i], type_group)
		button.pressed.connect(func(): doc.paint_type = i)
		type_grid.add_child(button)
		type_buttons.append(button)
	mode_sections.append(mask)

	# class
	var armor := VBoxContainer.new()
	box.add_child(armor)
	armor.add_child(section("Armor Class"))
	var class_grid := GridContainer.new()
	class_grid.columns = 2
	armor.add_child(class_grid)
	var class_group := ButtonGroup.new()
	for i in SpriteDocument.CLASS_COUNT:
		var button := swatch_button("Class %d" % i, SpriteDocument.CLASS_DISPLAY[i], class_group)
		button.pressed.connect(func(): doc.paint_class = i)
		class_grid.add_child(button)
		class_buttons.append(button)
	mode_sections.append(armor)

	# emission
	var emission := VBoxContainer.new()
	box.add_child(emission)
	emission.add_child(section("Emission"))
	var hint := Label.new()
	hint.text = "Paint cells that glow. Left adds, right erases. Core cells always glow."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
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
	box.add_child(check("Filled Rect", rect_filled, func(on): rect_filled = on))
	paste_all_check = check("Paste All Layers", doc.paste_all_layers, func(on): doc.paste_all_layers = on)
	box.add_child(paste_all_check)

	box.add_child(section("Canvas"))
	var size_row := HBoxContainer.new()
	box.add_child(size_row)
	var size_label := Label.new()
	size_label.text = "Size"
	size_label.custom_minimum_size.x = 56
	size_row.add_child(size_label)
	size_x = spin(1, SpriteDocument.MAX_SIZE, doc.width)
	size_y = spin(1, SpriteDocument.MAX_SIZE, doc.height)
	size_row.add_child(size_x)
	size_row.add_child(size_y)

	var canvas_row := HBoxContainer.new()
	box.add_child(canvas_row)
	canvas_row.add_child(action("Resize", func(): commit_float(); doc.resize_recorded(int(size_x.value), int(size_y.value)); canvas.fit_to_view()))
	canvas_row.add_child(action("Clear", func(): commit_float(); doc.clear_recorded()))
	canvas_row.add_child(action("Fit", func(): canvas.fit_to_view()))

	box.add_child(section("File"))
	var files := HBoxContainer.new()
	box.add_child(files)
	files.add_child(action("Load", func(): show_dialog(FileDialog.FILE_MODE_OPEN_FILE)))
	files.add_child(action("Save", func(): show_dialog(FileDialog.FILE_MODE_SAVE_FILE)))

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	box.add_child(spacer)

	var finish := HBoxContainer.new()
	box.add_child(finish)
	apply_button = action("Apply", apply_to_target)
	apply_button.disabled = target == null
	finish.add_child(apply_button)
	finish.add_child(action("Close", close))

	return panel

func build_toolbar() -> Control:
	var panel := PanelContainer.new()
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
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
	brush_label.custom_minimum_size.x = 64
	bar.add_child(brush_label)
	brush_slider = HSlider.new()
	brush_slider.min_value = 1
	brush_slider.max_value = 16
	brush_slider.step = 1
	brush_slider.value = brush_size
	brush_slider.custom_minimum_size.x = 100
	brush_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brush_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brush_slider.value_changed.connect(func(v): brush_size = int(v))
	bar.add_child(brush_slider)

	return panel

func section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(1, 1, 1, 0.6)
	return label

func labeled(text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 56
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

	var shown := color if color.a > 0.0 else Color8(40, 40, 46)
	var lum := 0.299 * shown.r + 0.587 * shown.g + 0.114 * shown.b
	button.add_theme_color_override("font_color", Color8(20, 20, 24) if lum > 0.5 else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color8(20, 20, 24) if lum > 0.5 else Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color8(20, 20, 24) if lum > 0.5 else Color.WHITE)

	button.add_theme_stylebox_override("normal", swatch_style(shown, Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("hover", swatch_style(shown.lightened(0.2), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("pressed", swatch_style(shown, ACCENT))
	button.add_theme_stylebox_override("hover_pressed", swatch_style(shown.lightened(0.2), ACCENT))
	return button

func swatch_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(6)
	return style

func _process(_delta: float) -> void:
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

	if color_picker.color != doc.paint_color:
		color_picker.color = doc.paint_color

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
	var owner := root.get_viewport().gui_get_focus_owner()
	return owner is LineEdit or owner is TextEdit

# modes and tools

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

# canvas interaction, mirrors the old canvas_input

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
				sel_start_active = Input.is_key_pressed(KEY_SHIFT) and doc.selection_active
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

# selection, clipboard and floating region

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

# keyboard

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or typing():
		return

	var key: Key = event.keycode
	var ctrl: bool = event.ctrl_pressed or event.meta_pressed
	var handled := true

	if ctrl:
		match key:
			KEY_Z:
				if event.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y: redo()
			KEY_A: select_all()
			KEY_C: copy_selection()
			KEY_X: cut_selection()
			KEY_V: paste_clipboard()
			KEY_D: duplicate_selection()
			KEY_0: canvas.fit_to_view()
			_: handled = false
	else:
		match key:
			KEY_B: set_tool(Tool.PENCIL)
			KEY_E: set_tool(Tool.ERASER)
			KEY_G: set_tool(Tool.FILL)
			KEY_I: set_tool(Tool.PICKER)
			KEY_M: set_tool(Tool.SELECT)
			KEY_V: set_tool(Tool.MOVE)
			KEY_R: set_tool(Tool.RECT)
			KEY_L: set_tool(Tool.LINE)
			KEY_F: canvas.fit_to_view()
			KEY_ESCAPE:
				if has_float():
					cancel_float()
				else:
					deselect()
			KEY_DELETE, KEY_BACKSPACE:
				if has_float():
					cancel_float()
				else:
					clear_selected_region()
			KEY_ENTER, KEY_KP_ENTER: commit_float()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: canvas.zoom_by(1.25)
			KEY_MINUS, KEY_KP_SUBTRACT: canvas.zoom_by(1.0 / 1.25)
			KEY_BRACKETLEFT: brush_size = maxi(1, brush_size - 1)
			KEY_BRACKETRIGHT: brush_size = mini(16, brush_size + 1)
			KEY_LEFT: nudge(-1, 0)
			KEY_RIGHT: nudge(1, 0)
			KEY_UP: nudge(0, -1)
			KEY_DOWN: nudge(0, 1)
			_: handled = false

	if handled:
		root.get_viewport().set_input_as_handled()

# files

func show_dialog(mode: FileDialog.FileMode) -> void:
	file_dialog.file_mode = mode
	file_dialog.title = "Save sprite" if mode == FileDialog.FILE_MODE_SAVE_FILE else "Load sprite"
	if mode == FileDialog.FILE_MODE_SAVE_FILE:
		file_dialog.current_file = filename + ".png"
	file_dialog.popup_centered()

static func mask_path(path: String) -> String:
	return path.get_basename() + "_mask.png"

func on_file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		save_to(path)
	else:
		load_from(path)

func save_to(path: String) -> bool:
	commit_float()

	if doc.width <= 0 or doc.height <= 0:
		return false

	if path.get_extension().to_lower() != "png":
		path += ".png"

	var err := doc.to_color_image().save_png(path)
	if err != OK:
		message = "could not save " + path.get_file()
		return false

	if doc.has_mask():
		err = doc.to_mask_image().save_png(mask_path(path))
	elif FileAccess.file_exists(mask_path(path)):
		DirAccess.remove_absolute(mask_path(path))

	filename = path.get_file().get_basename()
	name_edit.text = filename
	message = "saved " + path.get_file()
	return err == OK

func load_from(path: String) -> bool:
	var color := Image.load_from_file(path)
	if color == null:
		message = "could not load " + path.get_file()
		return false

	var mask: Image = null
	if FileAccess.file_exists(mask_path(path)):
		mask = Image.load_from_file(mask_path(path))

	reset_float()
	doc.from_images(color, mask)
	filename = path.get_file().get_basename()
	name_edit.text = filename
	size_x.value = doc.width
	size_y.value = doc.height
	canvas.fit_to_view()
	message = "loaded " + path.get_file()
	return true
