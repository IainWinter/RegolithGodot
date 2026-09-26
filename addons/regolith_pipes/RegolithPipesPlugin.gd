@tool
extends EditorPlugin

# hand placement of pipes on a PipeFrame, the old editor.py in the 2D editor.
# while a PipeFrame is selected the toolbar sits in the canvas editor menu
# and the viewport overlay draws the zone's layout lattice, the painted cells
# and their connections. clicks on the zone go through the layout resource:
#
#   Pipe brush   left drag paints cells, each step links to the previous cell
#                so a stroke is a run; a click links to painted neighbours.
#                right click / drag erases. Shift + left click near the edge
#                between two cells toggles that one connection
#   Erase brush  left drag erases
#   Gauge brush  left click sets a painted cell's radius to the toolbar value,
#                right click puts it back on the layer default
#   Select       nothing is consumed, so the Control handles move and resize
#                the zone as usual
#
# every stroke is one undo step (EditorUndoRedoManager), and the frame
# regenerates itself after the mouse is released. the plugin draws in the
# frame's local pixels through global_canvas_transform * global_transform like
# RegolithDebugPlugin does

const Toolbar := preload("res://addons/regolith_pipes/PipeToolbar.gd")

# clicks this close (viewport pixels) to the zone edge stay with the editor's
# resize handles
const HANDLE_MARGIN := 8.0
# how far from a cell edge a Shift-click still means that edge, in cell units
const EDGE_REACH := 0.35

const COLOR_ZONE := Color(0.47, 0.86, 1.0, 0.9)
const COLOR_GRID := Color(1.0, 1.0, 1.0, 0.12)
const COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.25)
const COLOR_LAYER: Array[Color] = [Color(0.55, 0.75, 1.0, 0.85), Color(1.0, 0.59, 0.24, 0.95)]
const COLOR_EDGE_HINT := Color(1.0, 1.0, 0.4, 0.9)

var toolbar: Toolbar
var frame: PipeFrame
var hover := Vector2i(-1, -1)
var hover_edge := Vector2i(-1, -1)

# the running stroke
var stroke_button := 0
var stroke_last := Vector2i(-1, -1)
var stroke_grid := PackedByteArray()
var stroke_sizes := PackedFloat32Array()

func _enter_tree() -> void:
	toolbar = Toolbar.new()
	toolbar.auto_fill_pressed.connect(_on_auto_fill)
	toolbar.clear_pressed.connect(_on_clear)
	toolbar.regenerate_pressed.connect(_on_regenerate)
	toolbar.tool_changed.connect(func(_tool: int): update_overlays())
	toolbar.layer_changed.connect(func(_layer: int): update_overlays())
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)
	toolbar.hide()

func _exit_tree() -> void:
	_set_frame(null)
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)
	toolbar.queue_free()
	toolbar = null

func _handles(object: Object) -> bool:
	return object is PipeFrame

func _edit(object: Object) -> void:
	_set_frame(object as PipeFrame)

func _make_visible(visible: bool) -> void:
	if not visible:
		_set_frame(null)

	if toolbar:
		toolbar.visible = visible and frame != null

func _set_frame(next: PipeFrame) -> void:
	if frame == next:
		return

	if frame != null and is_instance_valid(frame):
		frame.regenerated.disconnect(_on_frame_regenerated)
		frame.resized.disconnect(update_overlays)

	frame = next
	hover = Vector2i(-1, -1)
	if frame != null:
		frame.regenerated.connect(_on_frame_regenerated)
		frame.resized.connect(update_overlays)

	if toolbar:
		toolbar.visible = frame != null
		toolbar.show_frame(frame)

	update_overlays()

func _on_frame_regenerated() -> void:
	if toolbar:
		toolbar.show_frame(frame)

	update_overlays()

# --- transforms -----------------------------------------------------------

# frame local pixels -> viewport overlay pixels
func _to_overlay() -> Transform2D:
	return EditorInterface.get_editor_viewport_2d().global_canvas_transform * frame.get_global_transform()

func _to_local(viewport_pos: Vector2) -> Vector2:
	return _to_overlay().affine_inverse() * viewport_pos

# inside the zone but clear of the editor's resize handles
func _inside_zone(viewport_pos: Vector2) -> bool:
	var xf := _to_overlay()
	var zone := Vector2(frame.zone_size())
	var top_left := xf * Vector2.ZERO
	var bottom_right := xf * zone
	var rect := Rect2(top_left, bottom_right - top_left).abs().grow(-HANDLE_MARGIN)
	return rect.has_point(viewport_pos)

# --- input -------------------------------------------------------------

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if frame == null or not is_instance_valid(frame) or toolbar.tool == Toolbar.Tool.SELECT:
		return false

	if event is InputEventMouseMotion:
		return _on_motion(event)

	if event is InputEventMouseButton:
		return _on_button(event)

	return false

func _on_motion(event: InputEventMouseMotion) -> bool:
	var local := _to_local(event.position)
	var cell := frame.cell_at(local)
	hover = cell
	hover_edge = _edge_neighbour(local, cell) if _edge_held(event) and toolbar.tool == Toolbar.Tool.PIPE else Vector2i(-1, -1)
	update_overlays()

	if stroke_button == 0:
		return false

	if cell != stroke_last and cell.x >= 0:
		_apply(cell, true)
		stroke_last = cell

	return true

# the edge modifier (Controls.PIPES_EDGE, Shift) held on this event
func _edge_held(event: InputEventWithModifiers) -> bool:
	return Controls.modifier_held(event, Controls.PIPES_EDGE)

func _on_button(event: InputEventMouseButton) -> bool:
	if not Controls.matches(event, Controls.PIPES_PAINT) and not Controls.matches(event, Controls.PIPES_ERASE):
		return false

	if event.pressed:
		if stroke_button != 0 or not _inside_zone(event.position):
			return false

		var local := _to_local(event.position)
		var cell := frame.cell_at(local)
		if cell.x < 0:
			return false

		var layout := frame.ensure_layout()
		stroke_grid = layout.grid.duplicate()
		stroke_sizes = layout.sizes.duplicate()
		stroke_button = event.button_index
		stroke_last = cell

		if _edge_held(event) and Controls.matches(event, Controls.PIPES_PAINT) and toolbar.tool == Toolbar.Tool.PIPE:
			var other := _edge_neighbour(local, cell)
			if other.x >= 0:
				layout.toggle_edge(toolbar.layer, cell, other)
			else:
				layout.paint(toolbar.layer, cell.x, cell.y)
		else:
			_apply(cell, false)

		update_overlays()
		return true

	if event.button_index != stroke_button:
		return false

	_end_stroke()
	return true

# one brush step. `drag` links a Pipe step to the previous cell only
func _apply(cell: Vector2i, drag: bool) -> void:
	var layout := frame.ensure_layout()
	var layer: int = toolbar.layer
	var erase: bool = Controls.has_mouse_button(Controls.PIPES_ERASE, stroke_button) or toolbar.tool == Toolbar.Tool.ERASE
	match toolbar.tool:
		Toolbar.Tool.GAUGE:
			layout.set_gauge(layer, cell.x, cell.y, 0.0 if Controls.has_mouse_button(Controls.PIPES_ERASE, stroke_button) else toolbar.gauge)
		_:
			if erase:
				layout.erase(layer, cell.x, cell.y)
			elif drag and stroke_last.x >= 0 and PipeLayout.direction_between(stroke_last, cell) >= 0:
				layout.connect_cells(layer, stroke_last, cell)
			else:
				layout.paint(layer, cell.x, cell.y)

	update_overlays()

func _end_stroke() -> void:
	if stroke_button == 0:
		return

	stroke_button = 0
	stroke_last = Vector2i(-1, -1)
	var layout := frame.layout
	if layout == null:
		return

	if layout.grid == stroke_grid and layout.sizes == stroke_sizes:
		return

	var undo := get_undo_redo()
	undo.create_action("Paint pipes", UndoRedo.MERGE_DISABLE, frame)
	undo.add_do_method(layout, "restore", layout.grid.duplicate(), layout.sizes.duplicate())
	undo.add_undo_method(layout, "restore", stroke_grid, stroke_sizes)
	undo.commit_action(false)
	frame.queue_regenerate()

# the 4-neighbour across the cell edge nearest to a local point, when the
# point is close enough to that edge, else (-1, -1)
func _edge_neighbour(local: Vector2, cell: Vector2i) -> Vector2i:
	if cell.x < 0:
		return Vector2i(-1, -1)

	var rect := frame.cell_rect(cell)
	var u := (local - rect.position) / rect.size
	var d := -1
	var best := EDGE_REACH
	if u.y < best:
		best = u.y
		d = 0
	if 1.0 - u.x < best:
		best = 1.0 - u.x
		d = 1
	if 1.0 - u.y < best:
		best = 1.0 - u.y
		d = 2
	if u.x < best:
		d = 3

	if d < 0:
		return Vector2i(-1, -1)

	var other := Vector2i(cell.x + PipeGenerator.DIR_X[d], cell.y + PipeGenerator.DIR_Y[d])
	var g := frame.grid_size()
	if other.x < 0 or other.y < 0 or other.x >= g.x or other.y >= g.y:
		return Vector2i(-1, -1)

	return other

# --- toolbar actions ------------------------------------------------------

func _on_auto_fill() -> void:
	if frame == null:
		return

	var layout := frame.ensure_layout()
	var before_grid := layout.grid.duplicate()
	var before_sizes := layout.sizes.duplicate()
	frame.auto_fill(toolbar.layer)
	var undo := get_undo_redo()
	undo.create_action("Auto fill pipes", UndoRedo.MERGE_DISABLE, frame)
	undo.add_do_method(layout, "restore", layout.grid.duplicate(), layout.sizes.duplicate())
	undo.add_undo_method(layout, "restore", before_grid, before_sizes)
	undo.commit_action(false)
	frame.queue_regenerate()

func _on_clear() -> void:
	if frame == null or frame.layout == null:
		return

	var layout := frame.layout
	var before_grid := layout.grid.duplicate()
	var before_sizes := layout.sizes.duplicate()
	layout.clear(toolbar.layer)
	var undo := get_undo_redo()
	undo.create_action("Clear pipes", UndoRedo.MERGE_DISABLE, frame)
	undo.add_do_method(layout, "restore", layout.grid.duplicate(), layout.sizes.duplicate())
	undo.add_undo_method(layout, "restore", before_grid, before_sizes)
	undo.commit_action(false)
	frame.queue_regenerate()

func _on_regenerate() -> void:
	if frame != null:
		frame.regenerate()

# --- overlay -----------------------------------------------------------------

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if frame == null or not is_instance_valid(frame):
		return

	var xf := _to_overlay()
	var zone := Vector2(frame.zone_size())
	var g := frame.grid_size()
	var cell := float(frame.cell_size)

	# lattice
	for x in g.x + 1:
		var px := minf(x * cell, zone.x)
		overlay.draw_line(xf * Vector2(px, 0.0), xf * Vector2(px, zone.y), COLOR_GRID, 1.0)

	for y in g.y + 1:
		var py := minf(y * cell, zone.y)
		overlay.draw_line(xf * Vector2(0.0, py), xf * Vector2(zone.x, py), COLOR_GRID, 1.0)

	# painted cells, other layer dim, the edited layer on top
	var layout := frame.layout
	if layout != null and not layout.is_empty():
		var order: Array[int] = []
		for l in layout.layer_count:
			if l != toolbar.layer:
				order.append(l)

		order.append(toolbar.layer)
		for l in order:
			_draw_layer(overlay, xf, layout, l, l == toolbar.layer)

	# hover
	if hover.x >= 0 and toolbar.tool != Toolbar.Tool.SELECT:
		_draw_cell_rect(overlay, xf, frame.cell_rect(hover), COLOR_HOVER, false)
		if hover_edge.x >= 0:
			var a := frame.cell_rect(hover).get_center()
			var b := frame.cell_rect(hover_edge).get_center()
			overlay.draw_line(xf * a, xf * b, COLOR_EDGE_HINT, 3.0)

	# zone outline
	var corners := PackedVector2Array([
		xf * Vector2.ZERO, xf * Vector2(zone.x, 0.0), xf * zone, xf * Vector2(0.0, zone.y), xf * Vector2.ZERO,
	])
	overlay.draw_polyline(corners, COLOR_ZONE, 1.5)

func _draw_layer(overlay: Control, xf: Transform2D, layout: PipeLayout, layer: int, active: bool) -> void:
	var color := COLOR_LAYER[mini(layer, COLOR_LAYER.size() - 1)]
	if not active:
		color.a *= 0.35

	var fill := Color(color, color.a * 0.18)
	var scale := xf.get_scale().x
	for y in layout.height:
		for x in layout.width:
			var m := layout.get_cell(layer, x, y)
			if m == 0:
				continue

			var rect := frame.cell_rect(Vector2i(x, y))
			_draw_cell_rect(overlay, xf, rect, fill, true)
			var centre := rect.get_center()
			var gauge := layout.get_gauge(layer, x, y)
			var width := maxf(2.0, (gauge if gauge > 0.0 else 3.0) * 0.6 * scale)
			var dirs := m & PipeLayout.DIR_MASK
			if dirs == 0:
				overlay.draw_circle(xf * centre, width, color)
				continue

			for d in 4:
				if not (dirs & PipeGenerator.DIR_BIT[d]):
					continue

				var edge := centre + Vector2(PipeGenerator.DIR_X[d], PipeGenerator.DIR_Y[d]) * rect.size * 0.5
				overlay.draw_line(xf * centre, xf * edge, color, width)

			if PipeGenerator.popcount_table()[dirs] == 1:
				overlay.draw_circle(xf * centre, width * 0.9, color)

func _draw_cell_rect(overlay: Control, xf: Transform2D, rect: Rect2, color: Color, filled: bool) -> void:
	var a := xf * rect.position
	var b := xf * rect.end
	overlay.draw_rect(Rect2(a, b - a).abs(), color, filled, 1.0 if not filled else -1.0)
