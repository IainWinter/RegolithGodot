extends CanvasLayer
class_name DebugSpawnPanel

# backtick panel docked over the running game: one card per spawnable kind the
# StableSpawner knows and one per RockProps in the config folder. press a
# card and pull the cursor out of the panel to drag it: a ghost of the
# sprite at the camera's zoom follows the cursor, the wheel or Q / E turn
# it, escape drops it, and letting go over the world sends a SpawnRequest on
# the SpawnBus with wait_for_room off so it lands right where it fell with
# the ghost's facing. a plain click on a card (press and let go without
# leaving it) spawns at the click spot, the view center pushed left of the
# panel, or under the cursor when the SPAWN AT CURSOR toggle is on. the gun
# and the turret carry a SIZE field, cells across, that rides on the request
# as scale_cells meta for the StableSpawner to copy onto the node. the panel
# never instantiates a scene. the drag is the panel's own state machine, not
# the Control drag and drop: that one cannot be driven headless, cannot turn
# its preview and takes the escape key itself. while open a left drag on a
# dynamic sprite pulls it after the cursor. the game keeps running, nothing
# dims, nothing pauses. looks come from PixelTheme. a RASTER section under
# the title holds the three low resolution toggles (lightning, bullets /
# effects, everything), kept in GameSettings and applied through RasterMode,
# also once on ready so a saved choice comes back with the game, and the
# font toggle: the ui font rastered on whole pixels or smooth, applied
# through PixelTheme

const ACTION := Controls.SPAWN_PANEL
const PANEL_WIDTH := 184
const MARGIN := 8
const PREVIEW := 40
const PREVIEW_SEED := 7
# units per second of pull per unit of distance to the cursor
const GRAB_GAIN := 10.0
# screen pixels the cursor moves from the press before a drag starts
const DRAG_THRESHOLD := 6.0
# radians per wheel notch or Q / E press while dragging
const ROTATE_STEP := PI / 12.0
# where a plain click spawns, a fraction of the view from its center
const CLICK_SPOT := Vector2(-0.25, 0.0)
# kinds built at a size, cells across, with their default
const SIZED_KINDS := {SpawnRequest.Kind.GUN: 32, SpawnRequest.Kind.TURRET: 96}
const SIZE_MIN := 8
const SIZE_MAX := 256

@export var rock_props_dir := "res://game/config/rocks"

signal dropped(request: SpawnRequest)
signal drag_started(entry: Entry)
signal drag_ended

var root: Control
var catcher: DropCatcher
var window: PanelContainer
var list: VBoxContainer
var ghost: Ghost
var cursor_check: CheckBox
var entries: Array[Entry] = []
var last_request: SpawnRequest
var grabbed: RegolithSprite
var raster_lightning: CheckBox
var raster_effects: CheckBox
var raster_world: CheckBox
var raster_font: CheckBox
# a plain click spawns under the cursor instead of the click spot
var spawn_at_cursor := false

# the drag: the pressed card, where it was pressed, whether the cursor has
# left it, and the ghost's facing
var drag_entry: Entry
var drag_from := Vector2.ZERO
var dragging := false
var drag_rotation := 0.0

# a card in the list: a kind, its preview and, for sized kinds, the size
class Entry extends PanelContainer:
	var kind := SpawnRequest.Kind.FIGHTER
	var rock_props: RockProps
	var label := ""
	# the scene's or rock's own art, null for kinds with none
	var art: Texture2D
	# the icon on the card, the art or the placeholder
	var preview: Texture2D
	var enabled := true
	# cells across for sized kinds, zero for the rest
	var scale_cells := 0
	var size_field: SpinBox
	var normal: StyleBox
	var hover: StyleBox
	var panel: DebugSpawnPanel

	func _init(owner_panel: DebugSpawnPanel, of_kind: SpawnRequest.Kind, text: String, texture: Texture2D, props: RockProps = null, can_drag := true) -> void:
		panel = owner_panel
		kind = of_kind
		label = text
		art = texture
		preview = texture if texture else DebugSpawnPanel.placeholder_icon()
		rock_props = props
		enabled = can_drag
		scale_cells = SIZED_KINDS.get(kind, 0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG if enabled else Control.CURSOR_ARROW
		tooltip_text = "click to spawn, drag into the world" if enabled else "no scene set on the StableSpawner"

		normal = PixelTheme.box(PixelTheme.PAPER_RAISED if enabled else PixelTheme.PAPER, PixelTheme.LINE if enabled else PixelTheme.LINE_DIM, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, 4, 4)
		hover = PixelTheme.box(PixelTheme.PAPER_HOVER, PixelTheme.ACCENT, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, 4, 4)
		add_theme_stylebox_override("panel", normal)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		add_child(row)

		var icon := TextureRect.new()
		icon.texture = preview
		icon.custom_minimum_size = Vector2.ONE * PREVIEW
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = Color.WHITE if enabled else Color(1, 1, 1, 0.4)
		row.add_child(icon)

		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 2)
		row.add_child(column)

		var text_label := Label.new()
		text_label.text = label
		text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not enabled:
			text_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
		column.add_child(text_label)

		if scale_cells > 0:
			column.add_child(build_size_row())

		if enabled:
			mouse_entered.connect(func(): add_theme_stylebox_override("panel", hover))
			mouse_exited.connect(func(): add_theme_stylebox_override("panel", normal))

	# SIZE and a spin box of cells across, presses on it never start a drag
	func build_size_row() -> Control:
		var size_row := HBoxContainer.new()
		size_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_row.add_theme_constant_override("separation", 4)

		var size_label := Label.new()
		size_label.text = "SIZE"
		size_label.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
		size_label.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
		size_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		size_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_row.add_child(size_label)

		size_field = SpinBox.new()
		size_field.min_value = SIZE_MIN
		size_field.max_value = SIZE_MAX
		size_field.step = 1
		size_field.value = scale_cells
		size_field.tooltip_text = "cells across, rides on the request as scale_cells"
		size_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_field.editable = enabled
		size_field.value_changed.connect(func(value: float): scale_cells = int(value))
		size_row.add_child(size_field)
		return size_row

	func is_rock() -> bool:
		return kind == SpawnRequest.Kind.ROCK

	func is_sized() -> bool:
		return SIZED_KINDS.has(kind)

	func drag_data() -> Dictionary:
		return {"spawn_kind": kind, "rock_props": rock_props, "label": label, "scale_cells": scale_cells}

	# the art's size in cells, the size field for sized kinds
	func art_cells() -> Vector2:
		if scale_cells > 0:
			return Vector2.ONE * scale_cells

		return Vector2(art.get_size()) if art else Vector2.ONE * RegolithWorld.CELLS_PER_CHUNK

	# presses and motion over the card go to the panel's drag, in screen
	# coordinates so a synthesized event drives it the same as a real one
	func _gui_input(event: InputEvent) -> void:
		if not enabled or panel == null or not (event is InputEventMouse):
			return

		var screen: Vector2 = get_global_transform_with_canvas() * event.position

		if Controls.pressed(event, Controls.SPAWN_GRAB) and panel.drag_entry == null:
			panel.arm_drag(self, screen)
			accept_event()
		elif panel.drag_entry == self and panel.handle_drag_event(event, screen):
			accept_event()

# the sprite as it will spawn, drawn at the camera's zoom around the
# cursor with its facing, a labeled circle for kinds without art. the
# texture sits at the top left of its chunk padded grid, the grid's center
# is the sprite's origin
class Ghost extends Control:
	var texture: Texture2D
	var label := ""
	var cells := Vector2.ONE * RegolithWorld.CELLS_PER_CHUNK
	var screen := Vector2.ZERO
	var angle := 0.0
	# screen pixels per cell
	var scale_by := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visible = false

	# the grid the art loads into, whole chunks
	func padded() -> Vector2:
		var chunk := float(RegolithWorld.CELLS_PER_CHUNK)
		return Vector2(ceilf(cells.x / chunk), ceilf(cells.y / chunk)).max(Vector2.ONE) * chunk

	# the grid's footprint on the screen before the turn
	func rect() -> Rect2:
		var size := padded() * scale_by
		return Rect2(screen - size * 0.5, size)

	func _draw() -> void:
		draw_set_transform(screen, angle, Vector2.ONE * scale_by)
		var origin := -padded() * 0.5

		if texture:
			draw_texture_rect(texture, Rect2(origin, cells), false, Color(1, 1, 1, 0.8))
		else:
			var radius := cells.x * 0.5
			draw_circle(Vector2.ZERO, radius, Color(PixelTheme.PAPER, 0.5))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, PixelTheme.ACCENT, 1.0 / scale_by)

		# the facing, a tick from the center out of the grid's right edge
		var reach := padded().x * 0.5
		draw_line(Vector2.ZERO, Vector2(reach, 0.0), PixelTheme.ACCENT, 1.0 / scale_by)

		if not texture:
			draw_set_transform(screen, 0.0, Vector2.ONE)
			var font := ThemeDB.fallback_font
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, PixelTheme.SMALL_FONT_SIZE).x
			draw_string(font, Vector2(-width * 0.5, 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, -1, PixelTheme.SMALL_FONT_SIZE, PixelTheme.TEXT)

# the see through control over the whole view that takes the sprite
# grabs. it passes what it does not use on to the game
class DropCatcher extends Control:
	var panel: DebugSpawnPanel

	func _init(owner_panel: DebugSpawnPanel) -> void:
		panel = owner_panel
		mouse_filter = Control.MOUSE_FILTER_PASS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _gui_input(event: InputEvent) -> void:
		if panel.drag_entry != null:
			return

		if event is InputEventMouseButton and Controls.matches(event, Controls.SPAWN_GRAB):
			if event.pressed:
				if panel.grab(event.position):
					accept_event()
			elif panel.release():
				accept_event()

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	build()
	rebuild_entries()
	root.visible = false
	RasterMode.apply(get_tree())
	sync_raster()

# the drag runs ahead of the gui so the cursor can leave the card: motion,
# the release, and the Controls.SPAWN_ROTATE_* / SPAWN_DRAG_CANCEL bindings
# (wheel, Q / E, escape) are the panel's while a card is pressed
func _input(event: InputEvent) -> void:
	if drag_entry == null or not is_open():
		return

	var screen := Vector2.ZERO

	if event is InputEventMouse:
		screen = event.position

	if handle_drag_event(event, screen):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION) and event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and Controls.pressed(event, Controls.SPAWN_PANEL_CLOSE, true):
		close()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if dragging:
		ghost.scale_by = world_scale(get_viewport())
		ghost.queue_redraw()

	if grabbed == null:
		return

	if not is_instance_valid(grabbed) or grabbed.is_queued_for_deletion() or not is_open():
		grabbed = null
		return

	var target := screen_to_units(get_viewport().get_mouse_position())
	var at := grabbed.global_position / Steering.ppu()
	grabbed.linear_velocity = (target - at) * GRAB_GAIN

# open and close

func is_open() -> bool:
	return root.visible

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func open() -> void:
	root.visible = true

func close() -> void:
	cancel_drag()
	release()
	root.visible = false

# ui

func build() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = PixelTheme.theme()
	add_child(root)

	catcher = DropCatcher.new(self)
	catcher.name = "DropCatcher"
	root.add_child(catcher)

	window = PanelContainer.new()
	window.name = "Window"
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER, PixelTheme.LINE, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, PixelTheme.BORDER, 0, 0))
	window.anchor_left = 1.0
	window.anchor_right = 1.0
	window.anchor_top = 0.0
	window.anchor_bottom = 1.0
	window.offset_left = -(MARGIN + PANEL_WIDTH)
	window.offset_right = -MARGIN
	window.offset_top = MARGIN
	window.offset_bottom = -MARGIN
	root.add_child(window)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	window.add_child(column)

	column.add_child(build_title())
	column.add_child(build_raster())
	column.add_child(build_spawn_options())

	var hint := Label.new()
	hint.text = "CLICK TO SPAWN, DRAG INTO THE WORLD\nWHEEL OR Q / E TURNS, ESC DROPS"
	hint.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
	hint.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint_box := MarginContainer.new()
	hint_box.add_theme_constant_override("margin_top", 6)
	hint_box.add_theme_constant_override("margin_bottom", 2)
	hint_box.add_child(hint)
	column.add_child(hint_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 6)
	scroll.add_child(pad)

	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	pad.add_child(list)

	ghost = Ghost.new()
	ghost.name = "Ghost"
	root.add_child(ghost)

func build_title() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.INK, PixelTheme.LINE, 0, 0, 0, PixelTheme.BORDER, 8, 4))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)

	var title := Label.new()
	title.text = "SPAWN"
	title.add_theme_color_override("font_color", PixelTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "Close (`)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	row.add_child(close_button)

	return bar

# the spawn at cursor toggle
func build_spawn_options() -> Control:
	var box := PanelContainer.new()
	box.name = "SpawnOptions"
	box.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER_SUNKEN, PixelTheme.LINE, 0, 0, 0, PixelTheme.BORDER, 6, 4))

	cursor_check = CheckBox.new()
	cursor_check.text = "Spawn at cursor"
	cursor_check.tooltip_text = "a plain click spawns under the mouse instead of the view center"
	cursor_check.focus_mode = Control.FOCUS_NONE
	cursor_check.set_pressed_no_signal(spawn_at_cursor)
	cursor_check.toggled.connect(set_spawn_at_cursor)
	box.add_child(cursor_check)
	return box

func set_spawn_at_cursor(on: bool) -> void:
	spawn_at_cursor = on

	if cursor_check and cursor_check.button_pressed != on:
		cursor_check.set_pressed_no_signal(on)

# raster toggles

func build_raster() -> Control:
	var box := PanelContainer.new()
	box.name = "Raster"
	box.add_theme_stylebox_override("panel", PixelTheme.box(PixelTheme.PAPER_SUNKEN, PixelTheme.LINE, 0, 0, 0, PixelTheme.BORDER, 6, 4))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	box.add_child(column)

	var heading := Label.new()
	heading.text = "RASTER"
	heading.add_theme_font_size_override("font_size", PixelTheme.SMALL_FONT_SIZE)
	heading.add_theme_color_override("font_color", PixelTheme.TEXT_DIM)
	column.add_child(heading)

	raster_lightning = raster_check("Lightning", "lightning bolts snap to the cell grid, off draws them as smooth lines", on_raster_lightning)
	raster_effects = raster_check("Bullets / effects", "projectiles, trails and particles drawn at one pixel per cell", on_raster_effects)
	raster_world = raster_check("Everything", "the whole world drawn at one pixel per cell, the UI stays native", on_raster_world)
	raster_font = raster_check("Raster font", "the ui font drawn on whole pixels with no antialiasing, off draws it smooth like the first game's atlas", on_raster_font)
	column.add_child(raster_lightning)
	column.add_child(raster_effects)
	column.add_child(raster_world)
	column.add_child(raster_font)

	return box

func raster_check(text: String, tip: String, on_toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.tooltip_text = tip
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(on_toggled)
	return check

# the check boxes show what the settings hold
func sync_raster() -> void:
	var settings := RasterMode.settings_node(get_tree())

	if settings == null:
		return

	raster_lightning.set_pressed_no_signal(settings.raster_lightning)
	raster_effects.set_pressed_no_signal(settings.raster_effects)
	raster_world.set_pressed_no_signal(settings.raster_world)
	raster_font.set_pressed_no_signal(settings.font_rastered)
	PixelTheme.apply_font_mode(settings.font_rastered)

func on_raster_lightning(on: bool) -> void:
	RasterMode.set_lightning(get_tree(), on)

func on_raster_effects(on: bool) -> void:
	RasterMode.set_effects(get_tree(), on)

func on_raster_world(on: bool) -> void:
	RasterMode.set_world(get_tree(), on)

func on_raster_font(on: bool) -> void:
	var settings := RasterMode.settings_node(get_tree())

	if settings != null:
		settings.font_rastered = on
		settings.save()

	PixelTheme.apply_font_mode(on)

# entries

func rebuild_entries() -> void:
	cancel_drag()

	for entry in entries:
		entry.queue_free()
	entries.clear()

	var spawner := find_spawner()

	for kind in SpawnRequest.Kind.values():
		if kind == SpawnRequest.Kind.MESSAGE or kind == SpawnRequest.Kind.ROCK:
			continue

		var scene: PackedScene = spawner.scene_for(kind) if spawner else null
		add_entry(Entry.new(self, kind, kind_label(kind), scene_texture(scene) if scene else null, null, scene != null))

	for path in rock_props_paths():
		var props := load(path) as RockProps
		if props == null:
			continue

		add_entry(Entry.new(self, SpawnRequest.Kind.ROCK, path.get_file().get_basename().replace("_", " "), rock_preview(props), props))

func add_entry(entry: Entry) -> void:
	entries.append(entry)
	list.add_child(entry)

func entry_for(kind: SpawnRequest.Kind) -> Entry:
	for entry in entries:
		if entry.kind == kind:
			return entry

	return null

func rock_entries() -> Array[Entry]:
	var rocks: Array[Entry] = []
	for entry in entries:
		if entry.is_rock():
			rocks.append(entry)
	return rocks

# the StableSpawner is whoever listens on the bus
static func find_spawner() -> StableSpawner:
	for connection in SpawnBus.spawn_requested.get_connections():
		var listener: Object = connection["callable"].get_object()
		if listener is StableSpawner:
			return listener

	return null

static func kind_label(kind: SpawnRequest.Kind) -> String:
	return SpawnRequest.Kind.keys()[kind].to_lower().replace("_", " ")

func rock_props_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(rock_props_dir)

	if dir == null:
		return paths

	for file in dir.get_files():
		if file.get_extension() == "tres":
			paths.append(rock_props_dir.path_join(file))

	paths.sort()
	return paths

# the root sprite's texture read off the packed scene, nothing instantiated
static func scene_texture(scene: PackedScene) -> Texture2D:
	var state := scene.get_state()

	if state.get_node_count() == 0:
		return null

	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"texture":
			return state.get_node_property_value(0, i) as Texture2D

	return null

# one generated rock at the props' smallest size, masked to its shape
static func rock_preview(props: RockProps) -> Texture2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = PREVIEW_SEED
	var images := RockGenerator.make_rock(rng, props, maxi(props.min_chunks, 1))
	var color: Image = images["color"]
	var mask: Image = images["mask"]
	var out := Image.create(color.get_width(), color.get_height(), false, Image.FORMAT_RGBA8)
	out.fill(Color.TRANSPARENT)

	for y in color.get_height():
		for x in color.get_width():
			if mask.get_pixel(x, y).a > 0.0:
				out.set_pixel(x, y, color.get_pixel(x, y))

	return ImageTexture.create_from_image(out)

static func placeholder_icon() -> Texture2D:
	return PixelTheme.pixel_icon(16, 16, func(image: Image):
		image.fill_rect(Rect2i(0, 0, 16, 16), PixelTheme.LINE)
		image.fill_rect(Rect2i(2, 2, 12, 12), PixelTheme.PAPER_SUNKEN))

# screen to world

# screen pixels per cell of a sprite, the ghost's scale
static func world_scale(viewport: Viewport) -> float:
	var camera := viewport.get_camera_2d() if viewport else null
	var zoom := camera.zoom.y if camera else 1.0
	return Steering.cell_pixels() * zoom

# a point on the screen to sim units through the active camera
func screen_to_units(screen: Vector2) -> Vector2:
	var viewport := get_viewport()
	var camera := viewport.get_camera_2d() if viewport else null
	var pixels := screen

	if camera:
		var view_size := viewport.get_visible_rect().size
		pixels = camera.get_screen_center_position() + (screen - view_size * 0.5) / camera.zoom

	return pixels / Steering.ppu()

# where a plain click spawns, on the screen
func click_spot() -> Vector2:
	var view_size := get_viewport().get_visible_rect().size
	return view_size * 0.5 + view_size * CLICK_SPOT

# the panel's window, drops here spawn nothing
func over_window(screen: Vector2) -> bool:
	return window.get_global_rect().has_point(screen)

# the drag

func is_dragging() -> bool:
	return dragging

# a card was pressed, the drag starts once the cursor pulls away
func arm_drag(entry: Entry, screen: Vector2) -> void:
	if entry == null or not entry.enabled:
		return

	cancel_drag()
	drag_entry = entry
	drag_from = screen
	dragging = false

# motion, the release, the wheel and the keys of a pressed card. true when
# the event was the drag's
func handle_drag_event(event: InputEvent, screen: Vector2) -> bool:
	if drag_entry == null:
		return false

	if event is InputEventMouseMotion:
		if dragging:
			update_drag(screen)
			return true

		if screen.distance_to(drag_from) >= DRAG_THRESHOLD or not drag_entry.get_global_rect().has_point(screen):
			begin_entry_drag(drag_entry, screen)
			return true

		return false

	if event is InputEventMouseButton:
		if Controls.released(event, Controls.SPAWN_GRAB):
			if dragging:
				end_drag(screen)
			else:
				var entry := drag_entry
				drag_entry = null
				click_entry(entry)
			return true

	if not dragging:
		return false

	if Controls.pressed(event, Controls.SPAWN_ROTATE_LEFT, true):
		rotate_drag(-ROTATE_STEP)
		return true

	if Controls.pressed(event, Controls.SPAWN_ROTATE_RIGHT, true):
		rotate_drag(ROTATE_STEP)
		return true

	if Controls.pressed(event, Controls.SPAWN_DRAG_CANCEL, true):
		cancel_drag()
		return true

	return false

# starts a drag of the kind's card, at the mouse unless a point is given
func begin_drag(kind: SpawnRequest.Kind, screen := Vector2.INF) -> bool:
	return begin_entry_drag(entry_for(kind), screen)

func begin_entry_drag(entry: Entry, screen := Vector2.INF) -> bool:
	if entry == null or not entry.enabled:
		return false

	if screen == Vector2.INF:
		screen = get_viewport().get_mouse_position()

	drag_entry = entry
	drag_from = screen
	dragging = true
	drag_rotation = 0.0
	ghost.texture = entry.art
	ghost.label = entry.label
	ghost.cells = entry.art_cells()
	ghost.angle = 0.0
	ghost.visible = true
	update_drag(screen)
	drag_started.emit(entry)
	return true

func update_drag(screen: Vector2) -> void:
	if not dragging:
		return

	ghost.screen = screen
	ghost.angle = drag_rotation
	ghost.scale_by = world_scale(get_viewport())
	ghost.queue_redraw()

func rotate_drag(by: float) -> void:
	if not dragging:
		return

	drag_rotation = wrapf(drag_rotation + by, -PI, PI)
	update_drag(ghost.screen)

# lets go: over the world spawns the card's kind there with the ghost's
# facing, over the panel spawns nothing
func end_drag(screen: Vector2) -> SpawnRequest:
	if not dragging:
		return null

	var entry := drag_entry
	var rotation := drag_rotation
	cancel_drag()

	if over_window(screen):
		return null

	return spawn_entry(entry, screen_to_units(screen), rotation)

func cancel_drag() -> void:
	var was_dragging := dragging
	drag_entry = null
	dragging = false
	drag_rotation = 0.0

	if ghost:
		ghost.visible = false

	if was_dragging:
		drag_ended.emit()

# a plain click: the click spot, or under the cursor when the toggle is on
func click_entry(entry: Entry) -> SpawnRequest:
	if entry == null or not entry.enabled:
		return null

	var screen := get_viewport().get_mouse_position() if spawn_at_cursor else click_spot()
	return spawn_entry(entry, screen_to_units(screen), 0.0)

# the request for a card at a spot in units, placed at once
func spawn_entry(entry: Entry, at: Vector2, rotation := 0.0) -> SpawnRequest:
	var request: SpawnRequest

	if entry.is_rock():
		request = SpawnRequest.rock(entry.rock_props, at)
	else:
		request = SpawnRequest.enemy(entry.kind, at)

	request.rotation = rotation
	request.wait_for_room = false

	if entry.scale_cells > 0:
		request.set_meta(EnemyGun.META_SCALE_CELLS, entry.scale_cells)

	last_request = request
	dropped.emit(request)
	return SpawnBus.send(request)

# grabs

# the sprite under a screen point, one with a cell there first
func sprite_at(screen: Vector2) -> RegolithSprite:
	var world := RegolithWorld.active()

	if world == null or not world.is_inside_tree():
		return null

	var point := screen_to_units(screen) * Steering.ppu()
	var hits: Array = world.query_rect(Rect2(point, Vector2.ONE))

	for sprite in hits:
		if sprite is RegolithSprite and sprite.has_cell(sprite.world_to_cell(point)):
			return sprite

	for sprite in hits:
		if sprite is RegolithSprite:
			return sprite

	return null

func grab(screen: Vector2) -> bool:
	var sprite := sprite_at(screen)

	if sprite == null or not sprite.dynamic:
		return false

	grabbed = sprite
	return true

func release() -> bool:
	if grabbed == null:
		return false

	if is_instance_valid(grabbed):
		grabbed.linear_velocity = Vector2.ZERO

	grabbed = null
	return true
