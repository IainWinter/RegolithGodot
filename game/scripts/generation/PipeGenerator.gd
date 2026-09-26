extends RefCounted
class_name PipeGenerator

# pixel art pipe walls, a port of RegolithSim Scripts/PipeGen/pipegen.py (the
# C++ PipeGen.cpp port was the reference for the loop layout). the same knobs
# as the python entrypoint: width, height, seed, light, erosion, rust, sun, a
# layout override and the normals switch, plus flow (which axis the runs
# follow) for the port.
#
#   var gen := PipeGenerator.new()
#   gen.width = 72
#   gen.height = 270
#   gen.seed = 3
#   var image := gen.generate()
#
# or in one call, PipeGenerator.generate_image(72, 270, 3). the border helper
# make_border composes a horizontal and a vertical strip into a frame the way
# PipeBorderUI.cpp drew menu borders.
#
# geometry pass: seven layers of wave function collapse over the 16 N/E/S/W
# connection tiles on jittered grids, every open cell edge becomes a capsule
# from the cell centre, bends get cuffs, dead ends get a cap. a signed distance
# field per layer writes the cylinder offset vector, radius and cuff flag,
# layers blit back to front. light pass: lambert on the baked cylinder normal
# indexes a 12 entry palette, rim/edge/brass, noise stretched along the pipe,
# rust splotches pooled in absolute pixel space (so only the seed rerolls
# them), erosion bites alpha out of the deepest splotches.
#
# not bit for bit with python: the rng is Godot's pcg32 with stream seeds from
# String.hash(), value noise upsamples through Image.resize. same distribution,
# different picture for the same seed, like the C++ port was.
#
# hand layouts (the editor.py grids): a layout layer's grid byte carries the
# N/E/S/W bits in the low nibble and PAINTED (16) when the cell was placed by
# hand. a painted cell with no connections renders as a lone node. a layout
# layer with "fill": true keeps its painted cells fixed and runs WFC over the
# rest, the MIXED mode of PipeFrame

enum Flow { AUTO, HORIZONTAL, VERTICAL }

const PAD := 8
const TILE_COUNT := 16
const STUB_WEIGHT := 0.3
const WFC_TRIES := 40

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8
const DIR_MASK := 15
const PAINTED := 16

const DIR_BIT: PackedInt32Array = [1, 2, 4, 8]
const DIR_X: PackedInt32Array = [0, 1, 0, -1]
const DIR_Y: PackedInt32Array = [-1, 0, 1, 0]
const DIR_OPP: PackedInt32Array = [4, 8, 1, 2]

const PALETTE: PackedByteArray = [
	5, 4, 7,
	8, 8, 13,
	11, 11, 21,
	15, 16, 29,
	21, 24, 38,
	29, 37, 51,
	40, 54, 68,
	60, 73, 76,
	86, 95, 84,
	122, 112, 84,
	160, 152, 120,
	199, 201, 198,
]

const RUST_CORE := Vector3(68.0, 44.0, 32.0)
const RUST_EDGE := Vector3(118.0, 86.0, 52.0)
const RUST_DENSITY := 0.006
const RUST_POOL := 10.0
const MAT_VAR := 0.4

# global tuning, the P dict in pipegen.py
const TUNING := {
	"gamma": 1.100,
	"body_lo": 1.319,
	"body_hi": -0.600,
	"rim_lam": 0.905,
	"edge_lam": -0.200,
	"noise": 0.869,
	"brass": 3.200,
	"empty": 1.560,
	"run": 1.194,
	"jitter": 0.365,
	"radius": 0.880,
}

# per layer style, back layer first. cell is the grid pitch in pixels, horiz
# swaps the run weight onto east/west runs, sweep rounds the bends
const LAYERS := [
	{"cell": 10, "horiz": false, "empty": 46.0, "run": 26.0, "cross": 1.5, "bend": 0.7, "tee": 0.5, "radius": 2.2,
		"mat": 0.6, "sweep": false, "body_lo": 0.2, "body_hi": 3.4, "rim_idx": 4, "brass": 0.10, "edge_max": 0},
	{"cell": 16, "horiz": true, "empty": 150.0, "run": 24.0, "cross": 1.0, "bend": 0.5, "tee": 0.4, "radius": 2.6,
		"mat": 0.8, "sweep": true, "body_lo": 0.4, "body_hi": 4.4, "rim_idx": 5, "brass": 0.16, "edge_max": 0},
	{"cell": 11, "horiz": false, "empty": 40.0, "run": 26.0, "cross": 1.5, "bend": 0.8, "tee": 0.6, "radius": 3.0,
		"mat": 1.0, "sweep": false, "body_lo": 0.5, "body_hi": 5.6, "rim_idx": 5, "brass": 0.22, "edge_max": 0},
	{"cell": 18, "horiz": true, "empty": 200.0, "run": 22.0, "cross": 1.0, "bend": 0.5, "tee": 0.4, "radius": 3.4,
		"mat": 1.2, "sweep": true, "body_lo": 0.8, "body_hi": 7.0, "rim_idx": 6, "brass": 0.30, "edge_max": 1},
	{"cell": 12, "horiz": false, "empty": 38.0, "run": 24.0, "cross": 1.5, "bend": 0.9, "tee": 0.8, "radius": 4.4,
		"mat": 1.4, "sweep": false, "body_lo": 1.0, "body_hi": 8.0, "rim_idx": 6, "brass": 0.34, "edge_max": 1},
	{"cell": 9, "horiz": false, "empty": 52.0, "run": 26.0, "cross": 1.2, "bend": 0.7, "tee": 0.5, "radius": 1.9,
		"mat": 0.7, "sweep": true, "body_lo": 0.3, "body_hi": 4.0, "rim_idx": 5, "brass": 0.12, "edge_max": 0},
	{"cell": 13, "horiz": false, "empty": 44.0, "run": 25.0, "cross": 1.5, "bend": 0.8, "tee": 0.7, "radius": 3.8,
		"mat": 1.1, "sweep": false, "body_lo": 0.8, "body_hi": 7.0, "rim_idx": 6, "brass": 0.26, "edge_max": 1},
]

# the menu border preset PipeBorderUI.cpp shipped with
const MENU_SEED := 0x4d454e55
const MENU_TUNING := {"radius": 0.78, "empty": 1.35, "run": 1.25, "brass": 3.0}
const MENU_EROSION := 0.28
const MENU_RUST := 0.9
const MENU_THICKNESS := 26

# --- parameters, the python entrypoint's arguments -------------------------

var width := 72
var height := 270
var seed := 0
var light := Vector3(-0.62, -0.66, 0.42)
var erosion := 0.25
var rust := 1.0
var sun := Color.WHITE
var normals := false
var tuning: Dictionary = TUNING.duplicate()
var styles: Array = LAYERS
# which axis the WFC runs follow. AUTO keeps every style's own horiz flag (the
# python strip: two horizontal layers in seven), HORIZONTAL and VERTICAL turn
# every layer that way. bends and tees keep their weights so it still plumbs
var flow := Flow.AUTO
# layout override: an Array of layer dicts (see make_layer_dict), back layer
# first. non empty skips WFC and drops the 8px overscan pad. a layer with
# "fill": true is WFC'd around its painted cells (see fill_grid)
var layout: Array = []
# the layer dicts the last generate rasterised: WFC output in batch mode, the
# resolved layout otherwise. grids carry the PAINTED flag where they came from
# a hand layout
var last_layers: Array = []

# --- buffers of the last generate, composited over all layers -------------

var _w := 0
var _h := 0
var _n := 0
var _mask := PackedByteArray()
var _sd := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _rr := PackedFloat32Array()
var _cf := PackedFloat32Array()
var _lay := PackedByteArray()
var _layer_styles: Array = []
var _layer_sd := PackedFloat32Array()

static var _compat := PackedInt32Array()
static var _popcount := PackedByteArray()

# --- entry points ----------------------------------------------------------

static func generate_image(p_width := 72, p_height := 270, p_seed := 0, p_light := Vector3(-0.62, -0.66, 0.42),
		p_erosion := 0.25, p_rust := 1.0, p_sun := Color.WHITE, p_layout: Array = [], p_normals := false,
		p_flow := Flow.AUTO) -> Image:
	var gen := PipeGenerator.new()
	gen.width = p_width
	gen.height = p_height
	gen.seed = p_seed
	gen.light = p_light
	gen.erosion = p_erosion
	gen.rust = p_rust
	gen.sun = p_sun
	gen.layout = p_layout
	gen.normals = p_normals
	gen.flow = p_flow
	return gen.generate()

static func generate_texture(p_width := 72, p_height := 270, p_seed := 0) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(p_width, p_height, p_seed))

# the seed a strip of a given size gets inside a border, mixed like
# PipeBorderUI so the horizontal and vertical strips differ
static func strip_seed(base_seed: int, w: int, h: int) -> int:
	return (base_seed + w * 73856093 + h * 19349663) & 0x7fffffff

# a menu frame: horizontal strip along the top, the same strip flipped on the
# bottom, a vertical strip down the left, flipped on the right. verticals are
# blended over the corners last like the ImGui draw order was
func make_border(frame_size: Vector2i, thickness: int) -> Image:
	var w := maxi(frame_size.x, 1)
	var h := maxi(frame_size.y, 1)
	var t := clampi(thickness, 1, mini(w, h))
	var base_seed := seed

	seed = strip_seed(base_seed, w, t)
	width = w
	height = t
	var horiz := generate()

	seed = strip_seed(base_seed, t, h)
	width = t
	height = h
	var vert := generate()
	seed = base_seed

	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(horiz, Rect2i(0, 0, w, t), Vector2i(0, 0))
	var bottom: Image = horiz.duplicate()
	bottom.flip_x()
	bottom.flip_y()
	out.blend_rect(bottom, Rect2i(0, 0, w, t), Vector2i(0, h - t))
	out.blend_rect(vert, Rect2i(0, 0, t, h), Vector2i(0, 0))
	var right: Image = vert.duplicate()
	right.flip_x()
	right.flip_y()
	out.blend_rect(right, Rect2i(0, 0, t, h), Vector2i(w - t, 0))
	return out

func generate() -> Image:
	var pad := 0 if not layout.is_empty() else PAD
	_w = maxi(width, 1) + pad * 2
	_h = maxi(height, 1) + pad * 2
	_n = _w * _h
	_alloc()

	var layers: Array = _resolve_layout() if not layout.is_empty() else _batch_layers()
	last_layers = layers
	for layer in layers:
		_blit_layer(layer)

	var rgba := _normal_pass() if normals else _light_pass()
	var image := Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, rgba)
	if pad > 0:
		image = image.get_region(Rect2i(pad, pad, maxi(width, 1), maxi(height, 1)))

	return image

# fraction of pixels the pipes cover in the last generate, over the padded
# area. the python compare tool's coverage stat
func coverage() -> float:
	if _n == 0:
		return 0.0

	var filled := 0
	for i in _n:
		if _mask[i]:
			filled += 1

	return float(filled) / float(_n)

# how many cells of the last generate's grids are exactly `tile` (connection
# bits only, the PAINTED flag ignored). NORTH | SOUTH counts the vertical
# straights, EAST | WEST the horizontal ones
func count_tiles(tile: int) -> int:
	var total := 0
	for layer in last_layers:
		var grid: PackedByteArray = layer["grid"]
		for m in grid:
			if (m & DIR_MASK) == tile:
				total += 1

	return total

# --- rng streams -----------------------------------------------------------

static func stream_seed(base_seed: int, name: String) -> int:
	return (base_seed * 1000003 + (name.hash() & 0xffffffff)) & 0x7fffffff

static func stream(base_seed: int, name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream_seed(base_seed, name)
	return rng

# --- tiles and wave function collapse ---------------------------------------

# run is the weight of the straight along the layer's axis, cross_run the
# straight across it. horiz turns the axis: the tees and stubs that carry the
# run (N|S|x, N, S in the python) swap onto the east/west side too
static func tile_weights(empty: float, run: float, cross_run: float, bend: float, tee: float,
		horiz := false) -> PackedFloat32Array:
	var along := EAST | WEST if horiz else NORTH | SOUTH
	var across := NORTH | SOUTH if horiz else EAST | WEST
	var out := PackedFloat32Array()
	out.resize(TILE_COUNT)
	out[0] = empty
	out[along] = run
	out[across] = cross_run
	out[NORTH | EAST] = bend
	out[NORTH | WEST] = bend
	out[SOUTH | EAST] = bend
	out[SOUTH | WEST] = bend
	if horiz:
		out[EAST | WEST | NORTH] = tee
		out[EAST | WEST | SOUTH] = tee
		out[NORTH | SOUTH | EAST] = tee * 0.35
		out[NORTH | SOUTH | WEST] = tee * 0.35
		out[EAST] = STUB_WEIGHT
		out[WEST] = STUB_WEIGHT
		out[NORTH] = STUB_WEIGHT * 0.2
		out[SOUTH] = STUB_WEIGHT * 0.2
	else:
		out[NORTH | SOUTH | EAST] = tee
		out[NORTH | SOUTH | WEST] = tee
		out[NORTH | EAST | WEST] = tee * 0.35
		out[SOUTH | EAST | WEST] = tee * 0.35
		out[NORTH] = STUB_WEIGHT
		out[SOUTH] = STUB_WEIGHT
		out[EAST] = STUB_WEIGHT * 0.2
		out[WEST] = STUB_WEIGHT * 0.2

	out[NORTH | SOUTH | EAST | WEST] = tee * 0.2
	return out

# whether a layer runs east/west under the given flow: AUTO reads the style
static func layer_horizontal(style: Dictionary, p_flow: int) -> bool:
	if p_flow == Flow.HORIZONTAL:
		return true

	if p_flow == Flow.VERTICAL:
		return false

	return style["horiz"]

static func layer_weights(style: Dictionary, p_tuning: Dictionary, p_flow := Flow.AUTO) -> PackedFloat32Array:
	var e: float = style["empty"] * p_tuning["empty"]
	var r: float = style["run"] * p_tuning["run"]
	return tile_weights(e, r, style["cross"], style["bend"], style["tee"], layer_horizontal(style, p_flow))

static func is_bend(tile: int) -> bool:
	return tile == (NORTH | EAST) or tile == (NORTH | WEST) or tile == (SOUTH | EAST) or tile == (SOUTH | WEST)

# compat[d * 16 + a] is the bitmask of tiles allowed next to tile a in
# direction d: linked edges must match, and two bends may only chain when
# they mirror (a U), never into an S
static func compat_table() -> PackedInt32Array:
	if not _compat.is_empty():
		return _compat

	var table := PackedInt32Array()
	table.resize(4 * TILE_COUNT)
	for d in 4:
		var bit := DIR_BIT[d]
		var opp := DIR_OPP[d]
		for a in TILE_COUNT:
			var allow := 0
			for b in TILE_COUNT:
				var linked := (a & bit) != 0
				if linked != ((b & opp) != 0):
					continue

				if linked and is_bend(a) and is_bend(b) and (a & ~bit) != (b & ~opp):
					continue

				allow |= 1 << b

			table[d * TILE_COUNT + a] = allow

	_compat = table
	return _compat

static func popcount_table() -> PackedByteArray:
	if not _popcount.is_empty():
		return _popcount

	var table := PackedByteArray()
	table.resize(256)
	for i in range(1, 256):
		table[i] = table[i >> 1] + (i & 1)

	_popcount = table
	return _popcount

@warning_ignore("integer_division")
static func _wfc_propagate(wave: PackedInt32Array, counts: PackedByteArray, gw: int, gh: int, stack: Array[int]) -> bool:
	var compat := compat_table()
	var pop := popcount_table()
	while not stack.is_empty():
		var cell: int = stack.pop_back()
		var x := cell % gw
		var y := cell / gw
		var here := wave[cell]
		var reach_n := 0
		var reach_e := 0
		var reach_s := 0
		var reach_w := 0
		for a in TILE_COUNT:
			if here & (1 << a):
				reach_n |= compat[a]
				reach_e |= compat[TILE_COUNT + a]
				reach_s |= compat[2 * TILE_COUNT + a]
				reach_w |= compat[3 * TILE_COUNT + a]

		for d in 4:
			var nx := x + DIR_X[d]
			var ny := y + DIR_Y[d]
			if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
				continue

			var reach := reach_n
			if d == 1:
				reach = reach_e
			elif d == 2:
				reach = reach_s
			elif d == 3:
				reach = reach_w

			var nb := nx + ny * gw
			var allow := wave[nb] & reach
			if allow == 0:
				return false

			if allow != wave[nb]:
				wave[nb] = allow
				counts[nb] = pop[allow & 255] + pop[allow >> 8]
				stack.push_back(nb)

	return true

static func _wfc_observe(wave: PackedInt32Array, counts: PackedByteArray, gw: int, gh: int, weights: PackedFloat32Array,
		rng: RandomNumberGenerator, cell: int) -> bool:
	var here := wave[cell]
	var total := 0.0
	for t in TILE_COUNT:
		if here & (1 << t):
			total += weights[t]

	var roll := rng.randf() * total
	var pick := -1
	var run := 0.0
	for t in TILE_COUNT:
		if not (here & (1 << t)):
			continue

		run += weights[t]
		pick = t
		if run > roll:
			break

	wave[cell] = 1 << pick
	counts[cell] = 1
	var stack: Array[int] = [cell]
	return _wfc_propagate(wave, counts, gw, gh, stack)

# lowest entropy first with a little noise to break ties, like the python
static func _wfc_solve(wave: PackedInt32Array, counts: PackedByteArray, gw: int, gh: int, weights: PackedFloat32Array,
		rng: RandomNumberGenerator) -> bool:
	var count := gw * gh
	while true:
		var best := -1
		var best_score := 1e9
		for i in count:
			var bits := counts[i]
			if bits < 2:
				continue

			var score := float(bits) + rng.randf() * 0.4
			if score < best_score:
				best = i
				best_score = score

		if best < 0:
			return true

		if not _wfc_observe(wave, counts, gw, gh, weights, rng, best):
			return false

	return true

# collapse every PAINTED cell of `fixed` to its own tile and propagate, so the
# free cells only take tiles that connect to the hand drawn ones. false when
# the drawing contradicts the tile grammar (an S of two bends, say)
static func _wfc_fix(wave: PackedInt32Array, counts: PackedByteArray, gw: int, gh: int, fixed: PackedByteArray) -> bool:
	var stack: Array[int] = []
	for i in gw * gh:
		var m := fixed[i]
		if m & PAINTED:
			wave[i] = 1 << (m & DIR_MASK)
			counts[i] = 1
			stack.push_back(i)

	return _wfc_propagate(wave, counts, gw, gh, stack)

# wave function collapse over a gw by gh grid. `fixed`, when the size of the
# grid, pins its PAINTED cells: they come back unchanged (flag included) and
# the rest is solved around them. a drawing the grammar cannot satisfy falls
# back to an unconstrained solve with the painted cells stamped over it
static func wfc_grid(gw: int, gh: int, weights: PackedFloat32Array, rng: RandomNumberGenerator,
		fixed := PackedByteArray()) -> PackedByteArray:
	var wave := PackedInt32Array()
	wave.resize(gw * gh)
	var counts := PackedByteArray()
	counts.resize(gw * gh)
	var pinned := fixed.size() == gw * gh
	for _attempt in WFC_TRIES:
		wave.fill(0xffff)
		counts.fill(TILE_COUNT)
		if pinned and not _wfc_fix(wave, counts, gw, gh, fixed):
			pinned = false
			wave.fill(0xffff)
			counts.fill(TILE_COUNT)

		if _wfc_solve(wave, counts, gw, gh, weights, rng):
			break

	var grid := PackedByteArray()
	grid.resize(gw * gh)
	for i in gw * gh:
		var w := wave[i]
		var tile := 0
		for t in TILE_COUNT:
			if w & (1 << t):
				tile = t
				break

		grid[i] = tile

	if fixed.size() == gw * gh:
		for i in gw * gh:
			if fixed[i] & PAINTED:
				grid[i] = fixed[i]

	return grid

# drop every connection that points at a cell not pointing back, until
# stable. painted cells are the author's and keep every edge they were given
static func prune_stubs(grid: PackedByteArray, gw: int, gh: int) -> void:
	var changed := true
	while changed:
		changed = false
		for y in gh:
			for x in gw:
				var m := grid[x + y * gw]
				if m == 0 or m & PAINTED:
					continue

				for d in 4:
					if not (m & DIR_BIT[d]):
						continue

					var nx := x + DIR_X[d]
					var ny := y + DIR_Y[d]
					if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
						continue

					if not (grid[nx + ny * gw] & DIR_OPP[d]):
						m &= ~DIR_BIT[d]
						grid[x + y * gw] = m
						changed = true

static func grid_lines(total: int, cell: int, jitter: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(-rng.randf_range(0.2, 1.0) * cell)
	while out[out.size() - 1] < float(total + cell):
		out.append(out[out.size() - 1] + cell * rng.randf_range(1.0 - jitter, 1.0 + jitter))

	return out

# a layer dict as generate consumes them: grid of N/E/S/W bitmasks row major,
# ex/ey the grid line positions in pixels (one more than the grid size), sizes
# an optional per node radius (0 falls back to the style radius)
static func make_layer_dict(grid: PackedByteArray, gw: int, gh: int, ex: PackedFloat32Array, ey: PackedFloat32Array,
		style: Dictionary, sizes := PackedFloat32Array()) -> Dictionary:
	return {"grid": grid, "width": gw, "height": gh, "ex": ex, "ey": ey, "style": style, "sizes": sizes}

# a hand drawn layer on a uniform lattice, for menu frames authored in code
static func uniform_layer(grid: PackedByteArray, gw: int, gh: int, cell: float, style: Dictionary,
		origin := Vector2.ZERO, sizes := PackedFloat32Array()) -> Dictionary:
	var ex := PackedFloat32Array()
	for x in gw + 1:
		ex.append(origin.x + x * cell)

	var ey := PackedFloat32Array()
	for y in gh + 1:
		ey.append(origin.y + y * cell)

	return make_layer_dict(grid, gw, gh, ex, ey, style, sizes)

func make_layer(style: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cell: int = style["cell"]
	var jitter: float = tuning["jitter"]
	var ex := grid_lines(_w, cell, jitter, rng)
	var ey := grid_lines(_h, cell, jitter, rng)
	var gw := ex.size() - 1
	var gh := ey.size() - 1
	var grid := wfc_grid(gw, gh, layer_weights(style, tuning, flow), rng)
	prune_stubs(grid, gw, gh)
	return make_layer_dict(grid, gw, gh, ex, ey, style)

func _batch_layers() -> Array:
	var out := []
	for i in styles.size():
		out.append(make_layer(styles[i], stream(seed, "layout%d" % i)))

	return out

# WFC around the PAINTED cells of a hand grid: the painted cells come back as
# they were, every other cell gets a tile that connects to them, with this
# generator's flow and tuning. the MIXED mode and the editor's Auto fill
func fill_grid(grid: PackedByteArray, gw: int, gh: int, style: Dictionary, layer_index := 0) -> PackedByteArray:
	var out := wfc_grid(gw, gh, layer_weights(style, tuning, flow), stream(seed, "fill%d" % layer_index), grid)
	prune_stubs(out, gw, gh)
	return out

# the layout with every "fill" layer solved
func _resolve_layout() -> Array:
	var out := []
	for i in layout.size():
		var layer: Dictionary = layout[i]
		if layer.get("fill", false):
			layer = layer.duplicate()
			layer["grid"] = fill_grid(layer["grid"], layer["width"], layer["height"], layer["style"], i)
			layer["fill"] = false

		out.append(layer)

	return out

# --- capsules ------------------------------------------------------------

# capsules are 7 floats each: x0 y0 x1 y1 r cuff box
const CAP_STRIDE := 7

static func _add_capsule(caps: PackedFloat32Array, x0: float, y0: float, x1: float, y1: float, r: float,
		cuff := 0.0, box := 0.0) -> void:
	caps.append(x0)
	caps.append(y0)
	caps.append(x1)
	caps.append(y1)
	caps.append(r)
	caps.append(cuff)
	caps.append(box)

# a short box on the pipe axis with a slightly bigger radius, square shoulders
static func _add_cuff_band(caps: PackedFloat32Array, px: float, py: float, d: int, r: float, thick: float) -> void:
	if r < 1.8:
		return

	var dx := float(DIR_X[d])
	var dy := float(DIR_Y[d])
	var grow := 1.0 if r < 3.4 else 1.4
	_add_capsule(caps, px - dx * thick, py - dy * thick, px + dx * thick, py + dy * thick, r + grow, 1.0, 1.0)

static func _add_sweep_bend(caps: PackedFloat32Array, cx: float, cy: float, pa: Vector2, pb: Vector2, r: float) -> void:
	const STEPS := 5
	const K := 0.62
	var ka := Vector2(pa.x + (cx - pa.x) * K, pa.y + (cy - pa.y) * K)
	var kb := Vector2(pb.x + (cx - pb.x) * K, pb.y + (cy - pb.y) * K)
	var pts := PackedVector2Array()
	for i in STEPS + 1:
		var t := float(i) / STEPS
		var u := 1.0 - t
		pts.append(Vector2(u * u * ka.x + 2.0 * u * t * cx + t * t * kb.x, u * u * ka.y + 2.0 * u * t * cy + t * t * kb.y))

	_add_capsule(caps, pa.x, pa.y, ka.x, ka.y, r)
	for i in STEPS:
		_add_capsule(caps, pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, r)

	_add_capsule(caps, kb.x, kb.y, pb.x, pb.y, r)

func _build_capsules(layer: Dictionary) -> PackedFloat32Array:
	var caps := PackedFloat32Array()
	var grid: PackedByteArray = layer["grid"]
	var gw: int = layer["width"]
	var gh: int = layer["height"]
	var ex: PackedFloat32Array = layer["ex"]
	var ey: PackedFloat32Array = layer["ey"]
	var style: Dictionary = layer["style"]
	var sizes: PackedFloat32Array = layer.get("sizes", PackedFloat32Array())
	var has_sizes := sizes.size() == gw * gh
	var style_radius: float = style["radius"]
	var sweep: bool = style["sweep"]
	var radius_scale: float = tuning["radius"]
	var ends: Array[int] = []
	var end_pos := PackedVector2Array()

	for y in gh:
		for x in gw:
			var m := grid[x + y * gw]
			if m == 0:
				continue

			var r := style_radius
			if has_sizes and sizes[x + y * gw] > 0.0:
				r = sizes[x + y * gw]

			r *= radius_scale
			var cx := (ex[x] + ex[x + 1]) * 0.5
			var cy := (ey[y] + ey[y + 1]) * 0.5
			ends.clear()
			end_pos.clear()
			m &= DIR_MASK
			if m == 0:
				# a painted cell with nothing attached yet, a lone node
				_add_capsule(caps, cx, cy, cx, cy, r)
				continue

			if m & NORTH:
				ends.append(0)
				end_pos.append(Vector2(cx, ey[y]))

			if m & SOUTH:
				ends.append(2)
				end_pos.append(Vector2(cx, ey[y + 1]))

			if m & WEST:
				ends.append(3)
				end_pos.append(Vector2(ex[x], cy))

			if m & EAST:
				ends.append(1)
				end_pos.append(Vector2(ex[x + 1], cy))

			var count := ends.size()
			var bend := count == 2 and m != (NORTH | SOUTH) and m != (EAST | WEST)
			var thick := 1.5 if r < 3.2 else 2.0
			if bend and sweep:
				_add_sweep_bend(caps, cx, cy, end_pos[0], end_pos[1], r)
			else:
				for i in count:
					_add_capsule(caps, cx, cy, end_pos[i].x, end_pos[i].y, r)

			if bend or count >= 3:
				var back := r + thick + 1.5
				for i in count:
					var d := ends[i]
					_add_cuff_band(caps, end_pos[i].x - DIR_X[d] * back, end_pos[i].y - DIR_Y[d] * back, d, r, thick)

			if count == 1:
				var d := ends[0]
				_add_capsule(caps, cx, cy, cx, cy, r)
				_add_cuff_band(caps, cx - DIR_X[d] * r * 0.4, cy - DIR_Y[d] * r * 0.4, d, r, thick)

	return caps

# --- distance field --------------------------------------------------------

func _alloc() -> void:
	_mask.resize(_n)
	_mask.fill(0)
	_sd.resize(_n)
	_sd.fill(1e6)
	_vx.resize(_n)
	_vx.fill(0.0)
	_vy.resize(_n)
	_vy.fill(0.0)
	_rr.resize(_n)
	_rr.fill(0.0)
	_cf.resize(_n)
	_cf.fill(0.0)
	_lay.resize(_n)
	_lay.fill(0)
	_layer_sd.resize(_n)
	_layer_styles.clear()

# rasterise one layer's capsules. the layer keeps its own running minimum
# distance, and whenever a capsule beats it while inside the surface the
# pixel is written straight into the composited buffers, so a nearer layer
# overwrites a farther one exactly where it is solid
func _blit_layer(layer: Dictionary) -> void:
	var caps := _build_capsules(layer)
	if caps.is_empty():
		return

	_layer_styles.append(layer["style"])
	var layer_index := _layer_styles.size() - 1
	var w := _w
	var h := _h
	var lsd := _layer_sd
	lsd.fill(1e6)
	var sd := _sd
	var vx := _vx
	var vy := _vy
	var rr := _rr
	var cf := _cf
	var lay := _lay
	var mask := _mask

	@warning_ignore("integer_division")
	var cap_count := caps.size() / CAP_STRIDE
	for c in cap_count:
		var o := c * CAP_STRIDE
		var cx0 := caps[o]
		var cy0 := caps[o + 1]
		var cx1 := caps[o + 2]
		var cy1 := caps[o + 3]
		var r := caps[o + 4]
		var cuff := caps[o + 5]
		var box := caps[o + 6] > 0.5
		var pad := r + 3.0
		var x0 := maxi(0, floori(minf(cx0, cx1) - pad))
		var x1 := mini(w, ceili(maxf(cx0, cx1) + pad) + 1)
		var y0 := maxi(0, floori(minf(cy0, cy1) - pad))
		var y1 := mini(h, ceili(maxf(cy0, cy1) + pad) + 1)
		if x0 >= x1 or y0 >= y1:
			continue

		var ex := cx1 - cx0
		var ey := cy1 - cy0
		var ll := ex * ex + ey * ey
		if box and ll > 1e-9:
			var length := sqrt(ll)
			var ux := ex / length
			var uy := ey / length
			var half := length * 0.5
			var mx := ex * 0.5
			var my := ey * 0.5
			for y in range(y0, y1):
				var py := y + 0.5 - cy0
				var row := y * w
				for x in range(x0, x1):
					var px := x + 0.5 - cx0
					var along := (px - mx) * ux + (py - my) * uy
					var proj := px * ux + py * uy
					var qx := px - proj * ux
					var qy := py - proj * uy
					var d := maxf(sqrt(qx * qx + qy * qy) - r, absf(along) - half)
					var i := row + x
					if d < lsd[i]:
						lsd[i] = d
						if d <= 0.0:
							sd[i] = d
							vx[i] = qx
							vy[i] = qy
							rr[i] = r
							cf[i] = cuff
							lay[i] = layer_index
							mask[i] = 1
		else:
			var inv_ll := 1.0 / ll if ll >= 1e-9 else 0.0
			for y in range(y0, y1):
				var py := y + 0.5 - cy0
				var row := y * w
				for x in range(x0, x1):
					var px := x + 0.5 - cx0
					var t := clampf((px * ex + py * ey) * inv_ll, 0.0, 1.0)
					var qx := px - t * ex
					var qy := py - t * ey
					var d := sqrt(qx * qx + qy * qy) - r
					var i := row + x
					if d < lsd[i]:
						lsd[i] = d
						if d <= 0.0:
							sd[i] = d
							vx[i] = qx
							vy[i] = qy
							rr[i] = r
							cf[i] = cuff
							lay[i] = layer_index
							mask[i] = 1

# --- noise ---------------------------------------------------------------

# value noise, a random lattice of cx by cy pixel cells upsampled bilinearly
# per octave (Image.resize, centre aligned like PIL), octaves summed at
# halving amplitude and normalised to 0..1
static func value_noise(w: int, h: int, noise_seed: int, sx: int, sy: int, octaves := 3) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var n := w * h
	var out := PackedFloat32Array()
	out.resize(n)
	var amp := 1.0
	var total := 0.0
	var datas: Array[PackedByteArray] = []
	var amps := PackedFloat32Array()
	for o in octaves:
		var cx := maxi(1, sx >> o)
		var cy := maxi(1, sy >> o)
		@warning_ignore("integer_division")
		var gw := w / cx + 2
		@warning_ignore("integer_division")
		var gh := h / cy + 2
		var lattice := PackedByteArray()
		lattice.resize(gw * gh)
		for i in gw * gh:
			lattice[i] = rng.randi() & 255

		var img := Image.create_from_data(gw, gh, false, Image.FORMAT_L8, lattice)
		img.resize(gw * cx, gh * cy, Image.INTERPOLATE_BILINEAR)
		img.crop(w, h)
		datas.append(img.get_data())
		amps.append(amp)
		total += amp
		amp *= 0.5

	var scale := 1.0 / (255.0 * total)
	if octaves == 3:
		var d0 := datas[0]
		var d1 := datas[1]
		var d2 := datas[2]
		var a1 := amps[1]
		var a2 := amps[2]
		for i in n:
			out[i] = (d0[i] + a1 * d1[i] + a2 * d2[i]) * scale
	else:
		for o in octaves:
			var data := datas[o]
			var a := amps[o] * scale
			for i in n:
				out[i] += a * data[i]

	return out

# --- rust ----------------------------------------------------------------

# rust splotches, ellipses stretched along the pipe axis with noise chewed
# edges, accumulated with a max. candidate centres are a fixed pool over the
# whole image so only the seed moves them, erosion and rust just turn more of
# the same pool on. wet (downward facing) surfaces and cuffs collect more
func _corrosion_field(ux: PackedFloat32Array, uy: PackedFloat32Array, tt: PackedFloat32Array, wet: PackedFloat32Array,
		corr_seed: int) -> PackedFloat32Array:
	var w := _w
	var h := _h
	var n := _n
	var mask := _mask
	var cf := _cf
	var amt := PackedFloat32Array()
	amt.resize(n)
	amt.fill(0.0)

	for i in n:
		wet[i] = clampf(0.5 + uy[i] * tt[i] * 0.5, 0.0, 1.0)

	var pool := int(h * w * RUST_DENSITY * RUST_POOL)
	if pool < 1:
		return amt

	var rng := RandomNumberGenerator.new()
	rng.seed = corr_seed
	var ragged := value_noise(w, h, stream_seed(corr_seed, "ragged"), 3, 3, 2)
	var density := minf(1.0, maxf(rust, 0.35) * (0.35 + erosion * 1.3) / RUST_POOL)

	for _k in pool:
		var sx := int(rng.randf() * w)
		var sy := int(rng.randf() * h)
		var accept := rng.randf()
		var key := rng.randf()
		var fat := rng.randf()
		var r_fat := 2.8 + rng.randf() * 2.6
		var r_thin := 1.3 + rng.randf() * 1.5
		var stretch := 1.3 + rng.randf() * 1.1
		var at := sx + sy * w
		if not mask[at]:
			continue

		var weight := 0.20 + wet[at] * 0.80 + cf[at] * 0.35
		if accept >= weight or key >= density:
			continue

		var cx := float(sx)
		var cy := float(sy)
		var r := r_fat if fat < 0.15 else r_thin
		var ax := -uy[at]
		var ay := ux[at]
		var pad := ceili(r * stretch) + 2
		var x0 := maxi(0, sx - pad)
		var x1 := mini(w, sx + pad + 1)
		var y0 := maxi(0, sy - pad)
		var y1 := mini(h, sy + pad + 1)
		var falloff := maxf(r * 0.45, 0.6)
		var inv_stretch := 1.0 / stretch
		for y in range(y0, y1):
			var dy := y + 0.5 - cy
			var row := y * w
			for x in range(x0, x1):
				var dx := x + 0.5 - cx
				var along := (dx * ax + dy * ay) * inv_stretch
				var across := dx * -ay + dy * ax
				var d := sqrt(along * along + across * across)
				var i := row + x
				var edge := r * (0.72 + 0.56 * ragged[i])
				var a := clampf((edge - d) / falloff, 0.0, 1.0)
				if a > amt[i]:
					amt[i] = a

	var fringe := RandomNumberGenerator.new()
	fringe.seed = stream_seed(corr_seed, "fringe")
	for i in n:
		var a := amt[i]
		if a > 0.0:
			a *= (0.45 + 0.55 * wet[i]) if mask[i] else 0.0

		var f := fringe.randf()
		if a > 0.18 and a < 0.45 and f > 0.62:
			a = 0.0

		amt[i] = a if a > 0.18 else 0.0

	return amt

# --- shading ---------------------------------------------------------------

# cylinder normal per pixel from the offset vector and the radius. t is how
# far out from the axis the pixel sits, 0 on the axis, 1 at the silhouette
func _surface(ux: PackedFloat32Array, uy: PackedFloat32Array, tt: PackedFloat32Array) -> void:
	var vx := _vx
	var vy := _vy
	var rr := _rr
	var mask := _mask
	for i in _n:
		if not mask[i]:
			continue

		var x := vx[i]
		var y := vy[i]
		var length := sqrt(x * x + y * y) + 1e-6
		ux[i] = x / length
		uy[i] = y / length
		tt[i] = clampf(length / maxf(rr[i], 0.5), 0.0, 1.0)

func _normal_pass() -> PackedByteArray:
	var n := _n
	var ux := PackedFloat32Array()
	ux.resize(n)
	var uy := PackedFloat32Array()
	uy.resize(n)
	var tt := PackedFloat32Array()
	tt.resize(n)
	_surface(ux, uy, tt)

	var out := PackedByteArray()
	out.resize(n * 4)
	out.fill(0)
	var mask := _mask
	for i in n:
		if not mask[i]:
			continue

		var t := tt[i]
		var nz := sqrt(maxf(0.0, 1.0 - t * t))
		var o := i * 4
		out[o] = clampi(int((ux[i] * t * 0.5 + 0.5) * 255.0), 0, 255)
		out[o + 1] = clampi(int((uy[i] * t * 0.5 + 0.5) * 255.0), 0, 255)
		out[o + 2] = clampi(int((nz * 0.5 + 0.5) * 255.0), 0, 255)
		out[o + 3] = 255

	return out

func _light_pass() -> PackedByteArray:
	var w := _w
	var h := _h
	var n := _n
	var mask := _mask
	var sd := _sd
	var cf := _cf
	var lay := _lay

	var ux := PackedFloat32Array()
	ux.resize(n)
	var uy := PackedFloat32Array()
	uy.resize(n)
	var tt := PackedFloat32Array()
	tt.resize(n)
	_surface(ux, uy, tt)

	var ln := light.length()
	var lx := light.x / ln if ln > 0.0 else 0.0
	var ly := light.y / ln if ln > 0.0 else 0.0
	var lz := light.z / ln if ln > 0.0 else 1.0

	var gamma: float = tuning["gamma"]
	var t_body_lo: float = tuning["body_lo"]
	var t_body_hi: float = tuning["body_hi"]
	var rim_lam: float = tuning["rim_lam"]
	var edge_lam: float = tuning["edge_lam"]
	var t_noise: float = tuning["noise"]
	var t_brass: float = tuning["brass"]

	# per layer scalars, indexed by the layer byte
	var layer_count := _layer_styles.size()
	var s_mat := PackedFloat32Array()
	var s_lo := PackedFloat32Array()
	var s_hi := PackedFloat32Array()
	var s_rim := PackedInt32Array()
	var s_brass := PackedFloat32Array()
	var s_edge := PackedInt32Array()
	for k in layer_count:
		var style: Dictionary = _layer_styles[k]
		s_mat.append((style["mat"] - 1.0) * MAT_VAR)
		s_lo.append(style["body_lo"] + t_body_lo)
		s_hi.append(style["body_hi"] + t_body_hi)
		s_rim.append(int(style["rim_idx"]))
		s_brass.append(style["brass"] * t_brass)
		s_edge.append(int(style["edge_max"]))

	var noise := value_noise(w, h, stream_seed(seed, "noise"), 3, 14)
	var blotch := value_noise(w, h, stream_seed(seed, "blotch"), 5, 16)
	var patch := value_noise(w, h, stream_seed(seed, "patch"), 2, 7)
	var chew := value_noise(w, h, stream_seed(seed, "chew"), 2, 2)
	var grain := stream(seed, "grain")
	var brass := stream(seed, "brass")
	var pit := stream(seed, "pit")

	var lam := PackedFloat32Array()
	lam.resize(n)
	var idx := PackedByteArray()
	idx.resize(n)

	# lambert normalised by the brightest this pipe's orientation can reach,
	# tone ramp into the palette, rim and dark edge, sparse brass on the rim
	for i in n:
		var g := grain.randf()
		var b := brass.randf()
		if not mask[i]:
			continue

		var t := tt[i]
		var nx := ux[i] * t
		var ny := uy[i] * t
		var nz := sqrt(maxf(0.0, 1.0 - t * t))
		var dot := nx * lx + ny * ly + nz * lz
		var la := -uy[i] * lx + ux[i] * ly
		var lmax := sqrt(clampf(1.0 - la * la, 1e-3, 1.0))
		var l := clampf(dot / lmax, -1.0, 1.0)
		lam[i] = l

		var k := lay[i]
		var lo := s_lo[k]
		var hi := s_hi[k]
		var tone := pow(clampf(l, 0.0, 1.0), gamma)
		var shade := lo + tone * (hi - lo)
		shade += s_mat[k]
		shade += (noise[i] - 0.5) * 1.3 * t_noise
		shade += (blotch[i] - 0.5) * 1.6
		shade += (g - 0.5) * 0.6 * t_noise
		var index := clampi(roundi(shade), 0, 8)

		var outer := sd[i] > -1.0
		var rim := outer and l > rim_lam + (blotch[i] - 0.5) * 0.22
		if outer and l < edge_lam:
			index = mini(index, s_edge[k])

		if rim:
			index = maxi(index, s_rim[k])
			var chance := s_brass[k]
			if patch[i] > 0.56 and b < chance * 2.0:
				index = 9 if b < chance * 0.7 else 7

		idx[i] = index

	var wet := PackedFloat32Array()
	wet.resize(n)
	var corr := _corrosion_field(ux, uy, tt, wet, stream_seed(seed, "corrosion"))

	var sqrt_erosion := sqrt(maxf(erosion, 0.0))
	var wreck := erosion > 0.75
	var pit_chance := erosion * 0.25
	var rust_vis := minf(1.0, rust)
	var sun_top := maxf(sun.r, maxf(sun.g, sun.b))
	var sun_low := minf(sun.r, minf(sun.g, sun.b))
	var tinted := sun_top > 0.0 and sun_low < sun_top
	var warm := Vector3(sun.r, sun.g, sun.b) / sun_top if tinted else Vector3.ONE

	var out := PackedByteArray()
	out.resize(n * 4)
	out.fill(0)

	# erosion bites alpha where the rust is deepest, pits darken inside
	# patches, rust tints, the sun colours the lit side
	for i in n:
		var pitn := pit.randf()
		if not mask[i]:
			continue

		var c := corr[i]
		var deep := clampf((c - 0.22) / 0.78, 0.0, 1.0)
		var depth := deep * sqrt_erosion * 9.0 * (0.35 + 1.1 * chew[i])
		if depth > 0.2 and sd[i] > -depth:
			continue

		if wreck and c > 0.92:
			continue

		var index := int(idx[i])
		if pitn < pit_chance and c > 0.55:
			index = maxi(index - 2, 0)

		var p := index * 3
		var r := float(PALETTE[p])
		var g := float(PALETTE[p + 1])
		var bl := float(PALETTE[p + 2])
		var l := lam[i]

		if c > 0.02:
			var mix := clampf(c * 1.5 - 0.25, 0.0, 1.0)
			var shade := clampf(0.62 + l * 0.55, 0.35, 1.25)
			var a := minf(0.68, c * 0.85) * rust_vis
			var tint := (RUST_EDGE + (RUST_CORE - RUST_EDGE) * mix) * shade
			r = r * (1.0 - a) + tint.x * a
			g = g * (1.0 - a) + tint.y * a
			bl = bl * (1.0 - a) + tint.z * a

		if tinted:
			var k := clampf(l, 0.0, 1.0)
			r *= (1.0 - k) + k * warm.x
			g *= (1.0 - k) + k * warm.y
			bl *= (1.0 - k) + k * warm.z

		var o := i * 4
		out[o] = clampi(int(r), 0, 255)
		out[o + 1] = clampi(int(g), 0, 255)
		out[o + 2] = clampi(int(bl), 0, 255)
		out[o + 3] = 255

	return out
