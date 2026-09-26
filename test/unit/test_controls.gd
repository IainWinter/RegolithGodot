extends GutTest

# Controls: the one table of bindings. every action lands in the InputMap,
# project.godot's [input] is generated from the table and agrees with it,
# no script tests a raw key or button outside Controls.gd, the doc lists
# every action, and the moved bindings still drive their behavior

const ControlsDoc := preload("res://game/scripts/core/GenerateControlsDoc.gd")
const InputMapWriter := preload("res://game/scripts/core/GenerateInputMap.gd")

# the folders whose scripts must ask Controls, and the files allowed a raw
# key or button name anyway, with the reason
const SCAN_DIRS := ["res://game", "res://addons/regolith_debug", "res://addons/regolith_pipes", "res://addons/regolith_scenario", "res://addons/regolith_sprite_editor"]
const ALLOWED := {
	"res://game/scripts/core/Controls.gd": "the table itself",
}

func key(code: Key, ctrl := false, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = true
	return event

func test_every_action_is_in_the_input_map() -> void:
	Controls.register()
	for action in Controls.actions():
		assert_true(InputMap.has_action(action), "in the input map: %s" % action)
		for event in Controls.events(action):
			assert_true(Controls.has_event(InputMap.action_get_events(action), event), "%s carries %s" % [action, event.as_text()])

func test_builtin_ui_actions_carry_the_listed_keys() -> void:
	for action in Controls.TABLE:
		if not Controls.is_builtin(action):
			continue
		assert_true(InputMap.has_action(action), "godot has %s" % action)
		for event in Controls.events(action):
			assert_true(Controls.has_event(InputMap.action_get_events(action), event), "%s carries %s as listed" % [action, event.as_text()])

func test_every_action_has_a_binding_group_and_description() -> void:
	for action in Controls.TABLE:
		var entry: Dictionary = Controls.TABLE[action]
		assert_true(Controls.GROUPS.has(entry["group"]), "%s has a known group" % action)
		assert_ne(String(entry["description"]), "", "%s is described" % action)
		assert_gt(Controls.events(action).size(), 0, "%s is bound" % action)

# the [input] actions as written in the file
static func project_actions(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var in_input := false
	for line in text.split("\n"):
		if line.begins_with("["):
			in_input = line == "[input]"
		elif in_input and line.contains("={"):
			out.append(line.get_slice("=", 0))
	return out

func test_project_godot_input_matches_the_table() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	var written := project_actions(text)
	var wanted := PackedStringArray()
	for action in Controls.actions():
		wanted.append(String(action))
	assert_eq(written, wanted, "project.godot [input] lists the table's actions in order, rerun game/scripts/core/GenerateInputMap.gd")

	for action in Controls.actions():
		var setting = ProjectSettings.get_setting("input/" + action)
		assert_not_null(setting, "project setting for %s" % action)
		if setting == null:
			continue
		var events: Array = setting["events"]
		var table := Controls.events(action)
		assert_eq(events.size(), table.size(), "%s binding count" % action)
		for event in table:
			assert_true(Controls.has_event(events, event), "project.godot %s has %s" % [action, event.as_text()])

	assert_eq(InputMapWriter.with_input_section(text), text, "regenerating changes nothing")

# a code line with its comment cut off
static func code_of(line: String) -> String:
	if line.strip_edges().begins_with("#"):
		return ""
	var hash := line.find(" # ")
	return line if hash < 0 else line.substr(0, hash)

static func scripts_under(dir: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		scripts_under(dir.path_join(sub), out)

func test_no_raw_keys_or_buttons_outside_controls() -> void:
	var raw := RegEx.create_from_string("\\b(KEY|MOUSE_BUTTON|JOY_BUTTON|JOY_AXIS)_[A-Z0-9_]+|\\.keycode\\b|physical_keycode|is_key_pressed|is_physical_key_pressed|is_mouse_button_pressed|is_joy_button_pressed|is_action(_just)?_(pressed|released)\\(\\s*&?\"|get_vector\\(\\s*&?\"")
	var files := PackedStringArray()
	for dir in SCAN_DIRS:
		scripts_under(dir, files)
	assert_gt(files.size(), 50, "found the scripts")

	var hits := PackedStringArray()
	for path in files:
		if ALLOWED.has(path):
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var found := raw.search(code_of(lines[i]))
			if found:
				hits.append("%s:%d %s" % [path, i + 1, found.get_string()])

	assert_eq(hits, PackedStringArray(), "raw key / button checks belong in Controls.gd")

func test_doc_lists_every_action() -> void:
	var text := Controls.markdown()
	for action in Controls.TABLE:
		assert_string_contains(text, "`%s`" % action)
	for group in Controls.GROUPS:
		assert_string_contains(text, "## " + group)
	assert_string_contains(text, "| `editor_toggle` | F2 |")

	var out := ProjectSettings.globalize_path("user://controls_doc_test.md")
	assert_eq(ControlsDoc.write_doc(out), OK)
	assert_eq(FileAccess.get_file_as_string(out), text, "the generator writes the table's markdown")
	DirAccess.remove_absolute(out)
	assert_eq(FileAccess.get_file_as_string("res://docs/CONTROLS.md"), text, "docs/CONTROLS.md is current, rerun game/scripts/core/GenerateControlsDoc.gd")

func test_describe_groups_in_order() -> void:
	var rows := Controls.describe()
	assert_eq(rows.size(), Controls.TABLE.size())
	var last := -1
	for row in rows:
		var at := Controls.GROUPS.find(row["group"])
		assert_true(at >= last, "%s in group order" % row["action"])
		last = at
	assert_eq(Controls.bindings_text(rows[0]), "A, Left")

func test_ctrl_combos_are_apart_from_bare_keys() -> void:
	assert_true(Controls.pressed(key(KEY_V, true), Controls.SPRITE_PASTE))
	assert_false(Controls.pressed(key(KEY_V, true), Controls.SPRITE_MOVE), "ctrl+v is not the move tool")
	assert_true(Controls.pressed(key(KEY_V), Controls.SPRITE_MOVE))
	assert_false(Controls.pressed(key(KEY_V), Controls.SPRITE_PASTE))
	assert_true(Controls.pressed(key(KEY_B, false, true), Controls.SPRITE_PENCIL), "shift does not get in the way")
	assert_true(Controls.pressed(key(KEY_Z, true, true), Controls.SPRITE_REDO), "ctrl+shift+z redoes")
	var echo := key(KEY_LEFT)
	echo.echo = true
	assert_false(Controls.pressed(echo, Controls.SPRITE_NUDGE_LEFT))
	assert_true(Controls.pressed(echo, Controls.SPRITE_NUDGE_LEFT, true))

# the editor plugins match against the table when the InputMap lacks the
# action: the table's events answer the same
func test_table_answers_without_the_input_map() -> void:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var matched := false
	for binding in Controls.events(Controls.SPAWN_ROTATE_LEFT):
		matched = matched or Controls.binding_matches(binding, wheel)
	assert_true(matched)
	assert_true(Controls.has_mouse_button(Controls.PIPES_ERASE, MOUSE_BUTTON_RIGHT))
	assert_false(Controls.has_mouse_button(Controls.PIPES_ERASE, MOUSE_BUTTON_LEFT))

	var shift_click := InputEventMouseButton.new()
	shift_click.shift_pressed = true
	assert_true(Controls.modifier_held(shift_click, Controls.PIPES_EDGE))

func test_shortcut_carries_the_keys() -> void:
	var shortcut := Controls.shortcut(Controls.SPRITE_REDO)
	assert_eq(shortcut.events.size(), 2)
	assert_true(shortcut.matches_event(key(KEY_Y, true)))
	assert_false(shortcut.matches_event(key(KEY_Y)))

func test_sprite_editor_keys_go_through_the_table() -> void:
	var editor := SpriteEditor.new()
	add_child_autofree(editor)
	await get_tree().process_frame

	editor._unhandled_key_input(key(KEY_E))
	assert_eq(editor.tool, SpriteEditor.Tool.ERASER, "E is the eraser")
	editor._unhandled_key_input(key(KEY_B))
	assert_eq(editor.tool, SpriteEditor.Tool.PENCIL, "B is the pencil")
	editor._unhandled_key_input(key(KEY_V))
	assert_eq(editor.tool, SpriteEditor.Tool.MOVE, "V is the move tool")
	var brush: int = editor.brush_size
	editor._unhandled_key_input(key(KEY_BRACKETRIGHT))
	assert_eq(editor.brush_size, brush + 1, "] grows the brush")

func test_multisprite_keys_go_through_the_table() -> void:
	var editor := MultiSpriteEditor.new()
	add_child_autofree(editor)
	await get_tree().process_frame

	editor.add_sprite("res://game/images/multisprites/snake_chunk.png", Vector2.ZERO)
	editor.selected = 0
	editor._unhandled_key_input(key(KEY_E))
	assert_almost_eq(float(editor.doc.sprites[0]["rotation"]), MultiSpriteEditor.ROTATE_STEP, 0.0001, "E turns right")
	editor._unhandled_key_input(key(KEY_Q))
	assert_almost_eq(float(editor.doc.sprites[0]["rotation"]), 0.0, 0.0001, "Q turns back")
	editor._unhandled_key_input(key(KEY_J))
	assert_eq(editor.mode, MultiSpriteEditor.Mode.JOINT, "J is joint mode")
	editor._unhandled_key_input(key(KEY_ESCAPE))
	assert_eq(editor.selected, -1, "escape clears the selection")
