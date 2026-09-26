extends Node2D
class_name PowerTank

# port of PowerTank and PowerTankSystem: a falling sand tank on the hud
# built from a mask image, red cells are outlets, blue inlets, white is
# empty space and anything else a barrier. cells queued with queue_cells
# drop in at a random inlet one per update, when the outlet is open one
# cell per update is drained out and reported on power_drained. sand falls
# down, slides diagonally, then sideways, biased against the player's
# sideways speed, and briefly falls up after a hit (bounce). every cell
# shimmers on its own timer. draws its pixels as a texture scaled by
# pixel_size, so it can sit in a CanvasLayer

@export var mask: Texture2D
@export var pixel_size := 4.0
@export var update_rate := 1.0 / 60.0
@export var feed_color := Color8(60, 140, 220, 110)
@export var power_per_cell := 1.0
@export var open_outlet := false
# what the sideways bias reads, the player as a rule
@export var body: RegolithSprite

signal power_drained(amount: float)

const BARRIER_COLOR := Color8(15, 18, 30, 255)
const BOUNCE_TIME := 0.2

class Cell:
	var color := Color(0, 0, 0, 0)
	var is_static := false
	var timer := 0.0

	func copy() -> Cell:
		var c := Cell.new()
		c.color = color
		c.is_static = is_static
		c.timer = timer
		return c

var width := 0
var height := 0
var cells_read: Array[Cell] = []
var cells_write: Array[Cell] = []
var inlet: Array[Vector2i] = []
var outlet: Array[Vector2i] = []
var cells_queued := 0
var update_timer := 0.0
var bounce_timer := 0.0
var image: Image
var texture: ImageTexture
var default_cell := Cell.new()

func _ready() -> void:
	add_to_group("power_tank")
	default_cell.color = Color8(0, 0, 0, 255)
	default_cell.is_static = true

	if mask != null:
		init_from_mask(mask.get_image())

func index(x: int, y: int) -> int:
	return x + y * width

func outside(x: int, y: int) -> bool:
	return x < 0 or x >= width or y < 0 or y >= height

func init_from_mask(source: Image) -> void:
	width = source.get_width()
	height = source.get_height()
	cells_read.clear()
	cells_write.clear()
	inlet.clear()
	outlet.clear()

	for i in width * height:
		cells_read.append(Cell.new())
		cells_write.append(Cell.new())

	for y in height:
		for x in width:
			var p := source.get_pixel(x, y)
			var is_red := p.r8 > 200 and p.g8 < 100 and p.b8 < 100
			var is_blue := p.b8 > 200 and p.r8 < 100 and p.g8 < 100
			var is_white := p.r8 > 200 and p.g8 > 200 and p.b8 > 200

			if is_red:
				outlet.append(Vector2i(x, y))
			elif is_blue:
				inlet.append(Vector2i(x, y))
			elif not is_white:
				write_barrier(index(x, y))

	image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(image)

func read(x: int, y: int) -> Cell:
	if outside(x, y):
		return default_cell

	return cells_read[index(x, y)]

func test(x: int, y: int) -> bool:
	if outside(x, y):
		return false

	var i := index(x, y)
	return cells_write[i].color.a == 0.0 and cells_read[i].color.a == 0.0

func write_cell(i: int, color: Color, is_static: bool) -> void:
	var c := Cell.new()
	c.color = color
	c.is_static = is_static
	c.timer = randf() * TAU
	cells_write[i] = c

	if is_static:
		cells_read[i] = c.copy()

func write_barrier(i: int) -> void:
	write_cell(i, BARRIER_COLOR, true)

func move_cell(ox: int, oy: int, x: int, y: int) -> void:
	var oi := index(ox, oy)
	var i := index(x, y)
	var moved := cells_read[oi]
	cells_read[oi] = cells_write[i]
	cells_write[i] = moved

func queue_cells(count: int, color := Color(0, 0, 0, 0)) -> void:
	cells_queued += count

	if color.a > 0.0:
		feed_color = color

func bounce() -> void:
	bounce_timer = BOUNCE_TIME

func filled_count() -> int:
	var n := 0

	for c in cells_write:
		if c.color.a > 0.0 and not c.is_static:
			n += 1

	return n

func try_move_to(x: int, y: int, nx: int, ny: int) -> bool:
	if not test(nx, ny):
		return false

	move_cell(x, y, nx, ny)
	return true

func move_vertical(x: int, y: int, dir: int) -> bool:
	return try_move_to(x, y, x, y + dir)

func move_diagonal(x: int, y: int, dir: int, lr_bias: int) -> bool:
	var check := (1 if lr_bias > 0 else -1) if lr_bias != 0 else (1 if randf() < 0.5 else -1)

	if try_move_to(x, y, x + check, y + dir):
		return true

	return try_move_to(x, y, x - check, y + dir)

func move_lr(x: int, y: int, lr_bias: int) -> bool:
	var check := (1 if lr_bias > 0 else -1) if lr_bias != 0 else (1 if randf() < 0.5 else -1)

	if try_move_to(x, y, x + check, y):
		return true

	return try_move_to(x, y, x - check, y)

func step_cells(dt: float, gravity_dir: int, lr_bias: int) -> void:
	var swap := cells_read
	cells_read = cells_write
	cells_write = swap

	for x in width:
		for y in height:
			var cell := read(x, y)

			if cell.color.a == 0.0 or cell.is_static:
				continue

			cell.timer += 0.4 * dt

			if move_vertical(x, y, gravity_dir):
				continue

			if move_diagonal(x, y, gravity_dir, lr_bias):
				continue

			if move_lr(x, y, lr_bias):
				continue

			move_cell(x, y, x, y)

func write_pixels() -> void:
	for y in height:
		for x in width:
			var c := cells_write[index(x, y)]

			if c.color.a == 0.0 or c.is_static:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			var s := sin(c.timer)
			var r := clampi(c.color.r8 + int(35.0 * s), 0, 255)
			var g := clampi(c.color.g8 + int(55.0 * s), 0, 255)
			var b := clampi(c.color.b8 + int(55.0 * s), 0, 255)
			var a := clampi(c.color.a8 + int(25.0 * s), 0, 255)
			image.set_pixel(x, y, Color8(r, g, b, a))

	texture.update(image)

func _process(delta: float) -> void:
	if width == 0:
		return

	update_timer -= delta

	if update_timer > 0.0:
		return

	update_timer = update_rate
	update()

func update() -> void:
	if cells_queued > 0 and not inlet.is_empty():
		var at := inlet[randi() % inlet.size()]

		if test(at.x, at.y):
			write_cell(index(at.x, at.y), feed_color, false)
			cells_queued -= 1

	if open_outlet and not outlet.is_empty():
		var out := outlet[randi() % outlet.size()]
		var i := index(out.x, out.y)

		if cells_write[i].color.a != 0.0 and not cells_write[i].is_static:
			power_drained.emit(power_per_cell)
			write_cell(i, Color(0, 0, 0, 0), false)

	# the original's gravity_dir of -1 fell toward row zero with y up, the
	# mask here is y down so sand falls toward the last row
	var gravity_dir := 1

	if bounce_timer > 0.0:
		bounce_timer -= update_rate
		gravity_dir = -1

	var lr_bias := 0

	if body != null and is_instance_valid(body):
		var vx: float = body.linear_velocity.x

		if vx > 0.5:
			lr_bias = -1
		elif vx < -0.5:
			lr_bias = 1

	step_cells(update_rate, gravity_dir, lr_bias)
	write_pixels()
	queue_redraw()

func _draw() -> void:
	if texture != null:
		draw_texture_rect(texture, Rect2(Vector2.ZERO, Vector2(width, height) * pixel_size), false)
