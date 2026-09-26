extends SceneTree

# rewrites project.godot's [input] section from the Controls table, the one
# place bindings are defined. run headless from the project folder:
#   godot --headless --path . -s game/scripts/core/GenerateInputMap.gd
# then reload the project in an open editor (Project > Reload Current
# Project) so it does not save its old [input] back over the file.
# test_controls checks the two agree

const ControlsTable := preload("res://game/scripts/core/Controls.gd")
const PROJECT := "res://project.godot"

func _init() -> void:
	var error := write_input_section(ProjectSettings.globalize_path(PROJECT))
	print("GenerateInputMap: %s" % ("wrote " + PROJECT if error == OK else error_string(error)))
	quit(0 if error == OK else 1)

# the file with its [input] section swapped for the generated one, added at
# the end when the file has none
static func with_input_section(text: String) -> String:
	var section := ControlsTable.project_input_text()
	var start := text.find("\n[input]\n")

	if start < 0:
		return text.strip_edges(false, true) + "\n\n" + section

	start += 1
	var next := text.find("\n[", start + 1)
	var tail := "" if next < 0 else text.substr(next + 1)
	return text.substr(0, start) + section + ("\n" + tail if tail != "" else "")

static func write_input_section(path: String) -> Error:
	var text := FileAccess.get_file_as_string(path)

	if text.is_empty():
		return ERR_FILE_CANT_READ

	var updated := with_input_section(text)

	if updated == text:
		return OK

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return FileAccess.get_open_error()

	file.store_string(updated)
	return OK
