extends GutTest

# PipeGenerator: fixed seeds give the same pixels, the asked size comes back,
# a strip is neither empty nor solid, normals cover the lit pixels, a hand
# layout puts the pipe where it was drawn, borders are hollow, the 72x270
# python default strip generates inside the time budget, flow turns the runs.
# PipeFrame: the zone is the node's size and regenerates on resize, MANUAL
# renders only the painted cells, MIXED keeps them and fills around, the
# PipeLayout survives a scene save, the editor plugin scripts compile

const TIME_BUDGET_MS := 1000.0
const ROUNDTRIP_PATH := "user://test_pipe_layout_roundtrip.tscn"

func alpha_coverage(image: Image) -> float:
	var data := image.get_data()
	var count := image.get_width() * image.get_height()
	var solid := 0
	for i in count:
		if data[i * 4 + 3] > 0:
			solid += 1
	return float(solid) / float(count)

# a stroke of the Pipe brush: paint the first cell, link each next one to the previous
func paint_run(layout: PipeLayout, layer: int, cells: Array) -> void:
	for i in cells.size():
		if i == 0:
			layout.paint(layer, cells[0].x, cells[0].y)
		else:
			layout.connect_cells(layer, cells[i - 1], cells[i])

# a PLATE frame with a fresh layout fitted to size / cell_size, wear off so
# the alpha is the geometry
func manual_frame(placement: int, frame_size: Vector2, cell: int, frame_seed: int) -> PipeFrame:
	var frame := PipeFrame.new()
	frame.mode = PipeFrame.Mode.PLATE
	frame.placement = placement
	frame.size = frame_size
	frame.cell_size = cell
	frame.seed = frame_seed
	frame.erosion = 0.0
	frame.rust = 0.0
	frame.ensure_layout()
	return frame

# --- generator -----------------------------------------------------------

func test_same_seed_same_pixels_and_other_seed_differs() -> void:
	var a := PipeGenerator.generate_image(40, 60, 5)
	var b := PipeGenerator.generate_image(40, 60, 5)
	var c := PipeGenerator.generate_image(40, 60, 6)
	assert_eq(a.get_data(), b.get_data(), "seed 5 twice")
	assert_ne(a.get_data(), c.get_data(), "seed 6 is a different picture")

func test_image_is_the_asked_size_and_rgba8() -> void:
	var image := PipeGenerator.generate_image(40, 60, 1)
	assert_eq(image.get_size(), Vector2i(40, 60))
	assert_eq(image.get_format(), Image.FORMAT_RGBA8)

func test_strip_is_partly_covered_by_pipes() -> void:
	var image := PipeGenerator.generate_image(72, 270, 3)
	var coverage := alpha_coverage(image)
	assert_between(coverage, 0.25, 0.9, "coverage %.2f like the python batch stat 0.62 +- 0.07" % coverage)

	var lit := 0
	var data := image.get_data()
	for i in 72 * 270:
		if data[i * 4 + 3] > 0 and data[i * 4] + data[i * 4 + 1] + data[i * 4 + 2] > 3 * 40:
			lit += 1
	assert_gt(lit, 100, "some pixels sit on the lit end of the palette")

func test_lighting_does_not_move_the_silhouette() -> void:
	var a := PipeGenerator.generate_image(48, 96, 9, Vector3(-0.62, -0.66, 0.42))
	var b := PipeGenerator.generate_image(48, 96, 9, Vector3(0.7, -0.2, 0.5))
	var da := a.get_data()
	var db := b.get_data()
	var alpha_diff := 0
	var rgb_diff := 0
	for i in 48 * 96:
		if da[i * 4 + 3] != db[i * 4 + 3]:
			alpha_diff += 1
		if da[i * 4] != db[i * 4]:
			rgb_diff += 1
	assert_eq(alpha_diff, 0, "the light only relights, the erosion stays put")
	assert_gt(rgb_diff, 0, "the light changes the shading")

func test_normals_cover_every_lit_pixel() -> void:
	var lit := PipeGenerator.generate_image(48, 96, 4)
	var normals := PipeGenerator.generate_image(48, 96, 4, Vector3(-0.62, -0.66, 0.42), 0.25, 1.0, Color.WHITE, [], true)
	var dl := lit.get_data()
	var dn := normals.get_data()
	var missing := 0
	var facing := 0
	for i in 48 * 96:
		if dl[i * 4 + 3] > 0 and dn[i * 4 + 3] == 0:
			missing += 1
		if dn[i * 4 + 3] > 0 and dn[i * 4 + 2] > 128:
			facing += 1
	assert_eq(missing, 0, "erosion only removes pixels, never adds")
	assert_gt(facing, 0, "the normal z points at the viewer")

func test_sun_tint_warms_the_lit_side() -> void:
	var white := PipeGenerator.generate_image(48, 96, 2, Vector3(-0.62, -0.66, 0.42), 0.25, 1.0, Color.WHITE)
	var warm := PipeGenerator.generate_image(48, 96, 2, Vector3(-0.62, -0.66, 0.42), 0.25, 1.0, Color8(255, 200, 120))
	var dw := white.get_data()
	var dt := warm.get_data()
	var bluer := 0
	for i in 48 * 96:
		if dw[i * 4 + 3] > 0 and dt[i * 4 + 2] < dw[i * 4 + 2]:
			bluer += 1
	assert_gt(bluer, 0, "an orange sun drops blue out of the lit pixels")

func test_hand_layout_draws_a_pipe_down_the_middle() -> void:
	var grid := PackedByteArray([
		PipeGenerator.SOUTH,
		PipeGenerator.NORTH | PipeGenerator.SOUTH,
		PipeGenerator.NORTH,
	])
	var style: Dictionary = PipeGenerator.LAYERS[4].duplicate()
	var layer := PipeGenerator.uniform_layer(grid, 1, 3, 12.0, style, Vector2(6.0, 0.0))
	var image := PipeGenerator.generate_image(24, 36, 1, Vector3(-0.62, -0.66, 0.42), 0.0, 0.0, Color.WHITE, [layer])
	assert_eq(image.get_size(), Vector2i(24, 36), "no overscan pad with a layout")
	assert_eq(image.get_pixel(12, 18).a8, 255, "the middle of the run is pipe")
	assert_eq(image.get_pixel(0, 18).a8, 0, "the far left is empty")
	assert_eq(image.get_pixel(23, 18).a8, 0, "the far right is empty")

func test_border_is_hollow_with_solid_edges() -> void:
	var gen := PipeGenerator.new()
	gen.seed = PipeGenerator.MENU_SEED
	var image := gen.make_border(Vector2i(120, 80), 20)
	assert_eq(image.get_size(), Vector2i(120, 80))

	var data := image.get_data()
	var middle := 0
	var edge := 0
	for y in 80:
		for x in 120:
			var a := data[(y * 120 + x) * 4 + 3]
			var inside := x >= 20 and x < 100 and y >= 20 and y < 60
			if inside and a > 0:
				middle += 1
			elif not inside and a > 0:
				edge += 1
	assert_eq(middle, 0, "the inside of the frame is clear")
	assert_gt(edge, 960, "the band carries pipes, a tenth of the area at least")

func test_default_strip_generates_inside_the_budget() -> void:
	var start := Time.get_ticks_usec()
	var image := PipeGenerator.generate_image(72, 270, 3)
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	assert_eq(image.get_size(), Vector2i(72, 270))
	assert_lt(ms, TIME_BUDGET_MS, "72x270 took %.1f ms" % ms)
	gut.p("72x270 strip generated in %.1f ms" % ms)

func straight_counts(flow: int) -> Vector2i:
	var horizontal := 0
	var vertical := 0
	for s in [1, 2, 3, 4]:
		var gen := PipeGenerator.new()
		gen.width = 64
		gen.height = 64
		gen.seed = s
		gen.flow = flow
		gen.generate()
		horizontal += gen.count_tiles(PipeGenerator.EAST | PipeGenerator.WEST)
		vertical += gen.count_tiles(PipeGenerator.NORTH | PipeGenerator.SOUTH)
	return Vector2i(horizontal, vertical)

func test_flow_turns_the_straight_runs() -> void:
	var h := straight_counts(PipeGenerator.Flow.HORIZONTAL)
	assert_gt(h.x, h.y * 2, "HORIZONTAL: %d east/west straights against %d north/south" % [h.x, h.y])
	var v := straight_counts(PipeGenerator.Flow.VERTICAL)
	assert_gt(v.y, v.x * 2, "VERTICAL: %d north/south straights against %d east/west" % [v.y, v.x])
	var same := PipeGenerator.generate_image(40, 40, 3, Vector3(-0.62, -0.66, 0.42), 0.25, 1.0, Color.WHITE, [], false,
		PipeGenerator.Flow.HORIZONTAL)
	var again := PipeGenerator.generate_image(40, 40, 3, Vector3(-0.62, -0.66, 0.42), 0.25, 1.0, Color.WHITE, [], false,
		PipeGenerator.Flow.HORIZONTAL)
	assert_eq(same.get_data(), again.get_data(), "flow is deterministic with the seed")

func test_fill_grid_keeps_painted_cells_and_connects_into_them() -> void:
	var gw := 8
	var gh := 8
	var grid := PackedByteArray()
	grid.resize(gw * gh)
	var painted := PipeGenerator.PAINTED
	grid[3 * gw + 2] = painted | PipeGenerator.EAST
	grid[3 * gw + 3] = painted | PipeGenerator.EAST | PipeGenerator.WEST
	grid[3 * gw + 4] = painted | PipeGenerator.WEST | PipeGenerator.SOUTH
	grid[4 * gw + 4] = painted | PipeGenerator.NORTH
	grid[6 * gw + 6] = painted
	var gen := PipeGenerator.new()
	gen.seed = 2
	var out := gen.fill_grid(grid, gw, gh, PipeGenerator.LAYERS[4])
	for i in gw * gh:
		if grid[i] & painted:
			assert_eq(out[i], grid[i], "painted cell %d kept as drawn" % i)

	var broken := 0
	for y in gh:
		for x in gw:
			var m := out[x + y * gw]
			for d in 4:
				if not (m & PipeGenerator.DIR_BIT[d]):
					continue
				var nx: int = x + PipeGenerator.DIR_X[d]
				var ny: int = y + PipeGenerator.DIR_Y[d]
				if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
					continue
				if not (out[nx + ny * gw] & PipeGenerator.DIR_OPP[d]):
					broken += 1
	assert_eq(broken, 0, "every open edge is answered by the neighbour")

# --- frame ---------------------------------------------------------------

func test_pipe_frame_generates_on_ready_and_on_change() -> void:
	var frame := PipeFrame.new()
	frame.mode = PipeFrame.Mode.PLATE
	frame.size = Vector2(32, 40)
	frame.seed = 3
	add_child_autofree(frame)
	assert_not_null(frame.texture, "generated in _ready")
	assert_eq(frame.texture.get_size(), Vector2(32, 40))
	var before := frame.texture.get_image().get_data()

	frame.seed = 4
	frame.size = Vector2(32, 48)
	assert_eq(frame.texture.get_size(), Vector2(32, 40), "regenerate waits for the deferred call")
	await get_tree().process_frame
	assert_eq(frame.texture.get_size(), Vector2(32, 48), "one regenerate after the frame")
	assert_ne(frame.texture.get_image().get_data(), before)

func test_zone_is_the_node_rect_and_divides_into_cells() -> void:
	var frame := PipeFrame.new()
	frame.mode = PipeFrame.Mode.PLATE
	frame.size = Vector2(40, 30)
	frame.cell_size = 12
	add_child_autofree(frame)
	assert_eq(frame.zone_size(), Vector2i(40, 30))
	assert_eq(frame.texture.get_size(), Vector2(40, 30), "the texture is the zone")
	assert_eq(frame.grid_size(), Vector2i(4, 3), "cells hang over the far edge")
	assert_eq(frame.cell_at(Vector2(13.0, 25.0)), Vector2i(1, 2))
	assert_eq(frame.cell_at(Vector2(41.0, 5.0)), Vector2i(-1, -1), "outside the zone")

	frame.size = Vector2(52, 30)
	await get_tree().process_frame
	assert_eq(frame.texture.get_size(), Vector2(52, 30), "resizing the rect regenerates")
	assert_eq(frame.grid_size(), Vector2i(5, 3))
	var layout := frame.ensure_layout()
	assert_eq(Vector2i(layout.width, layout.height), Vector2i(5, 3), "the layout follows the lattice")

func test_pipe_frame_border_matches_the_generator() -> void:
	var frame := PipeFrame.new()
	frame.size = Vector2(64, 48)
	frame.thickness = 12
	add_child_autofree(frame)
	var gen := frame.make_generator()
	var expected := gen.make_border(Vector2i(64, 48), 12)
	assert_eq(frame.texture.get_image().get_data(), expected.get_data())

func test_pipe_frame_does_not_store_its_texture() -> void:
	var frame := PipeFrame.new()
	frame.size = Vector2(16, 16)
	frame.thickness = 4
	add_child_autofree(frame)
	for property in frame.get_property_list():
		if property["name"] == "texture":
			assert_eq(property["usage"] & PROPERTY_USAGE_STORAGE, 0, "texture is rebuilt, not saved")

func test_manual_placement_renders_only_the_painted_cells() -> void:
	var frame := manual_frame(PipeFrame.LayoutMode.MANUAL, Vector2(48, 48), 12, 1)
	var layout := frame.layout
	assert_eq(Vector2i(layout.width, layout.height), Vector2i(4, 4))
	paint_run(layout, 1, [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)])
	assert_eq(layout.get_cell(1, 1, 1), PipeLayout.PAINTED | PipeGenerator.EAST | PipeGenerator.WEST, "a stroke links along")
	assert_eq(layout.get_cell(1, 0, 1), PipeLayout.PAINTED | PipeGenerator.EAST, "the first cell is a dead end")
	add_child_autofree(frame)

	var image := frame.texture.get_image()
	assert_eq(image.get_size(), Vector2i(48, 48))
	for x in 4:
		assert_eq(image.get_pixel(x * 12 + 6, 18).a8, 255, "painted cell %d carries pipe" % x)
		assert_eq(image.get_pixel(x * 12 + 6, 6).a8, 0, "row 0 unpainted")
		assert_eq(image.get_pixel(x * 12 + 6, 42).a8, 0, "row 3 unpainted")

	# the back layer is untouched, nothing extra appears
	var gen := frame.make_generator()
	gen.width = 48
	gen.height = 48
	gen.layout = frame.layout_layers(false)
	gen.generate()
	assert_eq(gen.count_tiles(0), 4 * 4 * 2 - 4, "only the four painted cells hold tiles")

func test_lone_painted_cell_renders_a_node() -> void:
	var frame := manual_frame(PipeFrame.LayoutMode.MANUAL, Vector2(36, 36), 12, 1)
	frame.layout.paint(0, 1, 1)
	assert_eq(frame.layout.get_cell(0, 1, 1), PipeLayout.PAINTED, "no neighbours, no connections")
	add_child_autofree(frame)
	assert_eq(frame.texture.get_image().get_pixel(18, 18).a8, 255, "the lone node is drawn at the cell centre")
	assert_eq(frame.texture.get_image().get_pixel(6, 6).a8, 0)

func test_mixed_placement_keeps_painted_cells_and_fills_the_rest() -> void:
	var frame := manual_frame(PipeFrame.LayoutMode.MIXED, Vector2(120, 120), 12, 3)
	var layout := frame.layout
	var run: Array = []
	for x in range(2, 8):
		run.append(Vector2i(x, 4))
	paint_run(layout, 1, run)
	add_child_autofree(frame)

	var gen := frame.make_generator()
	gen.width = 120
	gen.height = 120
	gen.layout = frame.layout_layers(true)
	gen.generate()
	var front: PackedByteArray = gen.last_layers[1]["grid"]
	for x in range(2, 8):
		assert_eq(front[4 * 10 + x], layout.get_cell(1, x, 4), "painted cell %d,4 kept" % x)

	var filled := 0
	for m in front:
		if m != 0 and not (m & PipeLayout.PAINTED):
			filled += 1
	assert_gt(filled, 0, "WFC filled free cells around the drawing")
	assert_gt(gen.count_tiles(0), 0, "and left some empty")

	var image := frame.texture.get_image()
	for x in range(2, 8):
		assert_eq(image.get_pixel(x * 12 + 6, 4 * 12 + 6).a8, 255, "painted cell %d,4 is pipe in the picture" % x)

func test_auto_fill_bakes_wfc_cells_into_the_layout() -> void:
	var frame := manual_frame(PipeFrame.LayoutMode.MANUAL, Vector2(96, 96), 12, 7)
	var layout := frame.layout
	paint_run(layout, 0, [Vector2i(1, 1), Vector2i(2, 1)])
	add_child_autofree(frame)
	var before := layout.painted_count(0)
	frame.auto_fill(0)
	assert_gt(layout.painted_count(0), before, "fill painted more cells")
	assert_eq(layout.get_cell(0, 1, 1), PipeLayout.PAINTED | PipeGenerator.EAST, "the drawn cells stay")
	assert_eq(layout.painted_count(1), 0, "the other layer is untouched")

func test_pipe_layout_paint_links_toggle_flips_and_erase_unlinks() -> void:
	var layout := PipeLayout.new()
	layout.resize(3, 1)
	layout.paint(0, 0, 0)
	layout.paint(0, 1, 0)
	assert_eq(layout.get_cell(0, 0, 0), PipeLayout.PAINTED | PipeGenerator.EAST, "a click beside a pipe joins it")
	assert_eq(layout.get_cell(0, 1, 0), PipeLayout.PAINTED | PipeGenerator.WEST)

	layout.toggle_edge(0, Vector2i(1, 0), Vector2i(2, 0))
	assert_eq(layout.get_cell(0, 2, 0), PipeLayout.PAINTED | PipeGenerator.WEST, "toggle opens a closed edge and paints")
	layout.toggle_edge(0, Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(layout.get_cell(0, 0, 0), PipeLayout.PAINTED, "toggle closes an open edge, the cell stays")
	assert_eq(layout.get_cell(0, 1, 0), PipeLayout.PAINTED | PipeGenerator.EAST)

	layout.set_gauge(0, 2, 0, 6.0)
	assert_eq(layout.get_gauge(0, 2, 0), 6.0)
	layout.erase(0, 2, 0)
	assert_eq(layout.get_cell(0, 2, 0), 0)
	assert_eq(layout.get_gauge(0, 2, 0), 0.0)
	assert_eq(layout.get_cell(0, 1, 0), PipeLayout.PAINTED, "erase closes the neighbour's edge")

	layout.resize(4, 2)
	assert_eq(layout.get_cell(0, 1, 0), PipeLayout.PAINTED, "resize keeps the cells")
	assert_eq(layout.grid.size(), 4 * 2 * 2)

func test_pipe_layout_roundtrips_through_a_saved_scene() -> void:
	var frame := manual_frame(PipeFrame.LayoutMode.MANUAL, Vector2(48, 36), 12, 9)
	frame.name = "Frame"
	var layout := frame.layout
	paint_run(layout, 1, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)])
	layout.paint(0, 3, 2)
	layout.set_gauge(1, 1, 1, 6.5)

	var packed := PackedScene.new()
	assert_eq(packed.pack(frame), OK)
	assert_eq(ResourceSaver.save(packed, ROUNDTRIP_PATH), OK)
	frame.free()

	var loaded: PackedScene = ResourceLoader.load(ROUNDTRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(loaded)
	var copy := loaded.instantiate() as PipeFrame
	assert_not_null(copy, "the scene root is a PipeFrame")
	add_child_autofree(copy)
	assert_eq(copy.placement, PipeFrame.LayoutMode.MANUAL)
	assert_eq(copy.cell_size, 12)
	assert_not_null(copy.layout, "the layout came back as a sub resource")
	assert_eq(Vector2i(copy.layout.width, copy.layout.height), Vector2i(4, 3))
	assert_eq(copy.layout.grid, layout.grid, "every cell byte survived")
	assert_eq(copy.layout.sizes, layout.sizes, "the gauge survived")
	assert_eq(copy.texture.get_image().get_pixel(18, 18).a8, 255, "and it renders the same pipe")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUNDTRIP_PATH))

func test_demo_scene_has_manual_and_mixed_zones() -> void:
	var scene: PackedScene = load("res://game/editors/PipeFrameDemo.tscn")
	assert_not_null(scene)
	var root := scene.instantiate()
	add_child_autofree(root)
	var manual: PipeFrame = root.get_node("ManualZone")
	assert_eq(manual.placement, PipeFrame.LayoutMode.MANUAL)
	assert_eq(manual.layout.painted_count(), 19, "the demo layout's hand cells")
	assert_eq(manual.texture.get_size(), Vector2(120, 72))
	assert_eq(manual.texture.get_image().get_pixel(4 * 12 + 6, 2 * 12 + 6).a8 > 0, true, "the branch tee is pipe")
	var mixed: PipeFrame = root.get_node("MixedZone")
	assert_eq(mixed.placement, PipeFrame.LayoutMode.MIXED)
	assert_eq(mixed.flow, PipeGenerator.Flow.HORIZONTAL)
	assert_eq(Vector2i(mixed.layout.width, mixed.layout.height), mixed.grid_size(), "the mixed layout fits its zone")

# --- editor plugin --------------------------------------------------------------

func test_pipes_plugin_script_parses_and_toolbar_instantiates() -> void:
	var plugin_script: GDScript = load("res://addons/regolith_pipes/RegolithPipesPlugin.gd")
	assert_not_null(plugin_script)
	assert_true(plugin_script.can_instantiate(), "the plugin compiles")

	var toolbar_script: GDScript = load("res://addons/regolith_pipes/PipeToolbar.gd")
	assert_true(toolbar_script.can_instantiate(), "the toolbar compiles")
	var toolbar: Control = toolbar_script.new()
	add_child_autofree(toolbar)
	assert_eq(toolbar.tool_buttons.size(), 4, "Select, Pipe, Erase, Gauge")
	assert_eq(toolbar.layer_pick.item_count, 2, "back and front")
	assert_eq(toolbar.layer, 1, "the front layer is edited first")
	toolbar.set_tool(1)
	assert_eq(toolbar.tool, 1)
	assert_true(toolbar.tool_buttons[1].button_pressed)

	var frame := manual_frame(PipeFrame.LayoutMode.MIXED, Vector2(24, 24), 12, 1)
	add_child_autofree(frame)
	toolbar.show_frame(frame)
	assert_true(toolbar.status.text.contains("Mixed"), toolbar.status.text)
	assert_true(toolbar.status.text.contains("2x2"), toolbar.status.text)
