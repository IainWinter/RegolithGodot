extends MenuWindow
class_name DeathMenu

# the death menu, the GameDeathScreenSystem of the original, shown by
# GameState in DEAD while the dead song plays. Retry reloads the level, Quit
# quits, Main Menu is a placeholder until the menu scene exists. scene:
# res://game/scenes/ui/DeathMenu.tscn

signal retry_pressed
signal main_menu_pressed
signal quit_pressed

func _ready() -> void:
	super()
	chosen.connect(on_chosen)

func on_chosen(button: StringName) -> void:
	match button:
		&"Retry": retry_pressed.emit()
		&"MainMenu": main_menu_pressed.emit()
		&"Quit": quit_pressed.emit()
