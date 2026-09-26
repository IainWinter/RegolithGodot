extends SceneTree

# writes docs/CONTROLS.md, every binding of the game and its tools grouped
# as the Controls table has them. run headless from the project folder:
#   godot --headless --path . -s game/scripts/core/GenerateControlsDoc.gd

const ControlsTable := preload("res://game/scripts/core/Controls.gd")
const DOC := "res://docs/CONTROLS.md"

func _init() -> void:
	var error := write_doc(ProjectSettings.globalize_path(DOC))
	print("GenerateControlsDoc: %s" % ("wrote " + DOC if error == OK else error_string(error)))
	quit(0 if error == OK else 1)

static func write_doc(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return FileAccess.get_open_error()

	file.store_string(ControlsTable.markdown())
	return OK
