extends CanvasLayer
class_name DebugPanel

# f3 panel over the game: the world's monitors, pause and single step, and
# the debug line switches. every debug name gets a check and a color, layers
# tint whatever is drawn on them. the panel shows the scene's
# RegolithDebugDraw while it is open, making one next to the world when the
# scene has none

var world: RegolithWorld
var draw: RegolithDebugDraw

var stats: Label
var pause_check: CheckBox
var name_checks: Array[CheckBox] = []
var layer_checks: Array[CheckBox] = []

func _init(target: RegolithWorld) -> void:
	world = target
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	draw = find_draw()
	draw.visible = true
	build()

func _exit_tree() -> void:
	if is_instance_valid(draw):
		draw.visible = false

func find_draw() -> RegolithDebugDraw:
	var found := get_tree().get_first_node_in_group("regolith_debug_draw") as RegolithDebugDraw

	if found:
		return found

	found = RegolithDebugDraw.new()
	found.name = "DebugDraw"
	world.add_child(found)
	return found

func _process(_delta: float) -> void:
	stats.text = "fps %d   sprites %d   joints %d   contacts %d   ropes %d\ncommit %.2f ms   physics %.2f ms" % [
		Engine.get_frames_per_second(),
		world.get_sprite_count(),
		world.get_joint_count(),
		world.get_contact_count(),
		world.get_rope_count(),
		world.get_commit_time_ms(),
		world.get_physics_time_ms(),
	]

	pause_check.set_pressed_no_signal(get_tree().paused)

func build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	stats = Label.new()
	box.add_child(stats)

	var tick := HBoxContainer.new()
	box.add_child(tick)

	pause_check = CheckBox.new()
	pause_check.text = "Pause"
	pause_check.toggled.connect(func(on: bool): get_tree().paused = on)
	tick.add_child(pause_check)

	var step := Button.new()
	step.text = "Step"
	step.pressed.connect(step_once)
	tick.add_child(step)

	box.add_child(HSeparator.new())

	var lines := HBoxContainer.new()
	box.add_child(lines)

	var all_on := Button.new()
	all_on.text = "All on"
	all_on.pressed.connect(func(): set_all_names(true))
	lines.add_child(all_on)

	var all_off := Button.new()
	all_off.text = "All off"
	all_off.pressed.connect(func(): set_all_names(false))
	lines.add_child(all_off)

	var width := SpinBox.new()
	width.min_value = -1
	width.max_value = 8
	width.step = 0.5
	width.value = draw.line_width
	width.prefix = "width"
	width.value_changed.connect(func(value: float): draw.line_width = value)
	lines.add_child(width)

	var layers := HBoxContainer.new()
	box.add_child(layers)

	var layer_names := ["Default", "A", "B"]

	for i in draw.get_layer_count():
		var check := CheckBox.new()
		check.text = layer_names[i] if i < layer_names.size() else str(i)
		check.button_pressed = draw.is_layer_enabled(i)
		check.toggled.connect(func(on: bool): draw.set_layer_enabled(i, on))
		layers.add_child(check)
		layer_checks.append(check)

		var tint := ColorPickerButton.new()
		tint.color = draw.get_layer_tint(i)
		tint.edit_alpha = false
		tint.custom_minimum_size = Vector2(24, 0)
		tint.color_changed.connect(func(color: Color): draw.set_layer_tint(i, color))
		layers.add_child(tint)

	box.add_child(HSeparator.new())

	for i in draw.get_name_count():
		var row := HBoxContainer.new()
		box.add_child(row)

		var check := CheckBox.new()
		check.text = draw.get_name_label(i).to_lower().replace("_", " ")
		check.button_pressed = draw.is_name_enabled(i)
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.toggled.connect(func(on: bool): draw.set_name_enabled(i, on))
		row.add_child(check)
		name_checks.append(check)

		var color := ColorPickerButton.new()
		color.color = draw.get_name_color(i)
		color.edit_alpha = false
		color.custom_minimum_size = Vector2(24, 0)
		color.color_changed.connect(func(value: Color): draw.set_name_color(i, value))
		row.add_child(color)

func set_all_names(on: bool) -> void:
	draw.set_all_names_enabled(on)

	for check in name_checks:
		check.set_pressed_no_signal(on)

func step_once() -> void:
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().paused = true
