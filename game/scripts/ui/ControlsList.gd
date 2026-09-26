extends ScrollContainer
class_name ControlsList

# the controls list, every binding from Controls.describe() under a small
# uppercase label per group: the bindings on the left in the accent color,
# what they do on the right. shown by the pause menu's Controls page and
# the F3 debug panel. `groups` limits it to some groups, empty is all

const BINDING_WIDTH := 150
const GROUP_GAP := 6

var groups: Array[String] = []
var column: VBoxContainer
# action name -> the row, for tests and focus
var rows := {}

func _init(only: Array[String] = []) -> void:
	groups = only
	name = "ControlsList"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	build()

func build() -> void:
	if column:
		column.queue_free()

	rows.clear()
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	add_child(column)

	var group := ""

	for row in Controls.describe():
		if not groups.is_empty() and not groups.has(row["group"]):
			continue

		if row["group"] != group:
			group = row["group"]
			column.add_child(group_label(group, column.get_child_count() > 0))

		var line := binding_row(row)
		rows[row["action"]] = line
		column.add_child(line)

func group_label(text: String, gap: bool) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
	label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)

	if gap:
		label.add_theme_constant_override("line_spacing", 0)
		label.custom_minimum_size.y = PixelTheme.SMALL_FONT_SIZE + GROUP_GAP * 2
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	return label

func binding_row(row: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = String(row["action"])

	var keys := Label.new()
	keys.name = "Bindings"
	var text := Controls.bindings_text(row)
	keys.text = text if text != "" else "-"
	keys.custom_minimum_size.x = BINDING_WIDTH
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.add_theme_color_override("font_color", PixelTheme.ACCENT)
	line.add_child(keys)

	var what := Label.new()
	what.name = "Description"
	what.text = row["description"]
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.add_theme_color_override("font_color", PixelTheme.TEXT)
	line.add_child(what)

	return line
