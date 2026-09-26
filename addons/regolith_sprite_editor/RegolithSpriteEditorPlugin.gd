@tool
extends EditorPlugin

# adds a "Sprites" main screen (next to 2D, 3D, Script, AssetLib) that hosts
# the game's own SpriteEditor and MultiSpriteEditor Controls, the same ones the
# F2 window shows in game. the screen owns the file dialogs, the recent list
# and the reimport after a save; the editors know nothing about the editor.
# nothing here pauses or dims anything

const Screen := preload("res://addons/regolith_sprite_editor/RegolithSpriteEditorScreen.gd")

var screen: Control

func _enter_tree() -> void:
	screen = Screen.new()
	screen.name = "Sprites"
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(screen)
	screen.hide()

func _exit_tree() -> void:
	if screen:
		screen.queue_free()
		screen = null

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if screen:
		screen.visible = visible

func _get_plugin_name() -> String:
	return "Sprites"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("ImageTexture", "EditorIcons")

# switch to the Sprites screen with a png or multisprite json open
func open_path(path: String) -> bool:
	if screen == null:
		return false

	EditorInterface.set_main_screen_editor("Sprites")
	return screen.open_path(path)
