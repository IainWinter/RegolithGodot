@tool
extends EditorPlugin

# the scenario level editor. handles the Scenario node family in the 2D
# viewport: the selected zone or placement draws bright with drag handles,
# every other zone under a Scenario in the edited scene draws faint so the
# whole layout reads, and dragging a handle writes the node's exports
# through the editor undo/redo. a "Scenario" menu on the canvas toolbar
# adds a Scenario or a zone, placement or player start under the selected
# Scenario, at the center of the view.
#
# beside the menu a "Preview" toggle flips the Scenario's preview export
# (the ScenarioPreview child under the Scenario draws the planned rocks,
# see Scenario.ensure_preview) and "Reroll seed" gives the selected zone,
# or every zone of the Scenario, a new seed. the same reroll sits as a
# button at the top of a zone's inspector. every change goes through the
# editor undo/redo and the zone setters replan the preview.
#
# geometry lives in ScenarioGizmos (unit tested), unit to pixel scale in
# Scenario.pixels_per_unit_of, so this file is only editor plumbing and
# drawing. same pattern as addons/regolith_debug: overlay points are
# global_canvas_transform * world pixels

enum Add { SCENARIO, BELT, ROCK_FIELD, SPAWN_ZONE, PLAYER_START, PLACEMENT, TURRET }

const TOOLBAR_NAME := "ScenarioToolbar"
const PREVIEW_TOGGLE_NAME := "Preview"
const REROLL_BUTTON_NAME := "RerollSeed"

const DEFAULT_ROCK_PROPS := "res://game/config/rocks/default_rock.tres"
const TURRET_SCALE_CELLS := 96

const COLOR_SCENARIO := Color(0.6, 0.8, 1.0)
const COLOR_BELT := Color(1.0, 0.65, 0.2)
const COLOR_ROCK_FIELD := Color(0.85, 0.6, 0.4)
const COLOR_SPAWN := Color(1.0, 0.35, 0.35)
const COLOR_PLAYER := Color(0.35, 1.0, 0.45)
const COLOR_PLACEMENT := Color(0.9, 0.45, 1.0)
const COLOR_HANDLE := Color(1.0, 1.0, 1.0)
const FAINT := 0.35
const LINE_WIDTH := 2.0

var toolbar: HBoxContainer
var menu: MenuButton
var preview_toggle: CheckBox
var reroll_button: Button
var inspector: ZoneInspector
var edited: Node2D
# {handle, old} while a handle is held
var drag := {}

func _enter_tree() -> void:
	var made := make_toolbar(_on_add, _on_preview_toggled, _on_reroll)
	toolbar = made["toolbar"]
	menu = made["menu"]
	preview_toggle = made["preview_toggle"]
	reroll_button = made["reroll_button"]
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)
	set_force_draw_over_forwarding_enabled()

	inspector = ZoneInspector.new()
	inspector.plugin = self
	add_inspector_plugin(inspector)

func _exit_tree() -> void:
	remove_inspector_plugin(inspector)
	inspector = null
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)
	toolbar.queue_free()
	toolbar = null
	menu = null
	preview_toggle = null
	reroll_button = null

# the canvas toolbar piece: the Add menu, the Preview toggle and the
# Reroll seed button, wired to the given callables. static and free of
# editor singletons so a test can build it, an EditorPlugin itself only
# exists inside the editor. gives {toolbar, menu, preview_toggle,
# reroll_button}
static func make_toolbar(on_add: Callable, on_preview_toggled: Callable, on_reroll: Callable) -> Dictionary:
	var bar := HBoxContainer.new()
	bar.name = TOOLBAR_NAME

	var add_menu := MenuButton.new()
	add_menu.name = "Menu"
	add_menu.text = "Scenario"
	add_menu.flat = true
	add_menu.tooltip_text = "Add scenario level nodes under the selected Scenario"

	var popup := add_menu.get_popup()
	popup.add_item("Add Scenario", Add.SCENARIO)
	popup.add_separator()
	popup.add_item("Add Asteroid Belt Zone", Add.BELT)
	popup.add_item("Add Rock Field Zone", Add.ROCK_FIELD)
	popup.add_item("Add Spawn Zone", Add.SPAWN_ZONE)
	popup.add_item("Add Player Start", Add.PLAYER_START)
	popup.add_item("Add Enemy Placement", Add.PLACEMENT)
	popup.add_item("Add Turret Placement", Add.TURRET)
	popup.id_pressed.connect(on_add)
	bar.add_child(add_menu)

	var toggle := CheckBox.new()
	toggle.name = PREVIEW_TOGGLE_NAME
	toggle.text = "Preview"
	toggle.flat = true
	toggle.button_pressed = true
	toggle.tooltip_text = "Draw the rocks and enemies the Scenario's zones will spawn, where they will land"
	toggle.toggled.connect(on_preview_toggled)
	bar.add_child(toggle)

	var reroll := Button.new()
	reroll.name = REROLL_BUTTON_NAME
	reroll.text = "Reroll seed"
	reroll.flat = true
	reroll.tooltip_text = "A new layout seed for the selected zone, or every zone of the Scenario"
	reroll.pressed.connect(on_reroll)
	bar.add_child(reroll)

	return {"toolbar": bar, "menu": add_menu, "preview_toggle": toggle, "reroll_button": reroll}

# preview toggle and reroll

func _on_preview_toggled(on: bool) -> void:
	var root := EditorInterface.get_edited_scene_root()

	if root == null:
		return

	var scenario := target_scenario(root)
	var targets: Array[Scenario] = [scenario] if scenario else scenarios_in(root)

	if targets.is_empty():
		return

	var undo_redo := get_undo_redo()
	undo_redo.create_action("Scenario preview %s" % ("on" if on else "off"))

	for target in targets:
		undo_redo.add_do_property(target, "preview", on)
		undo_redo.add_undo_property(target, "preview", target.preview)

	undo_redo.commit_action()

func _on_reroll() -> void:
	var root := EditorInterface.get_edited_scene_root()

	if root == null:
		return

	var selected := selected_node()

	if selected and selected.has_method("reroll_seed"):
		reroll([selected])
		return

	var scenario := target_scenario(root)

	if scenario == null:
		push_warning("Scenario: select a zone or a Scenario to reroll")
		return

	reroll(seeded_zones(scenario))

# the zones under a Scenario that carry a seed
static func seeded_zones(scenario: Scenario) -> Array[Node]:
	var out: Array[Node] = []

	for child in scenario.get_children():
		if child.has_method("reroll_seed"):
			out.append(child)

	return out

# new seeds on the zones as one undo step. the setters replan the preview
func reroll(zones: Array) -> void:
	if zones.is_empty():
		return

	var undo_redo := get_undo_redo()
	undo_redo.create_action("Reroll seed")

	for zone in zones:
		var old: int = zone.seed
		undo_redo.add_do_property(zone, "seed", ScenarioGizmos.fresh_seed(old))
		undo_redo.add_undo_property(zone, "seed", old)

	undo_redo.commit_action()
	update_overlays()

# the inspector's Reroll seed button on a zone with a seed, Reroll all
# seeds on a Scenario
class ZoneInspector extends EditorInspectorPlugin:
	# the RegolithScenarioPlugin that owns this, untyped so the inner class
	# can call its reroll
	var plugin

	func _can_handle(object: Object) -> bool:
		return handles_seed(object)

	static func handles_seed(object: Object) -> bool:
		return object is Scenario or (object is Node and object.has_method("reroll_seed"))

	func _parse_begin(object: Object) -> void:
		var button := Button.new()
		button.name = "RerollSeed"
		button.text = "Reroll all seeds" if object is Scenario else "Reroll seed"
		button.pressed.connect(_on_pressed.bind(object))
		add_custom_control(button)

	func _on_pressed(object: Object) -> void:
		if not is_instance_valid(object) or plugin == null:
			return

		if object is Scenario:
			plugin.reroll(plugin.seeded_zones(object))
		else:
			plugin.reroll([object])

func _handles(object: Object) -> bool:
	return handles_node(object)

# the node family this plugin edits, static so tests can ask without an
# editor
static func handles_node(object: Object) -> bool:
	return object is Scenario or object is AsteroidBeltZone or object is RockFieldZone \
		or object is SpawnZone or object is PlayerStart or object is EnemyPlacement

func _edit(object: Object) -> void:
	edited = object as Node2D
	drag = {}
	update_overlays()

func _make_visible(visible: bool) -> void:
	if not visible:
		edited = null
		drag = {}

	update_overlays()

# inspector edits redraw the handles, the toggle follows the edited
# Scenario's preview export
func _process(_delta: float) -> void:
	if alive(edited):
		update_overlays()

		var scenario := Scenario.scenario_of(edited)

		if scenario and preview_toggle and preview_toggle.button_pressed != scenario.preview:
			preview_toggle.set_pressed_no_signal(scenario.preview)

static func alive(node: Node) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree()

func canvas_xform() -> Transform2D:
	return EditorInterface.get_editor_viewport_2d().global_canvas_transform

# the selected node, bright, with its handles
func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not alive(edited):
		return

	var xform := canvas_xform()
	draw_node(overlay, xform, edited, 1.0)
	draw_handles(overlay, xform, handles_of(edited))

# every other zone in the edited scene, faint, so the layout reads while
# one piece is being edited
func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	var root := EditorInterface.get_edited_scene_root()

	if root == null:
		return

	var xform := canvas_xform()

	for scenario in scenarios_in(root):
		if scenario != edited:
			draw_node(overlay, xform, scenario, FAINT)

		for child in scenario.get_children():
			if child != edited and child is Node2D and handles_node(child):
				draw_node(overlay, xform, child, FAINT)

static func scenarios_in(root: Node) -> Array[Scenario]:
	var out: Array[Scenario] = []

	if root is Scenario:
		out.append(root)

	for child in root.get_children():
		out.append_array(scenarios_in(child))

	return out

# drawing

func draw_node(overlay: Control, xform: Transform2D, node: Node2D, alpha: float) -> void:
	var ppu := Scenario.pixels_per_unit_of(node)
	var zoom := xform.get_scale().x
	var center := xform * node.global_position

	if node is AsteroidBeltZone:
		var color := with_alpha(COLOR_BELT, alpha)
		draw_ring(overlay, center, node.inner_radius * ppu * zoom, color)
		draw_ring(overlay, center, node.outer_radius * ppu * zoom, color)
		draw_cross(overlay, center, 6.0, color)
		var dir := "cw" if node.clockwise else "ccw"
		draw_label(overlay, center + Vector2(0, -node.outer_radius * ppu * zoom - 6.0), "%s: %d rocks, %s" % [node.name, node.rock_count(), dir], color)
	elif node is RockFieldZone:
		var color := with_alpha(COLOR_ROCK_FIELD, alpha)
		var corners := ScenarioGizmos.rect_corners(node.global_position, node.size * 0.5 * ppu, node.global_rotation)
		draw_closed(overlay, xform, corners, color)
		draw_label(overlay, xform * corners[0] + Vector2(0, -6.0), "%s: %d rocks" % [node.name, node.rock_count()], color)
	elif node is SpawnZone:
		var color := with_alpha(COLOR_SPAWN, alpha)
		var top: Vector2

		if node.shape == SpawnZone.Shape.CIRCLE:
			draw_ring(overlay, center, node.radius * ppu * zoom, color)
			top = center + Vector2(0, -node.radius * ppu * zoom)
		else:
			var corners := ScenarioGizmos.rect_corners(node.global_position, node.size * 0.5 * ppu, node.global_rotation)
			draw_closed(overlay, xform, corners, color)
			top = xform * corners[0]

		draw_cross(overlay, center, 5.0, color)
		draw_label(overlay, top + Vector2(0, -6.0), "%s: %s x%d" % [node.name, kinds_text(node), node.max_alive], color)
	elif node is PlayerStart:
		var color := with_alpha(COLOR_PLAYER, alpha)
		var arrow := ScenarioGizmos.arrow_points(node.global_position, node.global_rotation, node.arrow_length * ppu)
		overlay.draw_line(center, xform * arrow[0], color, LINE_WIDTH)
		overlay.draw_line(xform * arrow[0], xform * arrow[1], color, LINE_WIDTH)
		overlay.draw_line(xform * arrow[0], xform * arrow[2], color, LINE_WIDTH)
		draw_ring(overlay, center, 0.5 * ppu * zoom, color)
		draw_label(overlay, center + Vector2(0, -0.5 * ppu * zoom - 6.0), "player start", color)
	elif node is EnemyPlacement:
		draw_placement(overlay, xform, node, ppu, alpha)
	elif node is Scenario:
		var color := with_alpha(COLOR_SCENARIO, alpha)
		draw_cross(overlay, center, 10.0, color)
		draw_label(overlay, center + Vector2(12.0, -4.0), node.name, color)

# the enemy's art from its scene, scaled to scale_cells when set, else a
# circle scale_cells across. a heading line shows the rotation either way
func draw_placement(overlay: Control, xform: Transform2D, node: EnemyPlacement, ppu: float, alpha: float) -> void:
	var color := with_alpha(COLOR_PLACEMENT, alpha)
	var cell_pixels := ppu / RegolithWorld.CELLS_PER_CHUNK
	var zoom := xform.get_scale().x
	var center := xform * node.global_position
	var texture := node.silhouette_texture()
	var radius_pixels := placement_radius_pixels(node, ppu)

	if texture:
		var size := texture.get_size()
		var fit := ScenarioGizmos.fit_scale(size, node.scale_cells)
		var rect := ScenarioGizmos.padded_art_rect(size, cell_pixels)
		overlay.draw_set_transform_matrix(xform * node.global_transform * Transform2D(0.0, Vector2.ONE * fit, 0.0, Vector2.ZERO))
		overlay.draw_texture_rect(texture, rect, false, Color(1.0, 1.0, 1.0, 0.75 * alpha))
		overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
	else:
		draw_ring(overlay, center, radius_pixels * zoom, color)

	var heading := node.global_position + Vector2.from_angle(node.global_rotation) * radius_pixels
	overlay.draw_line(center, xform * heading, color, LINE_WIDTH)
	draw_cross(overlay, center, 5.0, color)
	var text := node.gizmo_label() if node.scale_cells == 0 else "%s %d cells" % [node.gizmo_label(), node.scale_cells]
	draw_label(overlay, center + Vector2(0, -radius_pixels * zoom - 6.0), text, color)

# the heading and cells handles sit on this radius, world pixels
static func placement_radius_pixels(node: EnemyPlacement, ppu: float) -> float:
	var cell_pixels := ppu / RegolithWorld.CELLS_PER_CHUNK
	var cells := node.scale_cells

	if cells == 0:
		var texture := node.silhouette_texture()
		cells = int(maxf(texture.get_size().x, texture.get_size().y)) if texture else 16

	return maxi(cells, 4) * 0.5 * cell_pixels

static func kinds_text(zone: SpawnZone) -> String:
	var names := PackedStringArray()

	for kind in zone.kinds:
		names.append(String(SpawnRequest.Kind.keys()[kind]).to_lower())

	return ", ".join(names) if not names.is_empty() else "nothing"

static func with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha)

func draw_ring(overlay: Control, center: Vector2, radius: float, color: Color) -> void:
	if radius > 0.5:
		overlay.draw_arc(center, radius, 0.0, TAU, 96, color, LINE_WIDTH, true)

func draw_cross(overlay: Control, at: Vector2, half: float, color: Color) -> void:
	overlay.draw_line(at + Vector2(-half, 0), at + Vector2(half, 0), color, LINE_WIDTH)
	overlay.draw_line(at + Vector2(0, -half), at + Vector2(0, half), color, LINE_WIDTH)

func draw_closed(overlay: Control, xform: Transform2D, points: PackedVector2Array, color: Color) -> void:
	var screen := PackedVector2Array()

	for p in points:
		screen.append(xform * p)

	screen.append(screen[0])
	overlay.draw_polyline(screen, color, LINE_WIDTH, true)

func draw_label(overlay: Control, at: Vector2, text: String, color: Color) -> void:
	var font := overlay.get_theme_default_font()
	var size := overlay.get_theme_default_font_size()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	overlay.draw_string(font, at + Vector2(-width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func draw_handles(overlay: Control, xform: Transform2D, handles: Array[Dictionary]) -> void:
	for handle in handles:
		var at: Vector2 = xform * handle["pos"]
		overlay.draw_circle(at, ScenarioGizmos.HANDLE_RADIUS - 2.0, COLOR_HANDLE)
		overlay.draw_arc(at, ScenarioGizmos.HANDLE_RADIUS - 1.0, 0.0, TAU, 24, Color(0, 0, 0, 0.8), 1.5, true)

# handles: each is {pos: world pixels, mode, property, index}

func handles_of(node: Node2D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ppu := Scenario.pixels_per_unit_of(node)
	var center := node.global_position

	if node is AsteroidBeltZone:
		add_ring_handles(out, center, node.inner_radius * ppu, "inner_radius")
		add_ring_handles(out, center, node.outer_radius * ppu, "outer_radius")
	elif node is RockFieldZone:
		add_rect_handles(out, center, node.size * 0.5 * ppu, node.global_rotation, "size")
	elif node is SpawnZone:
		if node.shape == SpawnZone.Shape.CIRCLE:
			add_ring_handles(out, center, node.radius * ppu, "radius")
		else:
			add_rect_handles(out, center, node.size * 0.5 * ppu, node.global_rotation, "size")
	elif node is PlayerStart:
		var arrow := ScenarioGizmos.arrow_points(center, node.global_rotation, node.arrow_length * ppu)
		out.append({"pos": arrow[0], "mode": "angle", "property": "rotation", "index": 0})
	elif node is EnemyPlacement:
		var radius := placement_radius_pixels(node, ppu)
		out.append({"pos": center + Vector2.from_angle(node.global_rotation) * radius, "mode": "angle", "property": "rotation", "index": 0})
		out.append({"pos": center + Vector2.from_angle(node.global_rotation + PI * 0.5) * radius, "mode": "cells", "property": "scale_cells", "index": 0})

	return out

static func add_ring_handles(out: Array[Dictionary], center: Vector2, radius: float, property: String) -> void:
	var points := ScenarioGizmos.ring_handles(center, radius)

	for i in points.size():
		out.append({"pos": points[i], "mode": "ring", "property": property, "index": i})

static func add_rect_handles(out: Array[Dictionary], center: Vector2, half: Vector2, angle: float, property: String) -> void:
	var points := ScenarioGizmos.rect_handles(center, half, angle)

	for i in points.size():
		out.append({"pos": points[i], "mode": "rect", "property": property, "index": i})

# the export value a drag of handle to world_point (world pixels) asks for
func handle_value(node: Node2D, handle: Dictionary, world_point: Vector2) -> Variant:
	var ppu := Scenario.pixels_per_unit_of(node)
	var center := node.global_position
	var property: String = handle["property"]

	match handle["mode"]:
		"ring":
			var radius := ScenarioGizmos.radius_from_drag(center, world_point) / ppu

			if node is AsteroidBeltZone:
				# the rings never cross
				if property == "inner_radius":
					radius = minf(radius, node.outer_radius)
				else:
					radius = maxf(radius, node.inner_radius)

			return maxf(radius, 0.0)
		"rect":
			var old_half: Vector2 = node.get(property) * 0.5 * ppu
			var half := ScenarioGizmos.half_from_drag(center, node.global_rotation, handle["index"], world_point, old_half)
			return (half * 2.0 / ppu).max(Vector2.ONE * 0.25)
		"angle":
			var wanted := (world_point - center).angle()
			return node.rotation + angle_difference(node.global_rotation, wanted)
		"cells":
			var cell_pixels := ppu / RegolithWorld.CELLS_PER_CHUNK
			return int(round(center.distance_to(world_point) / cell_pixels * 2.0))

	return node.get(property)

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not alive(edited):
		return false

	var xform := canvas_xform()

	if event is InputEventMouseButton and Controls.matches(event, Controls.SCENARIO_DRAG):
		if event.pressed:
			var handles := handles_of(edited)
			var screen := PackedVector2Array()

			for handle in handles:
				screen.append(xform * handle["pos"])

			var hit := ScenarioGizmos.hit_handle(event.position, screen)

			if hit < 0:
				return false

			drag = {"handle": handles[hit], "old": edited.get(handles[hit]["property"])}
			return true
		elif not drag.is_empty():
			commit_drag()
			return true
	elif event is InputEventMouseMotion and not drag.is_empty():
		var handle: Dictionary = drag["handle"]
		edited.set(handle["property"], handle_value(edited, handle, xform.affine_inverse() * event.position))
		update_overlays()
		return true

	return false

# the value is already on the node, the action records it for undo
func commit_drag() -> void:
	var handle: Dictionary = drag["handle"]
	var property: String = handle["property"]
	var undo_redo := get_undo_redo()
	undo_redo.create_action("Scenario: %s %s" % [edited.name, property])
	undo_redo.add_do_property(edited, property, edited.get(property))
	undo_redo.add_undo_property(edited, property, drag["old"])
	undo_redo.commit_action(false)
	drag = {}

# add menu

func selected_node() -> Node:
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	return nodes[0] if not nodes.is_empty() else null

# the Scenario a new zone goes under: the selection's, else the edited
# root when it is one, else the first Scenario child of the root
func target_scenario(root: Node) -> Scenario:
	var selected := selected_node()
	var scenario := Scenario.scenario_of(selected) if selected else null

	if scenario:
		return scenario

	var found := scenarios_in(root)
	return found[0] if not found.is_empty() else null

func view_center_world() -> Vector2:
	var viewport := EditorInterface.get_editor_viewport_2d()
	return viewport.global_canvas_transform.affine_inverse() * (viewport.get_visible_rect().size * 0.5)

func _on_add(id: int) -> void:
	var root := EditorInterface.get_edited_scene_root()

	if root == null:
		push_warning("Scenario: open a scene first")
		return

	var parent: Node
	var node: Node2D

	if id == Add.SCENARIO:
		var selected := selected_node()
		parent = selected if selected else root
		node = Scenario.new()
		node.name = "Scenario"
	else:
		parent = target_scenario(root)

		if parent == null:
			push_warning("Scenario: add a Scenario first (Scenario > Add Scenario) or select one")
			return

		node = make_node(id)

	var center := view_center_world()
	node.position = parent.global_transform.affine_inverse() * center if parent is Node2D else center

	var undo_redo := get_undo_redo()
	undo_redo.create_action("Add %s" % node.name)
	undo_redo.add_do_method(parent, "add_child", node, true)
	undo_redo.add_do_method(node, "set_owner", root)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(parent, "remove_child", node)
	undo_redo.commit_action()

	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)

func make_node(id: int) -> Node2D:
	match id:
		Add.BELT:
			var belt := AsteroidBeltZone.new()
			belt.name = "AsteroidBeltZone"
			belt.rock_props = default_rock_props()
			return belt
		Add.ROCK_FIELD:
			var field := RockFieldZone.new()
			field.name = "RockFieldZone"
			field.rock_props = default_rock_props()
			return field
		Add.SPAWN_ZONE:
			var zone := SpawnZone.new()
			zone.name = "SpawnZone"
			return zone
		Add.PLAYER_START:
			var start := PlayerStart.new()
			start.name = "PlayerStart"
			return start
		Add.TURRET:
			var turret := EnemyPlacement.new()
			turret.name = "Turret"
			turret.kind = SpawnRequest.Kind.BASE
			turret.kind_name = &"turret"
			turret.scale_cells = TURRET_SCALE_CELLS
			turret.label = "turret"
			return turret

	var placement := EnemyPlacement.new()
	placement.name = "EnemyPlacement"
	return placement

static func default_rock_props() -> RockProps:
	return load(DEFAULT_ROCK_PROPS) as RockProps if ResourceLoader.exists(DEFAULT_ROCK_PROPS) else null
