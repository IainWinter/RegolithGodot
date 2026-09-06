extends Node2D

@onready var world: RegolithWorld = $RegolithWorld

var editor: SpriteEditor
var debug_panel: DebugPanel

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
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

# f2 opens the sprite editor on the sprite under the mouse, or the player.
# the world pauses while it is open and resumes when it closes

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

	if sprite == null:
		return

	editor = SpriteEditor.new()
	editor.target = sprite
	editor.closed.connect(on_editor_closed)
	add_child(editor)
	get_tree().paused = true

func on_editor_closed() -> void:
	editor = null
	get_tree().paused = false

func _on_sprite_split(_source: RegolithSprite, piece: RegolithSprite) -> void:
	piece.add_to_group("regolith")

# f3 toggles the debug panel: monitors, pause and step, debug lines

func toggle_debug_panel() -> void:
	if debug_panel:
		debug_panel.queue_free()
		debug_panel = null
		return

	debug_panel = DebugPanel.new(world)
	add_child(debug_panel)
