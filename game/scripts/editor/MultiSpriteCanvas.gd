@tool
extends Control
class_name MultiSpriteCanvas

# zoomable view for MultiSpriteEditor. cell space: one unit is
# MultiSpriteDocument.UNIT_CELLS cells, sprites draw as their textures at the
# world's padded grid layout, joints as anchor dots. owns the view transform,
# turns mouse events into cell space points and hands them to the editor

const ZOOM_MIN := 0.25
const ZOOM_MAX := 64.0

const BG := PixelTheme.PAPER_SUNKEN
const GRID := Color(1, 1, 1, 0.08)
const AXIS := Color(1, 1, 1, 0.22)
const PADDED := Color(1, 1, 1, 0.16)
const SELECTED := PixelTheme.ACCENT
const HOVER := Color(PixelTheme.TEXT, 0.6)
const HEAD := Color8(120, 220, 120)
const JOINT := Color8(255, 217, 51, 230)
const JOINT_FIRST := PixelTheme.SELECT
const CURSOR := Color8(255, 255, 255, 200)

var editor: MultiSpriteEditor

signal pressed(point: Vector2, button: int)
signal dragged(point: Vector2)
signal released(point: Vector2, button: int)
signal hovered(point: Vector2)

var view_offset := Vector2.ZERO
var view_zoom := 4.0
var fit_pending := true

var textures := {}
var mid_down := false
var mid_dragged := false
var left_down := false
var mouse_local := Vector2.ZERO
var mouse_inside := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_exited.connect(func(): mouse_inside = false)
	mouse_entered.connect(func(): mouse_inside = true)

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

# drops go to the editor, which hands them to its host
func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return editor != null and editor._can_drop_data(at, data)

func _drop_data(at: Vector2, data: Variant) -> void:
	if editor:
		editor._drop_data(at, data)

func center() -> Vector2:
	return size * 0.5

func cell_to_local(cell: Vector2) -> Vector2:
	return center() + (cell - view_offset) * view_zoom

func local_to_cell(point: Vector2) -> Vector2:
	return (point - center()) / view_zoom + view_offset

func view_transform() -> Transform2D:
	return Transform2D(0.0, Vector2(view_zoom, view_zoom), 0.0, center() - view_offset * view_zoom)

func fit_to_view() -> void:
	fit_pending = true

func zoom_by(mul: float) -> void:
	view_zoom = clampf(view_zoom * mul, ZOOM_MIN, ZOOM_MAX)

func zoom_at(point: Vector2, mul: float) -> void:
	var before := local_to_cell(point)
	zoom_by(mul)
	var after := local_to_cell(point)
	view_offset += before - after

func apply_fit() -> void:
	if not fit_pending or size.x < 1 or size.y < 1 or editor == null:
		return

	var doc := editor.doc
	if doc.sprites.is_empty():
		view_offset = Vector2.ZERO
		view_zoom = 4.0
	else:
		var rect := doc.bounds().grow(MultiSpriteDocument.UNIT_CELLS * 0.5)
		var zx := (size.x * 0.9) / maxf(rect.size.x, 1.0)
		var zy := (size.y * 0.9) / maxf(rect.size.y, 1.0)
		view_zoom = clampf(minf(zx, zy), ZOOM_MIN, ZOOM_MAX)
		view_offset = rect.get_center()

	fit_pending = false

func hovered_point() -> Vector2:
	return local_to_cell(mouse_local)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_local = event.position
		mouse_inside = true

		if mid_down:
			mid_dragged = true
			view_offset -= event.relative / view_zoom

		hovered.emit(hovered_point())
		if left_down:
			dragged.emit(hovered_point())
		accept_event()
		return

	if event is InputEventMouseButton:
		mouse_local = event.position
		var point := hovered_point()

		if Controls.matches(event, Controls.CANVAS_ZOOM_IN):
			if event.pressed:
				zoom_at(event.position, 1.15)
		elif Controls.matches(event, Controls.CANVAS_ZOOM_OUT):
			if event.pressed:
				zoom_at(event.position, 1.0 / 1.15)
		elif Controls.matches(event, Controls.CANVAS_PAN):
			mid_down = event.pressed
			if event.pressed:
				mid_dragged = false
		elif Controls.matches(event, Controls.CANVAS_PRIMARY) or Controls.matches(event, Controls.CANVAS_SECONDARY):
			grab_focus()
			if Controls.matches(event, Controls.CANVAS_PRIMARY):
				left_down = event.pressed
			if event.pressed:
				pressed.emit(point, event.button_index)
			else:
				released.emit(point, event.button_index)

		accept_event()

func texture_for(path: String) -> ImageTexture:
	if textures.has(path):
		return textures[path]

	var image: Image = editor.doc.image_for(path)
	var texture: ImageTexture = ImageTexture.create_from_image(image) if image else null
	textures[path] = texture
	return texture

func _draw() -> void:
	if editor == null or editor.doc == null:
		return

	var doc: MultiSpriteDocument = editor.doc
	apply_fit()

	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_grid()

	var view := view_transform()

	for i in doc.sprites.size():
		var texture := texture_for(doc.sprites[i]["texture"])
		var xform := view * doc.transform_of(i)
		draw_set_transform_matrix(xform)

		var padded := Vector2(doc.padded_cells(i))
		var offset := doc.art_offset(i)
		draw_rect(Rect2(offset, padded), PADDED, false, 1.0 / view_zoom)

		if texture:
			draw_texture_rect(texture, Rect2(offset, Vector2(doc.size_cells(i))), false)

		var outline := Color(0, 0, 0, 0)
		if i == editor.selected:
			outline = SELECTED
		elif i == editor.hover_sprite:
			outline = HOVER
		if outline.a > 0.0:
			draw_rect(Rect2(offset, Vector2(doc.size_cells(i))), outline, false, 2.0 / view_zoom)

		if i == doc.head:
			draw_circle(Vector2.ZERO, MultiSpriteDocument.UNIT_CELLS * 0.18, HEAD, false, 2.0 / view_zoom)

	draw_set_transform_matrix(Transform2D.IDENTITY)

	var dot := maxf(3.0, view_zoom * 1.5)
	for joint in doc.joints:
		var a := cell_to_local(doc.units_to_cells(joint["point"]))
		draw_circle(a, dot, JOINT)
		if joint["type"] == "distance":
			var b := cell_to_local(doc.units_to_cells(joint["point_b"]))
			draw_circle(b, dot, JOINT)
			draw_line(a, b, JOINT, 1.0)

	if editor.joint_first >= 0 and editor.joint_first < doc.sprites.size():
		var origin := cell_to_local(doc.transform_of(editor.joint_first).origin)
		draw_arc(origin, dot * 3.0, 0.0, TAU, 24, JOINT_FIRST, 2.0)

	if mouse_inside and editor.mode == MultiSpriteEditor.Mode.JOINT:
		draw_arc(mouse_local, dot, 0.0, TAU, 12, CURSOR, 1.0)

func draw_grid() -> void:
	var step := MultiSpriteDocument.UNIT_CELLS
	var view_min := local_to_cell(Vector2.ZERO)
	var view_max := local_to_cell(size)

	if view_zoom * step >= 6.0:
		var x0 := floori(view_min.x / step) * step
		var x := x0
		while x <= view_max.x:
			draw_line(cell_to_local(Vector2(x, view_min.y)), cell_to_local(Vector2(x, view_max.y)), AXIS if x == 0 else GRID)
			x += step
		var y0 := floori(view_min.y / step) * step
		var y := y0
		while y <= view_max.y:
			draw_line(cell_to_local(Vector2(view_min.x, y)), cell_to_local(Vector2(view_max.x, y)), AXIS if y == 0 else GRID)
			y += step
	else:
		draw_line(cell_to_local(Vector2(0, view_min.y)), cell_to_local(Vector2(0, view_max.y)), AXIS)
		draw_line(cell_to_local(Vector2(view_min.x, 0)), cell_to_local(Vector2(view_max.x, 0)), AXIS)
