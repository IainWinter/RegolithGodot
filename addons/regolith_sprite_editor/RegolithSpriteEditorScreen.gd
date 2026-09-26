@tool
extends VBoxContainer

# the Sprites main screen: a toolbar (Open, Save, Save As, Reload, Recent) over
# two tabs, Sprite (SpriteEditor on a png plus _mask.png pair) and Multi sprite
# (MultiSpriteEditor on a multisprite json). files come from the Open dialog,
# the recent list or a drop from the FileSystem dock. saving writes the res://
# files back and asks the editor filesystem to reimport them so textures in
# open scenes refresh. the editors run with host_files so every dialog is an
# EditorFileDialog here (a FileDialog when instanced outside the editor, in
# tests). recent files live in a small cfg in user://

const RECENT_PATH := "user://regolith_sprite_editor.cfg"
const RECENT_LIMIT := 12
const SPRITE_DIR := "res://game/images/sprites"
const MULTI_DIR := "res://game/images/multisprites"
const PNG_FILTER := "*.png ; PNG image"
const JSON_FILTER := "*.json ; Multi sprite"

enum Tab { SPRITE, MULTI }

var tabs: TabContainer
var sprite_editor: SpriteEditor
var multi_editor: MultiSpriteEditor
var status: Label
var recent_menu: MenuButton
var recent: Array[String] = []
# EditorFileDialog or FileDialog, untyped so the shared members resolve on either
var dialog
var dialog_purpose := ""
# where the recent list lives, tests point it elsewhere before adding the screen
var recent_path := RECENT_PATH

signal opened(path: String)
signal saved(path: String)

func _ready() -> void:
	build_toolbar()

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	sprite_editor = SpriteEditor.new()
	sprite_editor.name = "Sprite"
	sprite_editor.host_files = true
	sprite_editor.show_close = false
	sprite_editor.drop_target = self
	sprite_editor.load_requested.connect(func(): show_dialog("sprite_open"))
	sprite_editor.save_requested.connect(save_current)
	sprite_editor.saved.connect(on_saved)
	sprite_editor.loaded.connect(on_loaded)
	tabs.add_child(sprite_editor)

	multi_editor = MultiSpriteEditor.new()
	multi_editor.name = "Multi sprite"
	multi_editor.host_files = true
	multi_editor.show_close = false
	multi_editor.drop_target = self
	multi_editor.load_requested.connect(func(): show_dialog("multi_open"))
	multi_editor.save_requested.connect(save_current)
	multi_editor.add_requested.connect(func(): show_dialog("multi_add"))
	multi_editor.saved.connect(on_saved)
	multi_editor.loaded.connect(on_loaded)
	tabs.add_child(multi_editor)

	tabs.tab_changed.connect(func(_tab): set_status(""))

	load_recent()
	set_status("Open a png from res://game/images or drop one here from the FileSystem dock")

func build_toolbar() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)

	bar.add_child(tool_button("Open...", func(): show_dialog("multi_open" if tabs.current_tab == Tab.MULTI else "sprite_open"), "Open a sprite png (its _mask.png comes along) or a multisprite json"))
	bar.add_child(tool_button("Save", save_current, "Write the file back where it came from"))
	bar.add_child(tool_button("Save As...", func(): show_dialog("multi_save" if tabs.current_tab == Tab.MULTI else "sprite_save"), "Write the file somewhere else"))
	bar.add_child(tool_button("Reload", reload_current, "Read the file again from disk, dropping unsaved edits"))

	recent_menu = MenuButton.new()
	recent_menu.text = "Recent"
	recent_menu.flat = false
	recent_menu.get_popup().index_pressed.connect(func(i): open_path(recent_menu.get_popup().get_item_metadata(i)))
	bar.add_child(recent_menu)

	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(status)

func tool_button(text: String, on_press: Callable, tip := "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	return button

func set_status(text: String) -> void:
	status.text = text

func current_tab() -> int:
	return tabs.current_tab

# files

static func is_png(path: String) -> bool:
	return path.get_extension().to_lower() == "png"

static func is_json(path: String) -> bool:
	return path.get_extension().to_lower() == "json"

static func supported(path: String) -> bool:
	return is_png(path) or is_json(path)

# a mask png opens as its color pair
static func color_path_of(path: String) -> String:
	var base := path.get_basename()
	if base.ends_with("_mask") and FileAccess.file_exists(base.trim_suffix("_mask") + ".png"):
		return base.trim_suffix("_mask") + ".png"
	return path

# picks the tab from the extension and opens the file there
func open_path(path: String) -> bool:
	if is_png(path):
		tabs.current_tab = Tab.SPRITE
		if sprite_editor.load_from(color_path_of(path)):
			return true
	elif is_json(path):
		tabs.current_tab = Tab.MULTI
		if multi_editor.load_from(path):
			return true
	else:
		set_status("not a sprite file: " + path.get_file())
		return false

	set_status("could not open " + path.get_file())
	return false

func current_file() -> String:
	return multi_editor.file_path if tabs.current_tab == Tab.MULTI else sprite_editor.file_path

func save_current() -> void:
	var path := current_file()
	if path == "":
		show_dialog("multi_save" if tabs.current_tab == Tab.MULTI else "sprite_save")
		return
	save_as(path)

func save_as(path: String) -> bool:
	if tabs.current_tab == Tab.MULTI:
		return multi_editor.save_to(path)
	return sprite_editor.save_to(path)

func reload_current() -> void:
	var path := current_file()
	if path == "":
		set_status("nothing to reload")
		return
	open_path(path)

func on_loaded(path: String) -> void:
	add_recent(path)
	set_status("opened " + path)
	opened.emit(path)

func on_saved(path: String) -> void:
	add_recent(path)

	var files := PackedStringArray([path])
	if is_png(path):
		files.append(SpriteEditor.mask_path(path))
	refresh_imports(files)

	set_status("saved " + path)
	saved.emit(path)

# tells the editor's filesystem about the files we just wrote so the imported
# textures (and every RegolithSprite preview showing them) refresh. a mask that
# went away is dropped from the tree the same way. no-op outside the editor
func refresh_imports(files: PackedStringArray) -> void:
	if not Engine.is_editor_hint():
		return

	var fs := EditorInterface.get_resource_filesystem()
	var existing := PackedStringArray()

	for file in files:
		if not file.begins_with("res://"):
			continue
		fs.update_file(file)
		if FileAccess.file_exists(file) and is_png(file):
			existing.append(file)

	if not existing.is_empty():
		fs.reimport_files(existing)

# dialogs, an EditorFileDialog in the editor (res:// paths, project tree), a
# FileDialog anywhere else

func make_dialog():
	var d
	if Engine.is_editor_hint():
		d = EditorFileDialog.new()
		d.access = EditorFileDialog.ACCESS_RESOURCES
	else:
		d = FileDialog.new()
		d.access = FileDialog.ACCESS_RESOURCES
		d.size = Vector2i(720, 480)
	d.file_selected.connect(on_file_selected)
	add_child(d)
	return d

func show_dialog(purpose: String) -> void:
	if dialog == null:
		dialog = make_dialog()

	dialog_purpose = purpose
	var saving := purpose.ends_with("_save")
	var multi := purpose.begins_with("multi")
	var adding := purpose == "multi_add"

	dialog.file_mode = dialog.FILE_MODE_SAVE_FILE if saving else dialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray([JSON_FILTER if multi and not adding else PNG_FILTER])
	dialog.title = {
		"sprite_open": "Open sprite",
		"sprite_save": "Save sprite",
		"multi_open": "Open multi sprite",
		"multi_save": "Save multi sprite",
		"multi_add": "Add sprite",
	}[purpose]

	var current := current_file()
	if current != "" and not adding:
		dialog.current_dir = current.get_base_dir()
		dialog.current_file = current.get_file()
	else:
		dialog.current_dir = MULTI_DIR if multi and not adding else SPRITE_DIR
		dialog.current_file = (multi_editor.filename + ".json" if multi else sprite_editor.filename + ".png") if saving else ""

	if Engine.is_editor_hint():
		dialog.popup_file_dialog()
	else:
		dialog.popup_centered()

func on_file_selected(path: String) -> void:
	match dialog_purpose:
		"sprite_open", "multi_open":
			open_path(path)
		"sprite_save", "multi_save":
			save_as(path)
		"multi_add":
			multi_editor.place_new_sprite(path)
			set_status("added " + path)

# drops from the FileSystem dock arrive as {"type": "files", "files": [...]}

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return not dropped_file(data).is_empty()

func _drop_data(_at: Vector2, data: Variant) -> void:
	var path := dropped_file(data)
	if path != "":
		open_path(path)

static func dropped_file(data: Variant) -> String:
	if not (data is Dictionary) or data.get("type", "") != "files":
		return ""

	for file in data.get("files", []):
		if supported(String(file)):
			return String(file)

	return ""

# recent files

func load_recent() -> void:
	recent.clear()
	var cfg := ConfigFile.new()
	if cfg.load(recent_path) == OK:
		for file in cfg.get_value("recent", "files", PackedStringArray()):
			recent.append(String(file))
	rebuild_recent_menu()

func save_recent() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("recent", "files", PackedStringArray(recent))
	cfg.save(recent_path)

func add_recent(path: String) -> void:
	recent.erase(path)
	recent.push_front(path)
	if recent.size() > RECENT_LIMIT:
		recent.resize(RECENT_LIMIT)
	save_recent()
	rebuild_recent_menu()

func rebuild_recent_menu() -> void:
	var popup := recent_menu.get_popup()
	popup.clear()
	for path in recent:
		popup.add_item(path.trim_prefix("res://"))
		popup.set_item_metadata(popup.item_count - 1, path)
	recent_menu.disabled = recent.is_empty()
