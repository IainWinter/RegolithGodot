@tool
extends VBoxContainer

# the Debug Draw dock: a check and a color per debug name, grouped by family,
# the three layer tints, and the master visible switch. holds the settings in
# the same dictionary shape RegolithDebugDraw.apply_settings takes and saves
# them per user in user://. emits changed on every edit

signal changed(settings: Dictionary)

const SAVE_PATH := "user://regolith_debug_dock.cfg"
const SECTIONS := ["names", "colors", "layers", "tints"]

var labels: Array[String] = []
var layer_labels: Array[String] = ["DEFAULT", "A", "B"]
var settings: Dictionary = {}

var name_checks: Dictionary = {}
var name_colors: Dictionary = {}
var layer_checks: Dictionary = {}
var layer_colors: Dictionary = {}
var visible_check: CheckBox

func _ready() -> void:
	settings = defaults()
	load_saved()
	build()

# a fresh drawer knows every label and the engine's default colors
func defaults() -> Dictionary:
	var draw := RegolithDebugDraw.new()
	var out: Dictionary = draw.get_settings()
	out["visible"] = false

	labels.clear()
	for i in draw.get_name_count():
		labels.append(draw.get_name_label(i))

	draw.free()
	return out

func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return

	settings["visible"] = cfg.get_value("draw", "visible", settings["visible"])

	for section in SECTIONS:
		for key in settings[section]:
			settings[section][key] = cfg.get_value(section, key, settings[section][key])

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("draw", "visible", settings["visible"])

	for section in SECTIONS:
		for key in settings[section]:
			cfg.set_value(section, key, settings[section][key])

	cfg.save(SAVE_PATH)

func edited() -> void:
	save()
	changed.emit(settings)

func build() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var top := HBoxContainer.new()
	add_child(top)

	visible_check = CheckBox.new()
	visible_check.text = "Show lines"
	visible_check.button_pressed = settings["visible"]
	visible_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visible_check.toggled.connect(func(on: bool):
		settings["visible"] = on
		edited())
	top.add_child(visible_check)

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

	var layer_box := fold(box, "Layers")

	for key in layer_labels:
		layer_box.add_child(switch_row(key.capitalize(), "layers", "tints", key, layer_checks, layer_colors))

	# families with two or more names fold together, singles stay flat
	var families := {}
	for label in labels:
		var family := family_of(label)
		if family != "":
			families[family] = families.get(family, 0) + 1

	var groups := {}
	for label in labels:
		var family := family_of(label)
		var parent: Node = box
		var text := label.capitalize()

		if family != "" and families[family] >= 2:
			if not groups.has(family):
				groups[family] = fold(box, family.capitalize())
			parent = groups[family]
			text = label.substr(family.length() + 1).capitalize()

		parent.add_child(switch_row(text, "names", "colors", label, name_checks, name_colors))

func fold(parent: Node, title: String) -> VBoxContainer:
	var container := FoldableContainer.new()
	container.title = title
	parent.add_child(container)

	var inner := VBoxContainer.new()
	container.add_child(inner)
	return inner

func family_of(label: String) -> String:
	var cut := label.find("_")
	return "" if cut < 0 else label.substr(0, cut)

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

	var pick := ColorPickerButton.new()
	pick.color = settings[color_section][key]
	pick.edit_alpha = false
	pick.custom_minimum_size = Vector2(28, 0)
	pick.color_changed.connect(func(color: Color):
		settings[color_section][key] = color
		edited())
	row.add_child(pick)
	colors[key] = pick

	return row

func set_all(on: bool) -> void:
	for label in labels:
		settings["names"][label] = on
		name_checks[label].set_pressed_no_signal(on)
	edited()

func reset_defaults() -> void:
	settings = defaults()
	visible_check.set_pressed_no_signal(false)

	for label in labels:
		name_checks[label].set_pressed_no_signal(settings["names"][label])
		name_colors[label].color = settings["colors"][label]

	for key in layer_labels:
		layer_checks[key].set_pressed_no_signal(settings["layers"][key])
		layer_colors[key].color = settings["tints"][key]

	edited()
