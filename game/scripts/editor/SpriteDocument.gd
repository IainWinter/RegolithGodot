extends RefCounted
class_name SpriteDocument

# pixel buffers for one sprite under edit: color, cell type, armor class with
# the emission bit. plain data with paint ops and undo, no nodes, so the ui
# and headless tests share it. png codec matches SpriteMaskPack.cpp

enum Mode { GRAPHICS, MASK, CLASS, EMISSION }

const EMISSION_BIT := 0x8
const CLASS_BITS := 0x7
const MAX_SIZE := 512
const TYPE_COUNT := 12
const CLASS_COUNT := 8
const HISTORY_LIMIT := 64

const TYPE_NAMES := ["Empty", "Filled", "Core", "Weakpoint 1", "Weakpoint 2", "Weakpoint 3", "Weakpoint 4", "Joint 1", "Joint 2", "Joint 3", "Joint 4", "Rope"]

const TYPE_DISPLAY: Array[Color] = [
	Color8(0, 0, 0, 0),
	Color8(200, 200, 200),
	Color8(50, 220, 50),
	Color8(255, 100, 100),
	Color8(255, 150, 80),
	Color8(255, 180, 60),
	Color8(255, 220, 40),
	Color8(60, 120, 255),
	Color8(80, 200, 255),
	Color8(80, 230, 210),
	Color8(160, 120, 255),
	Color8(255, 40, 220),
]

const CLASS_DISPLAY: Array[Color] = [
	Color8(60, 60, 60),
	Color8(80, 160, 255),
	Color8(255, 180, 40),
	Color8(255, 60, 60),
	Color8(60, 220, 90),
	Color8(180, 80, 255),
	Color8(40, 220, 220),
	Color8(240, 240, 60),
]

const EMISSION_ON := Color8(255, 190, 60)
const EMISSION_OFF := Color8(70, 74, 82)

const TYPE_RED := [0, 0, 0, 0, 0, 0, 0, 50, 100, 150, 200, 250]
const TYPE_GREEN := [0, 100, 200, 250, 251, 252, 253, 0, 0, 0, 0, 0]

var width := 0
var height := 0
var color := PackedByteArray()
var mask := PackedByteArray()
var cls := PackedByteArray()

var color_dirty := true
var mask_dirty := true
var class_dirty := true

var mode: Mode = Mode.GRAPHICS
var paint_color := Color.WHITE
var paint_type := RegolithSprite.CELL_FILLED
var paint_class := 0
var paste_all_layers := false

var selection := Rect2i()
var selection_active := false

var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var edit_before := {}

func _init(w := 0, h := 0) -> void:
	resize(w, h)

func cell_count() -> int:
	return width * height

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

func index(x: int, y: int) -> int:
	return x + y * width

func get_cell_color(i: int) -> Color:
	return Color8(color[i * 4], color[i * 4 + 1], color[i * 4 + 2], color[i * 4 + 3])

func set_cell_color(i: int, c: Color) -> void:
	color[i * 4] = c.r8
	color[i * 4 + 1] = c.g8
	color[i * 4 + 2] = c.b8
	color[i * 4 + 3] = c.a8
	color_dirty = true

func get_cell_type(i: int) -> int:
	return mask[i]

func set_cell_type(i: int, type: int) -> void:
	mask[i] = type
	mask_dirty = true

	if type == RegolithSprite.CELL_EMPTY and cls[i] != 0:
		cls[i] = 0
		class_dirty = true

func get_cell_class(i: int) -> int:
	return cls[i] & CLASS_BITS

func set_cell_class(i: int, value: int) -> void:
	cls[i] = (cls[i] & EMISSION_BIT) | (value & CLASS_BITS)
	class_dirty = true

func get_cell_emissive(i: int) -> bool:
	return (cls[i] & EMISSION_BIT) != 0

func set_cell_emissive(i: int, on: bool) -> void:
	cls[i] = (cls[i] | EMISSION_BIT) if on else (cls[i] & ~EMISSION_BIT)
	class_dirty = true

func set_cell_bits(i: int, bits: int) -> void:
	cls[i] = bits & (CLASS_BITS | EMISSION_BIT)
	class_dirty = true

func resize(w: int, h: int) -> void:
	w = clampi(w, 0, MAX_SIZE)
	h = clampi(h, 0, MAX_SIZE)

	var new_color := PackedByteArray()
	var new_mask := PackedByteArray()
	var new_cls := PackedByteArray()
	new_color.resize(w * h * 4)
	new_mask.resize(w * h)
	new_cls.resize(w * h)

	var cw := mini(w, width)
	var ch := mini(h, height)

	for y in ch:
		for x in cw:
			var src := x + y * width
			var dst := x + y * w
			for k in 4:
				new_color[dst * 4 + k] = color[src * 4 + k]
			new_mask[dst] = mask[src]
			new_cls[dst] = cls[src]

	width = w
	height = h
	color = new_color
	mask = new_mask
	cls = new_cls
	mark_all_dirty()

	if selection_active:
		set_selection(selection.position.x, selection.position.y, selection.end.x - 1, selection.end.y - 1)

func clear() -> void:
	color.fill(0)
	mask.fill(0)
	cls.fill(0)
	mark_all_dirty()

func mark_all_dirty() -> void:
	color_dirty = true
	mask_dirty = true
	class_dirty = true

func has_mask() -> bool:
	for i in cell_count():
		if mask[i] != RegolithSprite.CELL_EMPTY:
			return true
	return false

func snapshot() -> Dictionary:
	return {"w": width, "h": height, "color": color.duplicate(), "mask": mask.duplicate(), "cls": cls.duplicate()}

func restore(snap: Dictionary) -> void:
	width = snap["w"]
	height = snap["h"]
	color = snap["color"].duplicate()
	mask = snap["mask"].duplicate()
	cls = snap["cls"].duplicate()
	mark_all_dirty()

	if selection_active:
		set_selection(selection.position.x, selection.position.y, selection.end.x - 1, selection.end.y - 1)

static func snapshots_equal(a: Dictionary, b: Dictionary) -> bool:
	return a["w"] == b["w"] and a["h"] == b["h"] and a["color"] == b["color"] and a["mask"] == b["mask"] and a["cls"] == b["cls"]

func begin_edit() -> void:
	if edit_before.is_empty():
		edit_before = snapshot()

func end_edit() -> void:
	if edit_before.is_empty():
		return

	var after := snapshot()
	if not snapshots_equal(edit_before, after):
		push_history(edit_before, after)

	edit_before = {}

func editing() -> bool:
	return not edit_before.is_empty()

func push_history(before: Dictionary, after: Dictionary) -> void:
	undo_stack.append({"before": before, "after": after})
	redo_stack.clear()

	while undo_stack.size() > HISTORY_LIMIT:
		undo_stack.pop_front()

func clear_history() -> void:
	undo_stack.clear()
	redo_stack.clear()
	edit_before = {}

func can_undo() -> bool:
	return not undo_stack.is_empty()

func can_redo() -> bool:
	return not redo_stack.is_empty()

func undo() -> void:
	if undo_stack.is_empty():
		return

	var entry: Dictionary = undo_stack.pop_back()
	restore(entry["before"])
	redo_stack.append(entry)

func redo() -> void:
	if redo_stack.is_empty():
		return

	var entry: Dictionary = redo_stack.pop_back()
	restore(entry["after"])
	undo_stack.append(entry)

func resize_recorded(w: int, h: int) -> void:
	var before := snapshot()
	resize(w, h)
	push_history(before, snapshot())

func clear_recorded() -> void:
	var before := snapshot()
	clear()
	push_history(before, snapshot())

func set_selection(x0: int, y0: int, x1: int, y1: int) -> void:
	var ax := maxi(mini(x0, x1), 0)
	var ay := maxi(mini(y0, y1), 0)
	var bx := mini(maxi(x0, x1), width - 1)
	var by := mini(maxi(y0, y1), height - 1)

	if bx < ax or by < ay:
		selection_active = false
		return

	selection_active = true
	selection = Rect2i(ax, ay, bx - ax + 1, by - ay + 1)

func select_all() -> void:
	set_selection(0, 0, width - 1, height - 1)

func deselect() -> void:
	selection_active = false

func cell_selected(x: int, y: int) -> bool:
	if not selection_active:
		return true
	return selection.has_point(Vector2i(x, y))

func index_selected(i: int) -> bool:
	if not selection_active or width <= 0:
		return true
	return cell_selected(i % width, i / width)

func layer_pixels() -> bool:
	return paste_all_layers or mode == Mode.GRAPHICS

func layer_mask() -> bool:
	return paste_all_layers or mode == Mode.MASK

func layer_class() -> bool:
	return paste_all_layers or mode == Mode.CLASS or mode == Mode.EMISSION

func paint_at(x: int, y: int, erase: bool) -> void:
	if not in_bounds(x, y) or not cell_selected(x, y):
		return

	var i := index(x, y)

	match mode:
		Mode.GRAPHICS:
			set_cell_color(i, Color(0, 0, 0, 0) if erase else paint_color)
		Mode.CLASS:
			set_cell_class(i, 0 if erase else paint_class)
		Mode.EMISSION:
			set_cell_emissive(i, not erase)
		Mode.MASK:
			set_cell_type(i, RegolithSprite.CELL_EMPTY if erase else paint_type)

func paint_brush(x: int, y: int, size: int, erase: bool) -> void:
	if size <= 1:
		paint_at(x, y, erase)
		return

	var lo := -(size / 2)
	var hi := lo + size - 1

	for oy in range(lo, hi + 1):
		for ox in range(lo, hi + 1):
			paint_at(x + ox, y + oy, erase)

func paint_line(x0: int, y0: int, x1: int, y1: int, size: int, erase: bool) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0

	while true:
		paint_brush(x, y, size, erase)

		if x == x1 and y == y1:
			break

		var e2 := 2 * err

		if e2 >= dy:
			err += dy
			x += sx

		if e2 <= dx:
			err += dx
			y += sy

func paint_rect(x0: int, y0: int, x1: int, y1: int, size: int, filled: bool, erase: bool) -> void:
	var ax := mini(x0, x1)
	var ay := mini(y0, y1)
	var bx := maxi(x0, x1)
	var by := maxi(y0, y1)

	if filled:
		for y in range(ay, by + 1):
			for x in range(ax, bx + 1):
				paint_at(x, y, erase)
		return

	for x in range(ax, bx + 1):
		paint_brush(x, ay, size, erase)
		paint_brush(x, by, size, erase)

	for y in range(ay, by + 1):
		paint_brush(ax, y, size, erase)
		paint_brush(bx, y, size, erase)

func flood_fill_at(x: int, y: int, erase: bool) -> void:
	if not in_bounds(x, y) or not cell_selected(x, y):
		return

	var start := index(x, y)
	var needs_mask := mode == Mode.CLASS or mode == Mode.EMISSION
	var target := fill_key(start)
	var fill := fill_value(target, erase)

	if fill == target:
		return

	var seen := PackedByteArray()
	seen.resize(cell_count())
	var stack: Array[int] = [start]
	seen[start] = 1

	while not stack.is_empty():
		var i: int = stack.pop_back()
		write_fill(i, fill)

		var cx := i % width
		var cy := i / width

		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue

				var nx := cx + ox
				var ny := cy + oy

				if not in_bounds(nx, ny):
					continue

				var n := index(nx, ny)

				if seen[n] or fill_key(n) != target or not index_selected(n):
					continue

				if needs_mask and mask[n] == RegolithSprite.CELL_EMPTY:
					continue

				seen[n] = 1
				stack.append(n)

func fill_key(i: int) -> int:
	match mode:
		Mode.GRAPHICS:
			return color[i * 4] | (color[i * 4 + 1] << 8) | (color[i * 4 + 2] << 16) | (color[i * 4 + 3] << 24)
		Mode.MASK:
			return mask[i]
		_:
			return cls[i]

func fill_value(target: int, erase: bool) -> int:
	match mode:
		Mode.GRAPHICS:
			if erase:
				return 0
			return paint_color.r8 | (paint_color.g8 << 8) | (paint_color.b8 << 16) | (paint_color.a8 << 24)
		Mode.MASK:
			return RegolithSprite.CELL_EMPTY if erase else paint_type
		Mode.CLASS:
			return (target & EMISSION_BIT) | (0 if erase else paint_class)
		_:
			return (target & ~EMISSION_BIT) if erase else (target | EMISSION_BIT)

func write_fill(i: int, value: int) -> void:
	match mode:
		Mode.GRAPHICS:
			set_cell_color(i, Color8(value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF, (value >> 24) & 0xFF))
		Mode.MASK:
			set_cell_type(i, value)
		_:
			set_cell_bits(i, value)

func pick_at(x: int, y: int) -> void:
	if not in_bounds(x, y):
		return

	var i := index(x, y)

	match mode:
		Mode.GRAPHICS:
			paint_color = get_cell_color(i)
		Mode.MASK:
			paint_type = get_cell_type(i)
		Mode.CLASS:
			paint_class = get_cell_class(i)

func copy_region(rect: Rect2i) -> Dictionary:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return {}

	var rw := rect.size.x
	var rh := rect.size.y
	var count := rw * rh
	var out_color := PackedByteArray()
	var out_mask := PackedByteArray()
	var out_cls := PackedByteArray()
	out_color.resize(count * 4)
	out_mask.resize(count)
	out_cls.resize(count)

	for y in rh:
		var sy := rect.position.y + y
		if sy < 0 or sy >= height:
			continue

		for x in rw:
			var sx := rect.position.x + x
			if sx < 0 or sx >= width:
				continue

			var si := index(sx, sy)
			var di := x + y * rw
			for k in 4:
				out_color[di * 4 + k] = color[si * 4 + k]
			out_mask[di] = mask[si]
			out_cls[di] = cls[si]

	return {"w": rw, "h": rh, "color": out_color, "mask": out_mask, "cls": out_cls}

static func region_empty(region: Dictionary) -> bool:
	return region.is_empty() or region["w"] <= 0 or region["h"] <= 0

func clear_region(rect: Rect2i) -> void:
	for y in rect.size.y:
		var cy := rect.position.y + y
		if cy < 0 or cy >= height:
			continue

		for x in rect.size.x:
			var cx := rect.position.x + x
			if cx < 0 or cx >= width:
				continue

			var i := index(cx, cy)

			if layer_pixels():
				set_cell_color(i, Color(0, 0, 0, 0))

			if layer_mask():
				set_cell_type(i, RegolithSprite.CELL_EMPTY)

			if layer_class():
				if paste_all_layers:
					set_cell_bits(i, 0)
				elif mode == Mode.EMISSION:
					set_cell_emissive(i, false)
				else:
					set_cell_class(i, 0)

func write_region(region: Dictionary, at_x: int, at_y: int) -> void:
	if region_empty(region):
		return

	var rw: int = region["w"]
	var rh: int = region["h"]
	var region_color: PackedByteArray = region["color"]
	var region_mask: PackedByteArray = region["mask"]
	var region_cls: PackedByteArray = region["cls"]

	for y in rh:
		var cy := at_y + y
		if cy < 0 or cy >= height:
			continue

		for x in rw:
			var cx := at_x + x
			if cx < 0 or cx >= width:
				continue

			var si := x + y * rw
			var i := index(cx, cy)

			if layer_pixels():
				for k in 4:
					color[i * 4 + k] = region_color[si * 4 + k]
				color_dirty = true

			if layer_mask():
				set_cell_type(i, region_mask[si])

			if layer_class():
				if mode == Mode.EMISSION and not paste_all_layers:
					set_cell_bits(i, (cls[i] & ~EMISSION_BIT) | (region_cls[si] & EMISSION_BIT))
				else:
					set_cell_bits(i, region_cls[si])

func region_display_color(region: Dictionary, i: int) -> Color:
	match mode:
		Mode.MASK:
			return TYPE_DISPLAY[region["mask"][i]]
		Mode.CLASS:
			if region["mask"][i] == RegolithSprite.CELL_EMPTY:
				return Color(0, 0, 0, 0)
			return CLASS_DISPLAY[region["cls"][i] & CLASS_BITS]
		Mode.EMISSION:
			if region["mask"][i] == RegolithSprite.CELL_EMPTY:
				return Color(0, 0, 0, 0)
			return EMISSION_ON if (region["cls"][i] & EMISSION_BIT) else EMISSION_OFF
		_:
			return Color8(region["color"][i * 4], region["color"][i * 4 + 1], region["color"][i * 4 + 2], region["color"][i * 4 + 3])

func to_color_image() -> Image:
	if width <= 0 or height <= 0:
		return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, color)

func to_mask_image() -> Image:
	if width <= 0 or height <= 0:
		return null

	var data := PackedByteArray()
	data.resize(cell_count() * 4)

	for i in cell_count():
		var type := mask[i]
		if type == RegolithSprite.CELL_EMPTY:
			continue

		data[i * 4] = TYPE_RED[type]
		data[i * 4 + 1] = TYPE_GREEN[type]
		data[i * 4 + 2] = 255 - (cls[i] & CLASS_BITS)
		data[i * 4 + 3] = 254 if (cls[i] & EMISSION_BIT) else 255

	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)

func from_images(color_image: Image, mask_image: Image) -> void:
	if color_image == null:
		return

	var image: Image = color_image.duplicate()
	image.convert(Image.FORMAT_RGBA8)

	width = image.get_width()
	height = image.get_height()
	color = image.get_data()
	mask = PackedByteArray()
	mask.resize(cell_count())
	cls = PackedByteArray()
	cls.resize(cell_count())

	if mask_image and mask_image.get_width() == width and mask_image.get_height() == height:
		var m: Image = mask_image.duplicate()
		m.convert(Image.FORMAT_RGBA8)
		var data: PackedByteArray = m.get_data()

		for i in cell_count():
			var type := decode_mask_pixel(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
			mask[i] = type

			if type != RegolithSprite.CELL_EMPTY:
				cls[i] = ((255 - data[i * 4 + 2]) & CLASS_BITS) | (EMISSION_BIT if data[i * 4 + 3] == 254 else 0)
	else:
		for i in cell_count():
			var a := color[i * 4 + 3]
			if a > 0 and (color[i * 4] > 0 or color[i * 4 + 1] > 0 or color[i * 4 + 2] > 0):
				mask[i] = RegolithSprite.CELL_FILLED

	mark_all_dirty()
	deselect()
	clear_history()

static func decode_mask_pixel(r: int, g: int, b: int) -> int:
	if b == 0:
		return RegolithSprite.CELL_EMPTY

	match r:
		50: return RegolithSprite.CELL_JOINT1
		100: return RegolithSprite.CELL_JOINT2
		150: return RegolithSprite.CELL_JOINT3
		200: return RegolithSprite.CELL_JOINT4
		250: return RegolithSprite.CELL_ROPE

	match g:
		100: return RegolithSprite.CELL_FILLED
		200: return RegolithSprite.CELL_CORE
		250: return RegolithSprite.CELL_WEAKPOINT1
		251: return RegolithSprite.CELL_WEAKPOINT2
		252: return RegolithSprite.CELL_WEAKPOINT3
		253: return RegolithSprite.CELL_WEAKPOINT4

	return RegolithSprite.CELL_EMPTY

static func encode_mask_pixel(type: int, cell_class: int, emissive := false) -> Color:
	if type == RegolithSprite.CELL_EMPTY:
		return Color(0, 0, 0, 0)

	return Color8(TYPE_RED[type], TYPE_GREEN[type], 255 - (cell_class & CLASS_BITS), 254 if emissive else 255)

func color_display_image() -> Image:
	return to_color_image()

func mask_display_image() -> Image:
	var data := PackedByteArray()
	data.resize(cell_count() * 4)

	for i in cell_count():
		var c := TYPE_DISPLAY[mask[i]]
		data[i * 4] = c.r8
		data[i * 4 + 1] = c.g8
		data[i * 4 + 2] = c.b8
		data[i * 4 + 3] = c.a8

	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)

func class_display_image() -> Image:
	var data := PackedByteArray()
	data.resize(cell_count() * 4)

	for i in cell_count():
		if mask[i] == RegolithSprite.CELL_EMPTY:
			continue

		var c := CLASS_DISPLAY[cls[i] & CLASS_BITS]
		data[i * 4] = c.r8
		data[i * 4 + 1] = c.g8
		data[i * 4 + 2] = c.b8
		data[i * 4 + 3] = 255

	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)

func emission_display_image() -> Image:
	var data := PackedByteArray()
	data.resize(cell_count() * 4)

	for i in cell_count():
		if mask[i] == RegolithSprite.CELL_EMPTY:
			continue

		var c := EMISSION_ON if (cls[i] & EMISSION_BIT) else EMISSION_OFF
		data[i * 4] = c.r8
		data[i * 4 + 1] = c.g8
		data[i * 4 + 2] = c.b8
		data[i * 4 + 3] = 255

	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
