extends GutTest

# PixelTheme carries the first game's font, Staatliches out of game/fonts, as
# the default font of every themed control. rastered by default (no
# antialiasing, no hinting, no subpixel positioning, no oversampling), the
# smooth variant sits behind GameSettings.font_rastered and the "Raster font"
# check of the debug spawn panel; flipping either swaps the shared theme's
# font so the menus already open follow (theme changes reach the controls
# a frame later)

const PAUSE_MENU := "res://game/scenes/ui/PauseMenu.tscn"
const DEATH_MENU := "res://game/scenes/ui/DeathMenu.tscn"

var saved_rastered: bool

func before_each() -> void:
	saved_rastered = GameSettings.font_rastered
	GameSettings.font_rastered = true
	PixelTheme.apply_font_mode(true)

func after_each() -> void:
	GameSettings.font_rastered = saved_rastered
	GameSettings.save()
	PixelTheme.apply_font_mode(saved_rastered)
	get_tree().paused = false

func test_font_is_staatliches_from_game_fonts() -> void:
	assert_eq(PixelTheme.FONT_PATH, "res://game/fonts/Staatliches-Regular.ttf")
	assert_true(FileAccess.file_exists(PixelTheme.FONT_PATH), "the ttf ships in game/fonts")
	assert_true(FileAccess.file_exists("res://game/fonts/OFL.txt"), "with its license")

	var font := PixelTheme.font()
	assert_true(font is FontVariation, "the theme font carries the glyph spacing")
	assert_eq(font.spacing_glyph, PixelTheme.GLYPH_SPACING)
	assert_true(font.base_font is FontFile)
	assert_eq(font.base_font.get_font_name(), PixelTheme.FONT_NAME)
	assert_eq(font.base_font, PixelTheme.font_file())

func test_raster_font_settings() -> void:
	var font := PixelTheme.raster_font()
	assert_eq(font.get_font_name(), PixelTheme.FONT_NAME)
	assert_eq(font.antialiasing, TextServer.FONT_ANTIALIASING_NONE)
	assert_eq(font.hinting, TextServer.HINTING_NONE)
	assert_eq(font.subpixel_positioning, TextServer.SUBPIXEL_POSITIONING_DISABLED)
	assert_false(font.multichannel_signed_distance_field)
	assert_false(font.generate_mipmaps)
	assert_eq(font.oversampling, 1.0)

func test_smooth_font_is_the_same_face_antialiased() -> void:
	var font := PixelTheme.smooth_font()
	assert_eq(font.get_font_name(), PixelTheme.FONT_NAME)
	assert_eq(font.antialiasing, TextServer.FONT_ANTIALIASING_GRAY)
	assert_eq(font.hinting, TextServer.HINTING_LIGHT)
	assert_false(font.multichannel_signed_distance_field)
	assert_ne(font, PixelTheme.raster_font())

func test_theme_default_font_is_the_raster_font() -> void:
	var theme := PixelTheme.theme()
	assert_eq(theme.default_font, PixelTheme.font())
	assert_eq(theme.default_font.base_font, PixelTheme.raster_font())
	assert_eq(theme.get_font("title_font", "Window"), PixelTheme.font())
	assert_eq(theme.default_font_size, PixelTheme.FONT_SIZE)

func test_menus_resolve_the_theme_font() -> void:
	for path in [PAUSE_MENU, DEATH_MENU]:
		var menu: MenuWindow = load(path).instantiate()
		add_child_autofree(menu)
		await wait_process_frames(1)

		var title: Label = menu.column.get_node("Title")
		assert_eq(title.get_theme_font("font"), PixelTheme.font(), path + " title")
		assert_eq(title.get_theme_font("font").base_font, PixelTheme.raster_font(), path + " title file")
		assert_eq(title.get_theme_font_size("font_size"), PixelTheme.TITLE_FONT_SIZE, path + " title size")

		for button in menu.buttons:
			assert_eq(button.get_theme_font("font"), PixelTheme.font(), path + " " + button.name)
			assert_eq(button.get_theme_font_size("font_size"), PixelTheme.FONT_SIZE, path + " " + button.name + " size")

func test_apply_font_mode_swaps_the_font_of_an_open_menu() -> void:
	var menu: MenuWindow = load(PAUSE_MENU).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(1)
	var title: Label = menu.column.get_node("Title")
	var resume: Button = menu.button_named(&"Resume")

	PixelTheme.apply_font_mode(false)
	await wait_process_frames(1)
	assert_false(PixelTheme.rastered)
	assert_eq(PixelTheme.theme().default_font.base_font.antialiasing, TextServer.FONT_ANTIALIASING_GRAY)
	assert_eq(title.get_theme_font("font").base_font, PixelTheme.smooth_font())
	assert_eq(title.get_theme_font("font").base_font.antialiasing, TextServer.FONT_ANTIALIASING_GRAY)
	assert_eq(resume.get_theme_font("font").base_font, PixelTheme.smooth_font())

	PixelTheme.apply_font_mode(true)
	await wait_process_frames(1)
	assert_eq(PixelTheme.theme().default_font.base_font.antialiasing, TextServer.FONT_ANTIALIASING_NONE)
	assert_eq(title.get_theme_font("font").base_font, PixelTheme.raster_font())
	assert_eq(resume.get_theme_font("font").base_font, PixelTheme.raster_font())

func test_spawn_panel_raster_font_check_flips_the_setting_and_the_live_font() -> void:
	var menu: MenuWindow = load(PAUSE_MENU).instantiate()
	add_child_autofree(menu)
	var panel := DebugSpawnPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(1)
	var title: Label = menu.column.get_node("Title")

	assert_true(panel.raster_font.button_pressed, "the check shows the saved setting")
	assert_eq(title.get_theme_font("font").base_font.antialiasing, TextServer.FONT_ANTIALIASING_NONE)

	panel.raster_font.button_pressed = false
	await wait_process_frames(1)
	assert_false(GameSettings.font_rastered)
	assert_false(PixelTheme.rastered)
	assert_eq(PixelTheme.theme().default_font.base_font.antialiasing, TextServer.FONT_ANTIALIASING_GRAY)
	assert_eq(title.get_theme_font("font").base_font.antialiasing, TextServer.FONT_ANTIALIASING_GRAY, "the open menu follows")

	var saved := ConfigFile.new()
	assert_eq(saved.load(GameSettings.PATH), OK)
	assert_false(saved.get_value(GameSettings.SECTION, "font_rastered", true), "the flip is saved")

	panel.raster_font.button_pressed = true
	await wait_process_frames(1)
	assert_true(GameSettings.font_rastered)
	assert_eq(title.get_theme_font("font").base_font.antialiasing, TextServer.FONT_ANTIALIASING_NONE)

func test_saved_setting_loads_back() -> void:
	GameSettings.font_rastered = false
	assert_eq(GameSettings.save(), OK)
	GameSettings.font_rastered = true
	GameSettings.load_settings()
	assert_false(GameSettings.font_rastered)
