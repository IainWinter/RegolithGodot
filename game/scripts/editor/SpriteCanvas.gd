extends Control
class_name SpriteCanvas

# zoomable cell canvas for SpriteEditor. owns the view transform and layer
# textures, draws the document plus overlays, turns mouse events into cell
# coordinates and hands them to the editor

const ZOOM_MIN := 0.5
const ZOOM_MAX := 200.0

const BG := PixelTheme.PAPER_SUNKEN
const CHECKER_A := Color8(44, 43, 52)
const CHECKER_B := Color8(56, 55, 66)
const GRID_MINOR := Color(1, 1, 1, 0.12)
const GRID_MAJOR := Color(1, 1, 1, 0.28)
const OUTLINE := PixelTheme.LINE
const SELECTION_FILL := Color(PixelTheme.SELECT, 0.18)
const SELECTION_OUTLINE := PixelTheme.SELECT
const FLOAT_OUTLINE := PixelTheme.ACCENT
const GUIDE := Color8(255, 255, 255, 220)
const ACCENT := Color(PixelTheme.SELECT, 0.25)
const CURSOR := Color8(255, 255, 255, 230)

var editor: SpriteEditor

signal cell_input(hovered: bool, x: int, y: int, left_click: bool, right_click: bool, left_down: bool, right_down: bool)
signal cell_picked(x: int, y: int)
signal hovered(x: int, y: int)

var view_offset := Vector2.ZERO
var view_zoom := 16.0
var fit_pending := true

var color_tex: ImageTexture
var mask_tex: ImageTexture
var class_tex: ImageTexture
var emission_tex: ImageTexture
var tex_size := Vector2i.ZERO

var left_down := false
var right_down := false
var mid_down := false
var mid_dragged := false
var mouse_local := Vector2.ZERO
var mouse_inside := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_exited.connect(func(): mouse_inside = false; hovered.emit(-1, -1))
	mouse_entered.connect(func(): mouse_inside = true)

func _process(_delta: float) -> void:
	queue_redraw()

func center() -> Vector2:
	return size * 0.5

func cell_to_local(cell: Vector2) -> Vector2:
	return center() + (cell - view_offset) * view_zoom

func local_to_cell(point: Vector2) -> Vector2:
	return (point - center()) / view_zoom + view_offset

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
	var doc := editor.doc
	if not fit_pending or doc.width <= 0 or doc.height <= 0 or size.x < 1 or size.y < 1:
		return

	var zx := (size.x * 0.9) / float(doc.width)
	var zy := (size.y * 0.9) / float(doc.height)
	view_zoom = clampf(minf(zx, zy), ZOOM_MIN, ZOOM_MAX)
	view_offset = Vector2(doc.width, doc.height) * 0.5
	fit_pending = false

func hovered_cell() -> Vector2i:
	var p := local_to_cell(mouse_local)
	return Vector2i(floori(p.x), floori(p.y))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_local = event.position
		mouse_inside = true

		if mid_down:
			mid_dragged = true
			view_offset -= event.relative / view_zoom

		var cell := hovered_cell()
		cell_input.emit(true, cell.x, cell.y, false, false, left_down, right_down)
		accept_event()
		return

	if event is InputEventMouseButton:
		mouse_local = event.position
		var cell := hovered_cell()

		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_at(event.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_at(event.position, 1.0 / 1.15)
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					mid_down = true
					mid_dragged = false
				else:
					mid_down = false
					if not mid_dragged:
						cell_picked.emit(cell.x, cell.y)
			MOUSE_BUTTON_LEFT:
				grab_focus()
				left_down = event.pressed
				cell_input.emit(true, cell.x, cell.y, event.pressed, false, left_down, right_down)
			MOUSE_BUTTON_RIGHT:
				grab_focus()
				right_down = event.pressed
				cell_input.emit(true, cell.x, cell.y, false, event.pressed, left_down, right_down)

		accept_event()

func ensure_textures() -> void:
	var doc := editor.doc
	if doc.width <= 0 or doc.height <= 0:
		return

	var wanted := Vector2i(doc.width, doc.height)
	var rebuild := tex_size != wanted or color_tex == null

	if rebuild:
		color_tex = ImageTexture.create_from_image(doc.color_display_image())
		mask_tex = ImageTexture.create_from_image(doc.mask_display_image())
		class_tex = ImageTexture.create_from_image(doc.class_display_image())
		emission_tex = ImageTexture.create_from_image(doc.emission_display_image())
		tex_size = wanted
		doc.color_dirty = false
		doc.mask_dirty = false
		doc.class_dirty = false
		return

	if doc.color_dirty:
		color_tex.update(doc.color_display_image())
		doc.color_dirty = false

	if doc.mask_dirty:
		mask_tex.update(doc.mask_display_image())
		emission_tex.update(doc.emission_display_image())
		class_tex.update(doc.class_display_image())
		doc.mask_dirty = false
		doc.class_dirty = false

	if doc.class_dirty:
		class_tex.update(doc.class_display_image())
		emission_tex.update(doc.emission_display_image())
		doc.class_dirty = false

func _draw() -> void:
	if editor == null or editor.doc == null:
		return

	var doc := editor.doc
	apply_fit()
	ensure_textures()

	draw_rect(Rect2(Vector2.ZERO, size), BG)

	if doc.width <= 0 or doc.height <= 0:
		return

	if mouse_inside:
		var cell := hovered_cell()
		hovered.emit(cell.x, cell.y)

	var img_min := cell_to_local(Vector2.ZERO)
	var img_max := cell_to_local(Vector2(doc.width, doc.height))
	var img_rect := Rect2(img_min, img_max - img_min)

	draw_checker(img_rect, maxf(view_zoom, 8.0))

	var opacity := editor.layer_opacity
	var faded := Color(1, 1, 1, opacity)

	match doc.mode:
		SpriteDocument.Mode.GRAPHICS:
			draw_texture_rect(color_tex, img_rect, false)
			if opacity > 0.0:
				draw_texture_rect(mask_tex, img_rect, false, faded)
		SpriteDocument.Mode.MASK:
			if opacity > 0.0:
				draw_texture_rect(color_tex, img_rect, false, faded)
			draw_texture_rect(mask_tex, img_rect, false)
		SpriteDocument.Mode.CLASS:
			if opacity > 0.0:
				draw_texture_rect(color_tex, img_rect, false, faded)
			draw_texture_rect(class_tex, img_rect, false)
		SpriteDocument.Mode.EMISSION:
			if opacity > 0.0:
				draw_texture_rect(color_tex, img_rect, false, faded)
			draw_texture_rect(emission_tex, img_rect, false)

	draw_grid(doc)
	draw_rect(img_rect, OUTLINE, false, 1.0)

	draw_float(doc)
	draw_selection(doc)
	draw_shape()
	draw_cursor()

func draw_checker(rect: Rect2, step: float) -> void:
	var visible := rect.intersection(Rect2(Vector2.ZERO, size))
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return

	var x0 := floori((visible.position.x - rect.position.x) / step)
	var y0 := floori((visible.position.y - rect.position.y) / step)
	var x1 := ceili((visible.end.x - rect.position.x) / step)
	var y1 := ceili((visible.end.y - rect.position.y) / step)

	for y in range(y0, y1):
		for x in range(x0, x1):
			var cell := Rect2(rect.position + Vector2(x, y) * step, Vector2(step, step)).intersection(rect)
			if cell.size.x <= 0.0 or cell.size.y <= 0.0:
				continue
			draw_rect(cell, CHECKER_A if ((x + y) & 1) == 0 else CHECKER_B)

func draw_grid(doc: SpriteDocument) -> void:
	var view_min := local_to_cell(Vector2.ZERO)
	var view_max := local_to_cell(size)

	var gx0 := maxi(0, floori(view_min.x))
	var gy0 := maxi(0, floori(view_min.y))
	var gx1 := mini(doc.width, ceili(view_max.x) + 1)
	var gy1 := mini(doc.height, ceili(view_max.y) + 1)

	var minor_alpha := clampf((view_zoom - 4.0) / 8.0, 0.0, 1.0)

	if minor_alpha > 0.02:
		var minor := Color(GRID_MINOR, GRID_MINOR.a * minor_alpha)
		for x in range(gx0, gx1 + 1):
			draw_line(cell_to_local(Vector2(x, 0)), cell_to_local(Vector2(x, doc.height)), minor)
		for y in range(gy0, gy1 + 1):
			draw_line(cell_to_local(Vector2(0, y)), cell_to_local(Vector2(doc.width, y)), minor)

	if view_zoom >= 2.0:
		var major := 16 if (doc.width > 64 or doc.height > 64) else 8
		var mx := (gx0 / major) * major
		while mx <= gx1:
			draw_line(cell_to_local(Vector2(mx, 0)), cell_to_local(Vector2(mx, doc.height)), GRID_MAJOR)
			mx += major
		var my := (gy0 / major) * major
		while my <= gy1:
			draw_line(cell_to_local(Vector2(0, my)), cell_to_local(Vector2(doc.width, my)), GRID_MAJOR)
			my += major

func draw_float(doc: SpriteDocument) -> void:
	if not editor.has_float():
		return

	var region: Dictionary = editor.float_region
	var fw: int = region["w"]
	var fh: int = region["h"]
	var at := Vector2(editor.float_pos)

	if fw * fh <= 16384:
		for y in fh:
			for x in fw:
				var c := doc.region_display_color(region, x + y * fw)
				if c.a <= 0.0:
					continue
				var a := cell_to_local(at + Vector2(x, y))
				var b := cell_to_local(at + Vector2(x + 1, y + 1))
				draw_rect(Rect2(a, b - a), c)
	else:
		var a := cell_to_local(at)
		var b := cell_to_local(at + Vector2(fw, fh))
		draw_rect(Rect2(a, b - a), SELECTION_FILL)

	var a := cell_to_local(at)
	var b := cell_to_local(at + Vector2(fw, fh))
	draw_rect(Rect2(a, b - a), FLOAT_OUTLINE, false, 1.0)

func draw_selection(doc: SpriteDocument) -> void:
	if not doc.selection_active:
		return

	var a := cell_to_local(Vector2(doc.selection.position))
	var b := cell_to_local(Vector2(doc.selection.end))
	var rect := Rect2(a, b - a)

	if not editor.has_float():
		draw_rect(rect, SELECTION_FILL)

	draw_dashed_rect(rect, SELECTION_OUTLINE)

func draw_dashed_rect(rect: Rect2, color: Color) -> void:
	var p0 := rect.position
	var p1 := Vector2(rect.end.x, rect.position.y)
	var p2 := rect.end
	var p3 := Vector2(rect.position.x, rect.end.y)
	draw_dashed_line(p0, p1, color, 1.0, 5.0)
	draw_dashed_line(p1, p2, color, 1.0, 5.0)
	draw_dashed_line(p2, p3, color, 1.0, 5.0)
	draw_dashed_line(p3, p0, color, 1.0, 5.0)

func draw_shape() -> void:
	if not editor.shape_active:
		return

	var s0 := editor.shape_start
	var s1 := editor.shape_end

	if editor.tool == SpriteEditor.Tool.RECT:
		var lo := Vector2(mini(s0.x, s1.x), mini(s0.y, s1.y))
		var hi := Vector2(maxi(s0.x, s1.x) + 1, maxi(s0.y, s1.y) + 1)
		var a := cell_to_local(lo)
		var b := cell_to_local(hi)
		if editor.rect_filled:
			draw_rect(Rect2(a, b - a), ACCENT)
		draw_rect(Rect2(a, b - a), GUIDE, false, 1.0)
	else:
		draw_line(cell_to_local(Vector2(s0) + Vector2(0.5, 0.5)), cell_to_local(Vector2(s1) + Vector2(0.5, 0.5)), GUIDE, maxf(1.0, view_zoom * 0.2))

func draw_cursor() -> void:
	var hover := editor.hover
	if hover.x < 0 or not mouse_inside:
		return

	var span := editor.brush_size if editor.tool_uses_brush() else 1
	var lo := -(span / 2)
	var a := cell_to_local(Vector2(hover) + Vector2(lo, lo))
	var b := cell_to_local(Vector2(hover) + Vector2(lo + span, lo + span))
	draw_rect(Rect2(a, b - a), CURSOR, false, 1.0)
