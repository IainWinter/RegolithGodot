@tool
extends HBoxContainer

# the Pipes toolbar RegolithPipesPlugin puts in the 2D editor's menu bar
# while a PipeFrame is selected: layer (back/front), brush, the gauge radius
# the Gauge brush paints, and the Auto fill / Clear / Regenerate actions.
# holds no frame, the plugin reads `layer`, `tool` and `gauge` and listens
# to the action signals

signal auto_fill_pressed
signal clear_pressed
signal regenerate_pressed
signal tool_changed(tool: int)
signal layer_changed(layer: int)

enum Tool { SELECT, PIPE, ERASE, GAUGE }

const TOOL_NAMES: PackedStringArray = ["Select", "Pipe", "Erase", "Gauge"]
const TOOL_TIPS: PackedStringArray = [
	"Move and resize the zone with the normal handles, no painting",
	"Left drag paints a run of pipe cells, right click erases, Shift-click an edge between two cells toggles that connection",
	"Left drag erases cells",
	"Left click sets the pipe radius of a painted cell to the gauge value, right click resets it to the layer default",
]

var layer_pick: OptionButton
var tool_buttons: Array[Button] = []
var gauge_spin: SpinBox
var fill_button: Button
var clear_button: Button
var regen_button: Button
var status: Label

var tool := Tool.SELECT
var layer := 1
var gauge := 4.0

func _ready() -> void:
	add_child(VSeparator.new())

	var title := Label.new()
	title.text = "Pipes"
	add_child(title)

	layer_pick = OptionButton.new()
	for i in PipeLayout.LAYER_NAMES.size():
		layer_pick.add_item(PipeLayout.LAYER_NAMES[i], i)

	layer_pick.select(layer)
	layer_pick.tooltip_text = "Which layout layer the brushes edit"
	layer_pick.item_selected.connect(func(index: int):
		layer = index
		layer_changed.emit(layer))
	add_child(layer_pick)

	var group := ButtonGroup.new()
	for i in TOOL_NAMES.size():
		var button := Button.new()
		button.text = TOOL_NAMES[i]
		button.tooltip_text = TOOL_TIPS[i]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == tool
		button.pressed.connect(_make_tool_setter(i))
		add_child(button)
		tool_buttons.append(button)

	gauge_spin = SpinBox.new()
	gauge_spin.min_value = PipeLayout.GAUGE_MIN
	gauge_spin.max_value = PipeLayout.GAUGE_MAX
	gauge_spin.step = 0.5
	gauge_spin.value = gauge
	gauge_spin.prefix = "r"
	gauge_spin.tooltip_text = "Pipe radius in pixels the Gauge brush paints"
	gauge_spin.value_changed.connect(func(value: float): gauge = value)
	add_child(gauge_spin)

	add_child(VSeparator.new())

	fill_button = Button.new()
	fill_button.text = "Auto fill"
	fill_button.tooltip_text = "WFC the empty cells of this layer around the painted ones and bake them into the layout"
	fill_button.pressed.connect(func(): auto_fill_pressed.emit())
	add_child(fill_button)

	clear_button = Button.new()
	clear_button.text = "Clear"
	clear_button.tooltip_text = "Erase every cell of this layer"
	clear_button.pressed.connect(func(): clear_pressed.emit())
	add_child(clear_button)

	regen_button = Button.new()
	regen_button.text = "Regenerate"
	regen_button.tooltip_text = "Generate the texture again now"
	regen_button.pressed.connect(func(): regenerate_pressed.emit())
	add_child(regen_button)

	status = Label.new()
	status.modulate = Color(1, 1, 1, 0.6)
	add_child(status)

func _make_tool_setter(index: int) -> Callable:
	return func():
		tool = index as Tool
		tool_changed.emit(tool)

func set_tool(value: int) -> void:
	tool = value as Tool
	if value >= 0 and value < tool_buttons.size():
		tool_buttons[value].set_pressed_no_signal(true)

# a line of state next to the buttons: layout mode, lattice, cells painted
func show_frame(frame: PipeFrame) -> void:
	if frame == null:
		status.text = ""
		return

	var g := frame.grid_size()
	var painted := frame.layout.painted_count() if frame.layout != null else 0
	var mode_name: String = PipeFrame.LayoutMode.keys()[frame.placement].capitalize()
	status.text = "%s  %dx%d cells of %dpx  %d painted  %.0f ms" % [mode_name, g.x, g.y, frame.cell_size, painted, frame.last_generate_ms]
