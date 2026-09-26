extends Node2D

@onready var world: RegolithWorld = $RegolithWorld

var editor: SpriteEditorWindow
var debug_panel: DebugPanel

# the editor and debug panel toggles (Controls.EDITOR_TOGGLE / DEBUG_PANEL) live on a node that keeps taking input while the tree
# is paused (pause menu, death menu, the editor itself), Main is pausable
# so its own _unhandled_input stops with the game
class Hotkeys extends Node:
	var main: Node2D

	func _init(of: Node2D) -> void:
		main = of
		name = "Hotkeys"
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(Controls.EDITOR_TOGGLE):
			main.toggle_editor()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(Controls.DEBUG_PANEL):
			main.toggle_debug_panel()
			get_viewport().set_input_as_handled()

func _ready() -> void:
	add_child(Hotkeys.new(self))

func _unhandled_input(event: InputEvent) -> void:
	var dig := event.is_action_pressed(Controls.DEBUG_DIG)
	var burn := event.is_action_pressed(Controls.DEBUG_BURN)

	if dig or burn:
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
					if dig:
						sprite.remove_cell(cell)
					elif burn:
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

func toggle_editor() -> void:
	if editor:
		editor.close()
	else:
		open_editor()

# the editor holds the tree paused on its own, GameState stays PLAYING and
# ignores the pause action while it is open. closing hands the pause back
# to whatever the state wants
func open_editor() -> void:
	if editor:
		return

	var sprite := sprite_under_mouse()
	if sprite == null:
		sprite = get_tree().get_first_node_in_group("player") as RegolithSprite

	editor = SpriteEditorWindow.new()
	editor.path = sprite_source_path(sprite)
	editor.closed.connect(on_editor_closed)
	add_child(editor)
	get_tree().paused = true

func on_editor_closed() -> void:
	editor = null
	get_tree().paused = GameState.wants_paused()

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
