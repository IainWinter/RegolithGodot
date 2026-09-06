extends CanvasLayer
class_name MultiSpriteEditor

# in game tool to lay out several RegolithSprites and pin them together with
# joints. arrange while static, press play to let the world solve them

enum Mode { MOVE, JOINT }

@export var world: RegolithWorld
@export var root: Node2D

# the look every sprite placed here gets
@export var sprite_material: Material
@export var rope_material: Material

var mode := Mode.MOVE
var playing := false

var sprites: Array[RegolithSprite] = []
var sources := {}
var rest_positions := {}
var rest_rotations := {}
var joints: Array[Dictionary] = []

var dragging: RegolithSprite
var drag_offset := Vector2.ZERO
var joint_first: RegolithSprite

var panel: PanelContainer
var file_dialog: FileDialog
var status: Label
var overlay: Node2D
var play_button: Button

signal closed

func _ready() -> void:
	layer = 10

	if world == null:
		world = RegolithWorld.active()

	if root == null:
		root = get_parent() as Node2D

	build_ui()

	overlay = JointOverlay.new()
	overlay.editor = self
	overlay.top_level = true
	overlay.z_index = 100
	root.add_child(overlay)

func close() -> void:
	if overlay:
		overlay.queue_free()

	closed.emit()
	queue_free()

func build_ui() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -240
	panel.offset_top = 16
	panel.offset_right = -16
	panel.offset_bottom = -16
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Multi Sprite"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var group := ButtonGroup.new()
	var modes := HBoxContainer.new()
	box.add_child(modes)
	for entry in [["Move", Mode.MOVE], ["Joint", Mode.JOINT]]:
		var button := Button.new()
		button.text = entry[0]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = entry[1] == mode
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): mode = entry[1]; joint_first = null)
		modes.add_child(button)

	box.add_child(action("Add Sprite", func(): show_dialog(FileDialog.FILE_MODE_OPEN_FILE, "add")))
	box.add_child(action("Remove Last", remove_last))
	box.add_child(action("Clear Joints", clear_joints))

	box.add_child(HSeparator.new())

	play_button = action("Play", toggle_play)
	box.add_child(play_button)

	box.add_child(HSeparator.new())

	var files := HBoxContainer.new()
	box.add_child(files)
	files.add_child(action("Load", func(): show_dialog(FileDialog.FILE_MODE_OPEN_FILE, "load")))
	files.add_child(action("Save", func(): show_dialog(FileDialog.FILE_MODE_SAVE_FILE, "save")))

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(status)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	box.add_child(action("Done", close))

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.size = Vector2i(720, 480)
	file_dialog.file_selected.connect(on_file_selected)
	add_child(file_dialog)

	update_status()

func action(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_press)
	return button

func update_status() -> void:
	status.text = "%d sprites, %d joints%s" % [sprites.size(), joints.size(), "\nplaying" if playing else ""]

func mouse_over_ui() -> bool:
	var mouse := panel.get_viewport().get_mouse_position()
	return panel.get_global_rect().has_point(mouse) or file_dialog.visible

func mouse_world() -> Vector2:
	return root.get_global_mouse_position()

func sprite_at(point: Vector2) -> RegolithSprite:
	for sprite in world.query_rect(Rect2(point, Vector2.ONE)):
		if sprite in sprites and sprite.has_cell(sprite.world_to_cell(point)):
			return sprite

	for sprite in world.query_rect(Rect2(point, Vector2.ONE)):
		if sprite in sprites:
			return sprite

	return null

func _unhandled_input(event: InputEvent) -> void:
	if playing or mouse_over_ui():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point := mouse_world()

		if event.pressed:
			var hit := sprite_at(point)

			if mode == Mode.MOVE and hit:
				dragging = hit
				drag_offset = hit.global_position - point

			elif mode == Mode.JOINT and hit:
				if joint_first == null or joint_first == hit:
					joint_first = hit
				else:
					add_joint(joint_first, hit, point)
					joint_first = null
		else:
			dragging = null

	elif event is InputEventMouseMotion and dragging:
		dragging.global_position = mouse_world() + drag_offset

	elif event is InputEventKey and event.pressed and dragging == null and mode == Mode.MOVE:
		var hit := sprite_at(mouse_world())
		if hit and (event.keycode == KEY_Q or event.keycode == KEY_E):
			hit.global_rotation += (-1.0 if event.keycode == KEY_Q else 1.0) * PI / 16.0

func add_sprite(texture_path: String, position: Vector2, rotation: float) -> RegolithSprite:
	var color := Image.load_from_file(texture_path)
	if color == null:
		status.text = "could not load " + texture_path.get_file()
		return null

	var mask_path := texture_path.get_basename() + "_mask.png"
	var mask: Image = Image.load_from_file(mask_path) if FileAccess.file_exists(mask_path) else null

	var sprite := RegolithSprite.new()
	sprite.material = sprite_material
	sprite.rope_material = rope_material
	sprite.dynamic = false
	sprite.global_position = position
	sprite.global_rotation = rotation
	root.add_child(sprite)
	sprite.load_from_images(color, mask)

	sprites.append(sprite)
	sources[sprite] = texture_path
	update_status()
	return sprite

func remove_last() -> void:
	if sprites.is_empty():
		return

	var sprite: RegolithSprite = sprites.pop_back()
	sources.erase(sprite)

	for i in range(joints.size() - 1, -1, -1):
		if joints[i]["a"] == sprite or joints[i]["b"] == sprite:
			world.remove_joint(joints[i]["id"])
			joints.remove_at(i)

	sprite.queue_free()
	update_status()

func add_joint(a: RegolithSprite, b: RegolithSprite, point: Vector2) -> void:
	var id := world.add_joint(a, b, point)
	if id < 0:
		return

	joints.append({"id": id, "a": a, "b": b, "point": point})
	update_status()

func clear_joints() -> void:
	world.clear_joints()
	joints.clear()
	update_status()

func toggle_play() -> void:
	playing = not playing
	play_button.text = "Stop" if playing else "Play"

	if playing:
		for sprite in sprites:
			rest_positions[sprite] = sprite.global_position
			rest_rotations[sprite] = sprite.global_rotation
			sprite.dynamic = true
	else:
		for sprite in sprites:
			sprite.dynamic = false
			sprite.linear_velocity = Vector2.ZERO
			sprite.angular_velocity = 0.0
			if rest_positions.has(sprite):
				sprite.global_position = rest_positions[sprite]
				sprite.global_rotation = rest_rotations[sprite]

	update_status()

func show_dialog(file_mode: FileDialog.FileMode, purpose: String) -> void:
	file_dialog.file_mode = file_mode
	file_dialog.set_meta("purpose", purpose)
	file_dialog.filters = PackedStringArray(["*.png ; PNG"] if purpose == "add" else ["*.json ; Multi sprite"])
	file_dialog.popup_centered()

func on_file_selected(path: String) -> void:
	match file_dialog.get_meta("purpose"):
		"add":
			var sprite := add_sprite(path, root.get_viewport().get_camera_2d().get_screen_center_position() if root.get_viewport().get_camera_2d() else Vector2.ZERO, 0.0)
			if sprite and sprites.size() > 1:
				sprite.global_position += Vector2(sprites[-2].get_cell_count().x * RegolithWorld.pixels_per_unit() / RegolithWorld.CELLS_PER_CHUNK, 0)
		"save":
			save_to(path)
		"load":
			load_from(path)

func save_to(path: String) -> void:
	var ppu := RegolithWorld.pixels_per_unit()
	var data := {"sprites": [], "joints": []}

	for sprite in sprites:
		data["sprites"].append({
			"texture": sources.get(sprite, ""),
			"position": [sprite.global_position.x / ppu, sprite.global_position.y / ppu],
			"rotation": sprite.global_rotation,
		})

	for joint in joints:
		data["joints"].append({
			"a": sprites.find(joint["a"]),
			"b": sprites.find(joint["b"]),
			"point": [joint["point"].x / ppu, joint["point"].y / ppu],
		})

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "  "))
		status.text = "saved " + path.get_file()

func load_from(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		status.text = "bad file " + path.get_file()
		return

	if playing:
		toggle_play()

	clear_joints()
	while not sprites.is_empty():
		remove_last()

	var ppu := RegolithWorld.pixels_per_unit()

	for entry in data.get("sprites", []):
		add_sprite(entry["texture"], Vector2(entry["position"][0], entry["position"][1]) * ppu, entry["rotation"])

	for entry in data.get("joints", []):
		var a: int = entry["a"]
		var b: int = entry["b"]
		if a >= 0 and b >= 0 and a < sprites.size() and b < sprites.size():
			add_joint(sprites[a], sprites[b], Vector2(entry["point"][0], entry["point"][1]) * ppu)

	update_status()


class JointOverlay extends Node2D:
	var editor: MultiSpriteEditor

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if editor == null:
			return

		draw_set_transform(Vector2.ZERO)

		var cell_px := RegolithWorld.pixels_per_unit() / RegolithWorld.CELLS_PER_CHUNK

		for joint in editor.joints:
			var point: Vector2 = editor.world.get_joint_position(joint["id"])
			draw_circle(point, cell_px * 2.0, Color(1.0, 0.85, 0.2, 0.9))

		if editor.joint_first:
			draw_arc(editor.joint_first.global_position, cell_px * 6.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.2, 0.9), 1.0)

		if editor.dragging:
			draw_arc(editor.dragging.global_position, cell_px * 6.0, 0.0, TAU, 24, Color(0.4, 0.8, 1.0, 0.9), 1.0)
