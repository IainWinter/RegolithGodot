extends Node2D

@onready var world: RegolithWorld = $RegolithWorld

var editor: SpriteEditor
var debug_panel: DebugPanel

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		if editor:
			editor.close()
		else:
			open_editor()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		toggle_debug_panel()
		return

	if event is InputEventMouseButton and event.pressed:
		var radius := 6
		for sprite in get_tree().get_nodes_in_group("regolith"):
			var center: Vector2i = sprite.world_to_cell(get_global_mouse_position())
			if center.x < 0:
				continue
			for y in range(-radius, radius + 1):
				for x in range(-radius, radius + 1):
					if x * x + y * y > radius * radius:
						continue
					var cell := center + Vector2i(x, y)
					if event.button_index == MOUSE_BUTTON_LEFT:
						sprite.remove_cell(cell)
					elif event.button_index == MOUSE_BUTTON_RIGHT:
						sprite.burn_cell(cell, 200, 1)

func sprite_under_mouse() -> RegolithSprite:
	var point := get_global_mouse_position()
	var hits: Array = world.query_rect(Rect2(point, Vector2.ONE))

	for sprite in hits:
		if sprite is RegolithSprite and sprite.has_cell(sprite.world_to_cell(point)):
			return sprite

	for sprite in hits:
		if sprite is RegolithSprite:
			return sprite

	return null

func open_editor() -> void:
	if editor:
		return

	var sprite := sprite_under_mouse()
	if sprite == null:
		sprite = get_tree().get_first_node_in_group("player") as RegolithSprite

	editor = SpriteEditor.new()
	editor.path = sprite_source_path(sprite)
	editor.closed.connect(on_editor_closed)
	add_child(editor)
	get_tree().paused = true

func on_editor_closed() -> void:
	editor = null
	get_tree().paused = false

# the png a sprite was loaded from, the editor edits that file, not the sprite
static func sprite_source_path(sprite: RegolithSprite) -> String:
	if sprite == null or sprite.texture == null:
		return ""

	var res_path := sprite.texture.resource_path
	if res_path.get_extension() != "png":
		return ""

	return ProjectSettings.globalize_path(res_path)

func toggle_debug_panel() -> void:
	if debug_panel:
		debug_panel.queue_free()
		debug_panel = null
		return

	debug_panel = DebugPanel.new(world)
	add_child(debug_panel)
