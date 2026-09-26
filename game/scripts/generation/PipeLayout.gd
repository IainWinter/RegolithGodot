@tool
extends Resource
class_name PipeLayout

# a hand drawn pipe layout, the grids the old editor.py kept per layer. one
# byte per cell per layer: the low nibble is the N/E/S/W connection bitmask
# (PipeGenerator.NORTH..WEST), PAINTED (16) marks the cell as placed by hand
# so a 0 byte is a free cell the generator may fill (MIXED) or leave empty
# (MANUAL). `sizes` is the optional per node radius (0 = the layer's default),
# the python editor's size tool. layer 0 is the back layer, layer 1 the front.
#
# saved inline in the scene as the PipeFrame's `layout`, index order is
# layer * width * height + y * width + x

const PAINTED := PipeGenerator.PAINTED
const DIR_MASK := PipeGenerator.DIR_MASK
const LAYER_NAMES: PackedStringArray = ["Back", "Front"]
const GAUGE_MIN := 1.0
const GAUGE_MAX := 10.0

@export var width := 0
@export var height := 0
@export var layer_count := 2
@export var grid := PackedByteArray()
@export var sizes := PackedFloat32Array()

# --- shape ---------------------------------------------------------------

func cell_count() -> int:
	return width * height

func is_empty() -> bool:
	return cell_count() == 0

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

func index(layer: int, x: int, y: int) -> int:
	return layer * width * height + y * width + x

# change the grid dimensions, keeping every cell that is still inside like the
# python editor did when the seed re-rolled the lattice
func resize(new_width: int, new_height: int, new_layers := layer_count) -> void:
	new_width = maxi(new_width, 1)
	new_height = maxi(new_height, 1)
	new_layers = maxi(new_layers, 1)
	if new_width == width and new_height == height and new_layers == layer_count and grid.size() == cell_count() * layer_count:
		return

	var next := PackedByteArray()
	next.resize(new_width * new_height * new_layers)
	var next_sizes := PackedFloat32Array()
	next_sizes.resize(new_width * new_height * new_layers)
	var has_sizes := sizes.size() == cell_count() * layer_count
	var has_grid := grid.size() == cell_count() * layer_count
	if has_grid:
		for layer in mini(layer_count, new_layers):
			for y in mini(height, new_height):
				for x in mini(width, new_width):
					var from := index(layer, x, y)
					var to := layer * new_width * new_height + y * new_width + x
					next[to] = grid[from]
					if has_sizes:
						next_sizes[to] = sizes[from]

	width = new_width
	height = new_height
	layer_count = new_layers
	grid = next
	sizes = next_sizes
	emit_changed()

# --- cells ---------------------------------------------------------------

func get_cell(layer: int, x: int, y: int) -> int:
	if not in_bounds(x, y) or layer < 0 or layer >= layer_count:
		return 0

	return grid[index(layer, x, y)]

func is_painted(layer: int, x: int, y: int) -> bool:
	return (get_cell(layer, x, y) & PAINTED) != 0

func connections(layer: int, x: int, y: int) -> int:
	return get_cell(layer, x, y) & DIR_MASK

func get_gauge(layer: int, x: int, y: int) -> float:
	if not in_bounds(x, y) or sizes.size() != grid.size():
		return 0.0

	return sizes[index(layer, x, y)]

func set_cell(layer: int, x: int, y: int, value: int) -> void:
	if not in_bounds(x, y):
		return

	grid[index(layer, x, y)] = value & (PAINTED | DIR_MASK)
	emit_changed()

# mark a cell as pipe and link it to every painted 4-neighbour, so a stroke
# of paints draws a run and a click beside a pipe extends it
func paint(layer: int, x: int, y: int) -> void:
	if not in_bounds(x, y):
		return

	var i := index(layer, x, y)
	var m := grid[i] | PAINTED
	for d in 4:
		var nx := x + PipeGenerator.DIR_X[d]
		var ny := y + PipeGenerator.DIR_Y[d]
		if not in_bounds(nx, ny):
			continue

		var ni := index(layer, nx, ny)
		if grid[ni] & PAINTED:
			m |= PipeGenerator.DIR_BIT[d]
			grid[ni] |= PipeGenerator.DIR_OPP[d]

	grid[i] = m
	emit_changed()

# paint two 4-adjacent cells and open the edge between them. the stroke tool:
# each drag step links the cell under the mouse to the previous one only, so
# parallel runs one cell apart stay separate
func connect_cells(layer: int, a: Vector2i, b: Vector2i) -> void:
	var d := direction_between(a, b)
	if d < 0 or not in_bounds(a.x, a.y) or not in_bounds(b.x, b.y):
		return

	grid[index(layer, a.x, a.y)] |= PAINTED | PipeGenerator.DIR_BIT[d]
	grid[index(layer, b.x, b.y)] |= PAINTED | PipeGenerator.DIR_OPP[d]
	emit_changed()

# flip the edge between two 4-adjacent cells. closed edges open (painting both
# cells if needed), open edges close but the cells stay painted
func toggle_edge(layer: int, a: Vector2i, b: Vector2i) -> void:
	var d := direction_between(a, b)
	if d < 0 or not in_bounds(a.x, a.y) or not in_bounds(b.x, b.y):
		return

	var ia := index(layer, a.x, a.y)
	var ib := index(layer, b.x, b.y)
	if grid[ia] & PipeGenerator.DIR_BIT[d]:
		grid[ia] &= ~PipeGenerator.DIR_BIT[d]
		grid[ib] &= ~PipeGenerator.DIR_OPP[d]
	else:
		grid[ia] |= PAINTED | PipeGenerator.DIR_BIT[d]
		grid[ib] |= PAINTED | PipeGenerator.DIR_OPP[d]

	emit_changed()

# clear a cell and close the neighbours' edges into it
func erase(layer: int, x: int, y: int) -> void:
	if not in_bounds(x, y):
		return

	grid[index(layer, x, y)] = 0
	if sizes.size() == grid.size():
		sizes[index(layer, x, y)] = 0.0

	for d in 4:
		var nx := x + PipeGenerator.DIR_X[d]
		var ny := y + PipeGenerator.DIR_Y[d]
		if in_bounds(nx, ny):
			grid[index(layer, nx, ny)] &= ~PipeGenerator.DIR_OPP[d]

	emit_changed()

# per node radius, 0 goes back to the layer's default. only painted cells take one
func set_gauge(layer: int, x: int, y: int, radius: float) -> void:
	if not in_bounds(x, y) or not is_painted(layer, x, y):
		return

	if sizes.size() != grid.size():
		sizes.resize(grid.size())
		sizes.fill(0.0)

	sizes[index(layer, x, y)] = 0.0 if radius <= 0.0 else clampf(radius, GAUGE_MIN, GAUGE_MAX)
	emit_changed()

func clear(layer := -1) -> void:
	var n := cell_count()
	for l in layer_count:
		if layer >= 0 and l != layer:
			continue

		for i in n:
			grid[l * n + i] = 0
			if sizes.size() == grid.size():
				sizes[l * n + i] = 0.0

	emit_changed()

# stamp a generator grid (fill_grid output) into a layer: every connected cell
# becomes painted, empty cells stay free. the editor's Auto fill
func apply_grid(layer: int, filled: PackedByteArray) -> void:
	var n := cell_count()
	if filled.size() != n or layer < 0 or layer >= layer_count:
		return

	for i in n:
		var m := filled[i] & DIR_MASK
		if m != 0:
			grid[layer * n + i] = m | PAINTED

	emit_changed()

# whole state swap, for undo/redo
func restore(new_grid: PackedByteArray, new_sizes: PackedFloat32Array) -> void:
	grid = new_grid.duplicate()
	sizes = new_sizes.duplicate()
	emit_changed()

# --- reads for the generator ------------------------------------------------

func layer_grid(layer: int) -> PackedByteArray:
	var n := cell_count()
	if grid.size() != n * layer_count or layer < 0 or layer >= layer_count:
		var blank := PackedByteArray()
		blank.resize(n)
		return blank

	return grid.slice(layer * n, (layer + 1) * n)

func layer_sizes(layer: int) -> PackedFloat32Array:
	var n := cell_count()
	if sizes.size() != n * layer_count or layer < 0 or layer >= layer_count:
		return PackedFloat32Array()

	return sizes.slice(layer * n, (layer + 1) * n)

func painted_count(layer := -1) -> int:
	var n := cell_count()
	var total := 0
	for l in layer_count:
		if layer >= 0 and l != layer:
			continue

		for i in n:
			if grid.size() > l * n + i and grid[l * n + i] & PAINTED:
				total += 1

	return total

# direction index (0 N, 1 E, 2 S, 3 W) from a to its 4-neighbour b, -1 otherwise
static func direction_between(a: Vector2i, b: Vector2i) -> int:
	for d in 4:
		if b.x == a.x + PipeGenerator.DIR_X[d] and b.y == a.y + PipeGenerator.DIR_Y[d]:
			return d

	return -1
