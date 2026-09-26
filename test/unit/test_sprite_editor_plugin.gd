extends GutTest

# the regolith_sprite_editor addon: the EditorPlugin script parses and is
# registered, and its Sprites main screen Control works without the game or
# the editor: it hosts the shared SpriteEditor and MultiSpriteEditor, opens a
# png pair from res://game/images by path or by a FileSystem dock drop, paints,
# saves a copy under user:// and reads it back, and keeps a recent list

const PLUGIN_CFG := "res://addons/regolith_sprite_editor/plugin.cfg"
const PLUGIN := "res://addons/regolith_sprite_editor/RegolithSpriteEditorPlugin.gd"
const SCREEN := "res://addons/regolith_sprite_editor/RegolithSpriteEditorScreen.gd"
const PLAYER := "res://game/images/sprites/player.png"
const SNAKE := "res://game/images/multisprites/snake.json"
const SCRATCH_DIR := "user://sprite_editor_plugin_test"
const RECENT := SCRATCH_DIR + "/recent.cfg"

var screen

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH_DIR))
	screen = make_screen()
	await get_tree().process_frame

func after_each() -> void:
	var dir := DirAccess.open(SCRATCH_DIR)
	if dir:
		for file in dir.get_files():
			dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_DIR))

func make_screen():
	var made = load(SCREEN).new()
	made.recent_path = RECENT
	add_child_autofree(made)
	return made

func test_plugin_script_parses_and_is_enabled() -> void:
	var script = load(PLUGIN)
	assert_true(script is GDScript, "plugin script loads")
	assert_true(script.can_instantiate(), "plugin script compiles")
	assert_eq(script.get_instance_base_type(), &"EditorPlugin")

	var methods := {}
	for m in script.get_script_method_list():
		methods[m["name"]] = true
	for wanted in ["_has_main_screen", "_make_visible", "_get_plugin_name", "_get_plugin_icon", "_enter_tree", "_exit_tree", "open_path"]:
		assert_true(methods.has(wanted), "plugin implements " + wanted)

	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PLUGIN_CFG), OK)
	assert_eq(cfg.get_value("plugin", "script"), "RegolithSpriteEditorPlugin.gd")

	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	assert_true(PLUGIN_CFG in enabled, "plugin is enabled in project.godot")

func test_screen_hosts_both_editors_without_the_game() -> void:
	assert_not_null(screen.sprite_editor)
	assert_not_null(screen.multi_editor)
	assert_eq(screen.tabs.get_tab_count(), 2)
	assert_true(screen.sprite_editor.host_files, "the screen owns the file dialogs")
	assert_true(screen.multi_editor.host_files)
	assert_false(screen.sprite_editor.close_button.visible, "no close button in a main screen")
	assert_false(screen.multi_editor.close_button.visible)
	assert_null(screen.sprite_editor.file_dialog, "the editor makes no dialog of its own")
	assert_eq(screen.sprite_editor.doc.width, 32, "a blank document until a file opens")
	assert_true(screen.recent.is_empty())

func test_open_paint_save_copy_and_reload() -> void:
	assert_true(screen.open_path(PLAYER))
	assert_eq(screen.tabs.current_tab, 0, "a png opens on the Sprite tab")

	var editor: SpriteEditor = screen.sprite_editor
	var doc: SpriteDocument = editor.doc
	var texture: Texture2D = load(PLAYER)
	assert_eq(Vector2i(doc.width, doc.height), Vector2i(texture.get_size()))
	assert_gt(doc.mask.count(RegolithSprite.CELL_CORE), 0, "player_mask.png came along")
	assert_eq(editor.file_path, PLAYER)
	assert_true(screen.status.text.contains(PLAYER), "status names the opened file")

	doc.mode = SpriteDocument.Mode.GRAPHICS
	doc.paint_color = Color8(255, 0, 128)
	doc.begin_edit()
	doc.paint_at(1, 1, false)
	doc.end_edit()
	doc.mode = SpriteDocument.Mode.MASK
	doc.paint_type = RegolithSprite.CELL_WEAKPOINT3
	doc.begin_edit()
	doc.paint_at(1, 1, false)
	doc.end_edit()
	var before := doc.snapshot()

	var copy := SCRATCH_DIR + "/player_copy.png"
	watch_signals(screen)
	assert_true(screen.save_as(copy))
	assert_signal_emitted_with_parameters(screen, "saved", [copy])
	assert_true(FileAccess.file_exists(copy))
	assert_true(FileAccess.file_exists(SpriteEditor.mask_path(copy)), "the mask pair was written")
	assert_eq(editor.file_path, copy, "Save now goes to the copy")
	assert_true(screen.status.text.begins_with("saved "))
	assert_true(FileAccess.file_exists(PLAYER + ".import"), "the source png is still an imported project file")

	var original := Image.load_from_file(ProjectSettings.globalize_path(PLAYER))
	var saved := Image.load_from_file(ProjectSettings.globalize_path(copy))
	assert_eq(saved.get_pixel(1, 1), Color8(255, 0, 128))
	assert_ne(original.get_pixel(1, 1), saved.get_pixel(1, 1), "the source file is untouched")

	doc.clear()
	assert_true(screen.open_path(copy))
	assert_true(SpriteDocument.snapshots_equal(before, doc.snapshot()), "the copy reads back cell for cell")
	assert_eq(doc.get_cell_type(doc.index(1, 1)), RegolithSprite.CELL_WEAKPOINT3)

	assert_eq(screen.recent[0], copy)
	assert_true(screen.recent.has(PLAYER))

func test_mask_png_opens_its_color_pair() -> void:
	assert_true(screen.open_path("res://game/images/sprites/player_mask.png"))
	assert_eq(screen.sprite_editor.file_path, PLAYER)

func test_drop_from_filesystem_dock_opens_the_file() -> void:
	var png := {"type": "files", "files": PackedStringArray([PLAYER])}
	var json := {"type": "files", "files": PackedStringArray([SNAKE])}
	var scene := {"type": "files", "files": PackedStringArray(["res://game/scenes/Main.tscn"])}
	var nodes := {"type": "nodes", "nodes": []}

	assert_true(screen._can_drop_data(Vector2.ZERO, png))
	assert_true(screen._can_drop_data(Vector2.ZERO, json))
	assert_false(screen._can_drop_data(Vector2.ZERO, scene))
	assert_false(screen._can_drop_data(Vector2.ZERO, nodes))
	assert_false(screen._can_drop_data(Vector2.ZERO, "res://game/images/sprites/player.png"))

	screen._drop_data(Vector2.ZERO, json)
	assert_eq(screen.tabs.current_tab, 1, "a json lands on the Multi sprite tab")
	assert_eq(screen.multi_editor.doc.sprites.size(), 7)
	assert_eq(screen.multi_editor.file_path, SNAKE)

	screen._drop_data(Vector2.ZERO, png)
	assert_eq(screen.tabs.current_tab, 0)
	assert_eq(screen.sprite_editor.file_path, PLAYER)

	# the canvas and the editors stop the mouse, so they hand drops up to the screen
	assert_true(screen.sprite_editor._can_drop_data(Vector2.ZERO, json))
	assert_true(screen.sprite_editor.canvas._can_drop_data(Vector2.ZERO, json))
	assert_true(screen.multi_editor.canvas._can_drop_data(Vector2.ZERO, png))
	assert_false(screen.multi_editor.canvas._can_drop_data(Vector2.ZERO, scene))
	screen.sprite_editor.canvas._drop_data(Vector2.ZERO, json)
	assert_eq(screen.tabs.current_tab, 1, "a drop on the sprite canvas still opens the json")

	var alone := SpriteEditor.new()
	add_child_autofree(alone)
	assert_false(alone._can_drop_data(Vector2.ZERO, png), "no host, no drops")

func test_multisprite_saves_a_copy_and_reloads() -> void:
	assert_true(screen.open_path(SNAKE))
	var copy := SCRATCH_DIR + "/snake_copy.json"
	screen.multi_editor.doc.set_head(2)
	assert_true(screen.save_as(copy))
	assert_true(FileAccess.file_exists(copy))

	screen.multi_editor.clear_all()
	assert_eq(screen.multi_editor.doc.sprites.size(), 0)
	assert_true(screen.open_path(copy))
	assert_eq(screen.multi_editor.doc.sprites.size(), 7)
	assert_eq(screen.multi_editor.doc.joints.size(), 12)
	assert_eq(screen.multi_editor.doc.head, 2)

func test_unsupported_and_missing_files_are_refused() -> void:
	assert_false(screen.open_path("res://game/scenes/Main.tscn"))
	assert_false(screen.open_path("res://game/images/sprites/does_not_exist.png"))
	assert_true(screen.status.text.begins_with("could not open"))
	assert_true(screen.recent.is_empty(), "failed opens stay out of the recent list")

func test_recent_files_persist_between_screens() -> void:
	assert_true(screen.open_path(PLAYER))
	assert_true(screen.open_path(SNAKE))

	var again = make_screen()
	await get_tree().process_frame
	assert_eq(again.recent, [SNAKE, PLAYER] as Array[String])
	assert_eq(again.recent_menu.get_popup().item_count, 2)
	assert_eq(again.recent_menu.get_popup().get_item_metadata(0), SNAKE)
