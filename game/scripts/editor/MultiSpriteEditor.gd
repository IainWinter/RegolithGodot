@tool
extends Control
class_name MultiSpriteEditor

# lays out several sprites and pins them together with joints, writing the
# json a MultiSprite node spawns from. works on a MultiSpriteDocument, never a
# live world, so the same Control sits in the Godot editor's Sprites screen
# (regolith_sprite_editor addon) and in the game (MultiSpriteEditorWindow,
# which adds Play to drop the document into the running world). a host that
# owns the file dialogs sets host_files and answers the *_requested signals.
# looks come from PixelTheme

enum Mode { MOVE, JOINT }

const MODE_LABELS := [["Move", "V"], ["Joint", "J"]]
const SIDEBAR_WIDTH := 208
const ROTATE_STEP := PI / 16.0
const ACCENT := PixelTheme.ACCENT

# json to open on ready, empty starts a blank document
@export var path := ""
# the host pops its own file dialogs and answers the *_requested signals
@export var host_files := false
# the title bar close button, hosts that embed the editor for good hide it
@export var show_close := true

var doc := MultiSpriteDocument.new()
var canvas: MultiSpriteCanvas

var mode := Mode.MOVE
var selected := -1
var hover_sprite := -1
var hover_point := Vector2.ZERO
var joint_first := -1
var dragging := false
var drag_offset := Vector2.ZERO
var filename := "new_multisprite"
var file_path := ""
var message := ""

var mode_buttons: Array[Button] = []
var name_edit: LineEdit
var status: Label
var dynamic_check: CheckBox
var head_button: Button
var remove_button: Button
var close_button: Button
# hosts add their own buttons here (the game window's Play)
var host_actions: VBoxContainer
var file_dialog: FileDialog

signal closed
signal load_requested
signal save_requested
signal add_requested
signal saved(path: String)
signal loaded(path: String)

func _ready() -> void:
	build_ui()
	doc.changed.connect(on_doc_changed)

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

	canvas = MultiSpriteCanvas.new()
	canvas.editor = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.pressed.connect(on_pressed)
	canvas.dragged.connect(on_dragged)
	canvas.released.connect(on_released)
	canvas.hovered.connect(on_hovered)
	right.add_child(canvas)

	right.add_child(build_status())

	for button in find_children("*", "BaseButton", true, false):
		button.focus_mode = Control.FOCUS_NONE

	if not host_files:
		file_dialog = FileDialog.new()
		file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		file_dialog.size = Vector2i(720, 480)
		file_dialog.current_dir = ProjectSettings.globalize_path("res://game/images/multisprites")
		file_dialog.file_selected.connect(on_file_selected)
		add_child(file_dialog)

	sync_ui()

func build_title() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.INK, PixelTheme.LINE, 0, 0, 0, PixelTheme.BORDER, 8, 4))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)

	var title := Label.new()
	title.text = "MULTI SPRITE"
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
	close_button.tooltip_text = "Close"
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

	box.add_child(section("Mode"))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 2)
	box.add_child(modes)
	var group := ButtonGroup.new()
	for i in MODE_LABELS.size():
		var button := Button.new()
		button.text = MODE_LABELS[i][0]
		button.tooltip_text = "%s (%s)" % [MODE_LABELS[i][0], MODE_LABELS[i][1]]
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): set_mode(i))
		modes.add_child(button)
		mode_buttons.append(button)

	var hint := Label.new()
	hint.text = "Move: drag a sprite, Q / E rotate, Delete removes. Joint: click two sprites to pin them where you click second."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
	hint.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	box.add_child(hint)

	box.add_child(section("Sprites"))
	box.add_child(action("Add Sprite", request_add))
	remove_button = action("Remove Selected", remove_selected)
	box.add_child(remove_button)
	head_button = action("Set Head", func(): doc.set_head(-1 if doc.head == selected else selected))
	box.add_child(head_button)
	dynamic_check = check("Dynamic", true, set_selected_dynamic)
	box.add_child(dynamic_check)

	box.add_child(section("Joints"))
	box.add_child(action("Clear Joints", func(): joint_first = -1; doc.clear_joints()))

	host_actions = VBoxContainer.new()
	host_actions.add_theme_constant_override("separation", 4)
	box.add_child(host_actions)

	box.add_child(section("Canvas"))
	box.add_child(action("Clear All", clear_all))

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

	return panel

func section(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
	label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	return label

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

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		sync_ui()

func sync_ui() -> void:
	if status == null:
		return

	for i in mode_buttons.size():
		mode_buttons[i].set_pressed_no_signal(i == mode)

	var has_selection := selected >= 0 and selected < doc.sprites.size()
	remove_button.disabled = not has_selection
	head_button.disabled = not has_selection
	head_button.text = "Unset Head" if has_selection and doc.head == selected else "Set Head"
	dynamic_check.disabled = not has_selection
	if has_selection and dynamic_check.button_pressed != doc.sprites[selected]["dynamic"]:
		dynamic_check.set_pressed_no_signal(doc.sprites[selected]["dynamic"])

	status.text = status_text()

func status_text() -> String:
	var parts: Array[String] = []
	var units := doc.cells_to_units(hover_point)
	parts.append("%.2f, %.2f" % [units.x, units.y])
	parts.append("%d sprites" % doc.sprites.size())
	parts.append("%d joints" % doc.joints.size())

	if selected >= 0 and selected < doc.sprites.size():
		parts.append("#%d %s" % [selected, String(doc.sprites[selected]["texture"]).get_file()])

	if joint_first >= 0:
		parts.append("joint from #%d" % joint_first)

	if not message.is_empty():
		parts.append(message)

	return "   ".join(parts)

func on_doc_changed() -> void:
	if selected >= doc.sprites.size():
		selected = -1
	if joint_first >= doc.sprites.size():
		joint_first = -1
	if canvas:
		canvas.textures.clear()

func set_mode(next: int) -> void:
	mode = next as Mode
	joint_first = -1
	dragging = false

func typing() -> bool:
	var owner := get_viewport().gui_get_focus_owner()
	return owner is LineEdit or owner is TextEdit

# canvas input, points in cell space

func on_hovered(point: Vector2) -> void:
	hover_point = point
	hover_sprite = doc.sprite_at(point)

func on_pressed(point: Vector2, button: int) -> void:
	message = ""
	var hit := doc.sprite_at(point)

	if Controls.has_mouse_button(Controls.CANVAS_SECONDARY, button):
		joint_first = -1
		dragging = false
		if hit < 0:
			selected = -1
		return

	match mode:
		Mode.MOVE:
			selected = hit
			if hit >= 0:
				dragging = true
				drag_offset = doc.transform_of(hit).origin - point
		Mode.JOINT:
			if hit < 0:
				return
			selected = hit
			if joint_first < 0 or joint_first == hit:
				joint_first = hit
			else:
				add_joint(joint_first, hit, doc.cells_to_units(point))
				joint_first = -1

func on_dragged(point: Vector2) -> void:
	if not dragging or selected < 0 or selected >= doc.sprites.size():
		return

	doc.sprites[selected]["position"] = doc.cells_to_units(point + drag_offset)

func on_released(_point: Vector2, button: int) -> void:
	if Controls.has_mouse_button(Controls.CANVAS_PRIMARY, button) and dragging:
		dragging = false
		doc.touch()

func set_selected_dynamic(on: bool) -> void:
	if selected < 0 or selected >= doc.sprites.size():
		return

	doc.sprites[selected]["dynamic"] = on
	doc.touch()

func rotate_selected(steps: int) -> void:
	if selected < 0 or selected >= doc.sprites.size():
		return

	doc.sprites[selected]["rotation"] = wrapf(doc.sprites[selected]["rotation"] + steps * ROTATE_STEP, -PI, PI)
	doc.touch()

func key_bindings() -> Array:
	return [
		[Controls.MULTI_MOVE_MODE, set_mode.bind(Mode.MOVE)],
		[Controls.MULTI_JOINT_MODE, set_mode.bind(Mode.JOINT)],
		[Controls.MULTI_ROTATE_LEFT, rotate_selected.bind(-1)],
		[Controls.MULTI_ROTATE_RIGHT, rotate_selected.bind(1)],
		[Controls.MULTI_SET_HEAD, toggle_head],
		[Controls.MULTI_FIT, canvas.fit_to_view],
		[Controls.MULTI_DELETE, remove_selected],
		[Controls.MULTI_DESELECT, deselect],
	]

func toggle_head() -> void:
	doc.set_head(-1 if doc.head == selected else selected)

func deselect() -> void:
	joint_first = -1
	selected = -1

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or not is_visible_in_tree() or typing():
		return

	for binding in key_bindings():
		if Controls.pressed(event, binding[0], true):
			binding[1].call()
			get_viewport().set_input_as_handled()
			return

# document edits

func add_sprite(texture: String, position := Vector2.ZERO, rotation := 0.0, extra := {}) -> int:
	var i := doc.add_sprite(texture, position, rotation, extra)
	if i < 0:
		message = "could not load " + texture.get_file()
		return -1

	selected = i
	message = "added " + texture.get_file()
	if doc.sprites.size() == 1:
		canvas.fit_to_view()
	return i

# a new sprite lands right of the last one, or at the view center
func place_new_sprite(texture: String) -> int:
	var at := doc.cells_to_units(canvas.view_offset)
	if not doc.sprites.is_empty():
		var last := doc.sprites.size() - 1
		at = doc.sprites[last]["position"] + Vector2(doc.size_cells(last).x / float(MultiSpriteDocument.UNIT_CELLS), 0.0)
	return add_sprite(texture, at)

func remove_selected() -> void:
	if selected < 0 or selected >= doc.sprites.size():
		return

	doc.remove_sprite(selected)
	selected = -1
	joint_first = -1

func add_joint(a: int, b: int, point_units: Vector2) -> int:
	return doc.add_pin_joint(a, b, point_units)

func clear_all() -> void:
	selected = -1
	joint_first = -1
	dragging = false
	doc.clear()

# files

func request_load() -> void:
	if host_files:
		load_requested.emit()
	else:
		show_dialog(FileDialog.FILE_MODE_OPEN_FILE, "load")

func request_save() -> void:
	if host_files:
		save_requested.emit()
	else:
		show_dialog(FileDialog.FILE_MODE_SAVE_FILE, "save")

func request_add() -> void:
	if host_files:
		add_requested.emit()
	else:
		show_dialog(FileDialog.FILE_MODE_OPEN_FILE, "add")

func show_dialog(file_mode: FileDialog.FileMode, purpose: String) -> void:
	file_dialog.file_mode = file_mode
	file_dialog.set_meta("purpose", purpose)
	file_dialog.filters = PackedStringArray(["*.png ; PNG"] if purpose == "add" else ["*.json ; Multi sprite"])
	file_dialog.title = {"add": "Add sprite", "save": "Save multi sprite", "load": "Load multi sprite"}[purpose]
	if purpose == "save":
		file_dialog.current_file = filename + ".json"
	file_dialog.popup_centered()

func on_file_selected(selected_path: String) -> void:
	match file_dialog.get_meta("purpose"):
		"add": place_new_sprite(selected_path)
		"save": save_to(selected_path)
		"load": load_from(selected_path)

func save_to(save_path: String) -> bool:
	if save_path.get_extension().to_lower() != "json":
		save_path += ".json"

	if not doc.save_to(save_path):
		message = "could not save " + save_path.get_file()
		return false

	filename = save_path.get_file().get_basename()
	name_edit.text = filename
	file_path = save_path
	message = "saved " + save_path.get_file()
	saved.emit(save_path)
	return true

func load_from(load_path: String) -> bool:
	if not doc.load_from(load_path):
		message = "could not load " + load_path.get_file()
		return false

	selected = -1
	joint_first = -1
	dragging = false
	filename = load_path.get_file().get_basename()
	name_edit.text = filename
	file_path = load_path
	canvas.fit_to_view()
	message = "loaded " + load_path.get_file()
	loaded.emit(load_path)
	return true
