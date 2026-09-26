extends Node

# the GameSettings autoload, port of game_settings() / game_settings_save():
# a handful of player options loaded once from user://game_settings.cfg and
# written back with save(). the display fields are kept for the options
# menu to come, only aim_assist is read by gameplay so far

const PATH := "user://game_settings.cfg"
const SECTION := "game"

var aim_assist := true
var emissive := true
var vsync := true
var display_mode := 0
var volume := 100
# the raster toggles of the debug spawn panel, see RasterMode
var raster_lightning := false
var raster_effects := false
var raster_world := false
# the ui font drawn on whole pixels with no antialiasing, off is smooth
var font_rastered := true

func _ready() -> void:
	# the earliest autoload that runs game code, every binding lands in the
	# InputMap here before anything reads input
	Controls.register()
	load_settings()

func load_settings() -> void:
	var file := ConfigFile.new()

	if file.load(PATH) != OK:
		return

	aim_assist = file.get_value(SECTION, "aim_assist", aim_assist)
	emissive = file.get_value(SECTION, "emissive", emissive)
	vsync = file.get_value(SECTION, "vsync", vsync)
	display_mode = file.get_value(SECTION, "display_mode", display_mode)
	volume = file.get_value(SECTION, "volume", volume)
	raster_lightning = file.get_value(SECTION, "raster_lightning", raster_lightning)
	raster_effects = file.get_value(SECTION, "raster_effects", raster_effects)
	raster_world = file.get_value(SECTION, "raster_world", raster_world)
	font_rastered = file.get_value(SECTION, "font_rastered", font_rastered)

func save() -> Error:
	var file := ConfigFile.new()
	file.set_value(SECTION, "aim_assist", aim_assist)
	file.set_value(SECTION, "emissive", emissive)
	file.set_value(SECTION, "vsync", vsync)
	file.set_value(SECTION, "display_mode", display_mode)
	file.set_value(SECTION, "volume", volume)
	file.set_value(SECTION, "raster_lightning", raster_lightning)
	file.set_value(SECTION, "raster_effects", raster_effects)
	file.set_value(SECTION, "raster_world", raster_world)
	file.set_value(SECTION, "font_rastered", font_rastered)
	return file.save(PATH)
