@tool
extends VBoxContainer

# the Debug Draw dock: a check and a color per debug name, grouped by family,
# and the three layer tints. holds the settings in the same dictionary shape
# RegolithDebugDraw.apply_settings takes and saves them per user in user://.
# emits changed on every edit.
#
# section chips at the top gate which family folds are visible in the panel —
# per-name checkboxes inside each fold still control what actually draws

signal changed(settings: Dictionary)

const SAVE_PATH := "user://regolith_debug_dock.cfg"
const SECTIONS := ["names", "colors", "layers", "tints"]
const LAYERS_FAMILY := "LAYERS"
const GENERAL_FAMILY := "GENERAL"

var labels: Array[String] = []
var layer_labels: Array[String] = ["DEFAULT", "A", "B"]
var settings: Dictionary = {}

var name_checks: Dictionary = {}
var name_colors: Dictionary = {}
var layer_checks: Dictionary = {}
var layer_colors: Dictionary = {}

# per-label family assignment and per-family member counts, computed once from labels
var _label_family: Dictionary = {}
var _family_counts: Dictionary = {}

# family reveal state — which family sections are shown in the panel
var shown_families: Dictionary = {}
var family_folds: Dictionary = {}
var family_chips: Dictionary = {}

func _ready() -> void:
	settings = defaults()
	load_saved()
	build()

# a fresh drawer knows every label and the engine's default colors
func defaults() -> Dictionary:
	var draw := RegolithDebugDraw.new()
	var out: Dictionary = draw.get_settings()
	# visibility is now driven purely by the per-name checkboxes
	out.erase("visible")

	labels.clear()
	for i in draw.get_name_count():
		labels.append(draw.get_name_label(i))

	draw.free()
	return out

func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return

	for section in SECTIONS:
		for key in settings[section]:
			settings[section][key] = cfg.get_value(section, key, settings[section][key])

	if cfg.has_section("shown_families"):
		for family in cfg.get_section_keys("shown_families"):
			shown_families[family] = cfg.get_value("shown_families", family, false)

func save() -> void:
	var cfg := ConfigFile.new()

	for section in SECTIONS:
		for key in settings[section]:
			cfg.set_value(section, key, settings[section][key])

	for family in shown_families:
		cfg.set_value("shown_families", family, shown_families[family])

	cfg.save(SAVE_PATH)

func edited() -> void:
	save()
	changed.emit(settings)

func build() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	compute_families()

	var top := HBoxContainer.new()
	add_child(top)

	var all_on := Button.new()
	all_on.text = "All"
	all_on.tooltip_text = "Enable every name"
	all_on.pressed.connect(func(): set_all(true))
	top.add_child(all_on)

	var all_off := Button.new()
	all_off.text = "None"
	all_off.tooltip_text = "Disable every name"
	all_off.pressed.connect(func(): set_all(false))
	top.add_child(all_off)

	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Back to the engine defaults"
	reset.pressed.connect(reset_defaults)
	top.add_child(reset)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	# each family's header IS a checkbox — checking it reveals the per-name
	# rows below, unchecking hides them. no separate chip row, no fold arrow
	for family in family_order():
		var header := CheckBox.new()
		header.text = family_title(family)
		header.button_pressed = shown_families.get(family, false)
		# helper wraps the capture so each header binds its own family,
		# avoiding the shared-loop-variable trap for closures inside for loops
		header.toggled.connect(make_family_toggler(family))
		box.add_child(header)
		family_chips[family] = header

		var indent := MarginContainer.new()
		indent.add_theme_constant_override("margin_left", 16)
		indent.visible = shown_families.get(family, false)
		box.add_child(indent)

		var inner := VBoxContainer.new()
		indent.add_child(inner)
		family_folds[family] = {"fold": indent, "inner": inner}

	for key in layer_labels:
		family_folds[LAYERS_FAMILY]["inner"].add_child(
			switch_row(key.capitalize(), "layers", "tints", key, layer_checks, layer_colors))

	for label in labels:
		var family: String = _label_family[label]
		var text := label_text(label, family)
		family_folds[family]["inner"].add_child(
			switch_row(text, "names", "colors", label, name_checks, name_colors))

# singleton labels (no underscore, or the only member of their prefix) collapse
# into GENERAL so there aren't orphan rows floating outside any fold
func compute_families() -> void:
	_family_counts.clear()
	for label in labels:
		var cut := label.find("_")
		if cut >= 0:
			var f := label.substr(0, cut)
			_family_counts[f] = _family_counts.get(f, 0) + 1

	_label_family.clear()
	for label in labels:
		var cut := label.find("_")
		var f := "" if cut < 0 else label.substr(0, cut)
		_label_family[label] = f if f != "" and _family_counts[f] >= 2 else GENERAL_FAMILY

func family_order() -> Array[String]:
	# Layers first, then families in the order names are declared in the engine,
	# GENERAL last if any singleton exists
	var out: Array[String] = [LAYERS_FAMILY]
	var seen := {LAYERS_FAMILY: true, GENERAL_FAMILY: true}
	var has_general := false
	for label in labels:
		var f: String = _label_family[label]
		if f == GENERAL_FAMILY:
			has_general = true
			continue
		if not seen.has(f):
			seen[f] = true
			out.append(f)
	if has_general:
		out.append(GENERAL_FAMILY)
	return out

func family_title(family: String) -> String:
	return family.capitalize()

func label_text(label: String, family: String) -> String:
	if family == GENERAL_FAMILY:
		return label.capitalize()
	return label.substr(family.length() + 1).capitalize()

func set_family_shown(family: String, on: bool) -> void:
	shown_families[family] = on
	if family_folds.has(family):
		family_folds[family]["fold"].visible = on
	save()

func make_family_toggler(family: String) -> Callable:
	return func(on: bool): set_family_shown(family, on)

# a check writing settings[on_section][key] and a color writing settings[color_section][key]
func switch_row(text: String, on_section: String, color_section: String, key: String, checks: Dictionary, colors: Dictionary) -> Control:
	var row := HBoxContainer.new()

	var check := CheckBox.new()
	check.text = text
	check.button_pressed = settings[on_section][key]
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.toggled.connect(func(on: bool):
		settings[on_section][key] = on
		edited())
	row.add_child(check)
	checks[key] = check

	# ColorPickerButton fills the swatch with a plain draw_rect so it can't be
	# rounded via a stylebox — build the swatch by hand as a Panel with a
	# rounded StyleBoxFlat, click to open a ColorPicker popup
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_END
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style := StyleBoxFlat.new()
	style.bg_color = settings[color_section][key]
	style.set_corner_radius_all(6)
	style.set_border_width_all(0)
	swatch.add_theme_stylebox_override("panel", style)

	var picker := ColorPicker.new()
	picker.color = settings[color_section][key]
	picker.edit_alpha = false
	picker.color_changed.connect(func(color: Color):
		style.bg_color = color
		settings[color_section][key] = color
		edited())

	var popup := PopupPanel.new()
	popup.add_child(picker)
	swatch.add_child(popup)

	swatch.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			popup.popup(Rect2i(swatch.get_screen_position() + Vector2(0, swatch.size.y), Vector2i.ZERO)))

	row.add_child(swatch)
	colors[key] = {"style": style, "picker": picker}

	return row

func set_swatch_color(entry: Dictionary, color: Color) -> void:
	entry["style"].bg_color = color
	entry["picker"].color = color

func set_all(on: bool) -> void:
	for label in labels:
		settings["names"][label] = on
		name_checks[label].set_pressed_no_signal(on)
	edited()

func reset_defaults() -> void:
	settings = defaults()

	for label in labels:
		name_checks[label].set_pressed_no_signal(settings["names"][label])
		set_swatch_color(name_colors[label], settings["colors"][label])

	for key in layer_labels:
		layer_checks[key].set_pressed_no_signal(settings["layers"][key])
		set_swatch_color(layer_colors[key], settings["tints"][key])

	edited()
