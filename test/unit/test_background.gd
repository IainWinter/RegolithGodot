extends GutTest

# the background is a camera following field: depth layers of stars, dust
# washes and near clouds in parallax order, items placed by density per
# unit area in a padded window around the camera's view of each layer,
# spawned and freed as the camera moves, the same sky when scrolling back,
# and the view stays covered through zoom changes. an item is uploaded by
# its own bounds, not its cell, so nothing that touches the view can pop,
# the multimesh buffer is never empty or half written while items show,
# and every multimesh carries a cull rect over its window

const STAR := preload("res://game/images/background/star.png")
const DUST := preload("res://game/images/background/smoke1.png")

var arena: Node2D
var camera: Camera2D
var background: Background

func before_each() -> void:
	arena = Node2D.new()
	add_child_autofree(arena)

	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	arena.add_child(camera)
	camera.make_current()

	background = Background.new()
	background.star_texture = STAR
	background.dust_texture = DUST
	background.density = 3.0
	arena.add_child(background)
	await wait_physics_frames(2)

func view_area_units() -> float:
	var ppu := RegolithWorld.pixels_per_unit()
	var size := background.view_extents * 2.0 / ppu
	return size.x * size.y

func kind_count_in_view(kind: String) -> int:
	var total := 0

	for layer in background.layers_of(kind):
		total += layer.items_in_rect(layer.view).size()

	return total

# the count over every layer of a kind inside its padded view, the biggest
# rect the generated cells are guaranteed to cover, against density times
# that area
func assert_kind_density(kind: String, field_density: float) -> void:
	var ppu := RegolithWorld.pixels_per_unit()
	var count := 0
	var expected := 0.0

	for layer in background.layers_of(kind):
		var probe: Rect2 = layer.padded_view()
		count += layer.items_in_rect(probe).size()
		expected += background.density * field_density / background.layers_of(kind).size() * probe.get_area() / (ppu * ppu)

	assert_almost_eq(float(count), expected, expected * 0.2, "%s in the padded view: %d for %.1f expected" % [kind, count, expected])

func assert_view_covered() -> void:
	for layer in background.layers:
		var wanted: Rect2i = layer.cell_range(layer.padded_view())
		assert_true(layer.window.encloses(wanted), "%s window covers the padded view" % layer.instance.name)

		for key in layer.cells:
			assert_true(layer.window.has_point(key), "%s keeps no cell outside its window" % layer.instance.name)

# the buffer is a capacity that only grows, the live items fill its front
# and visible_instance_count is the drawn count, so instance_count is at
# least the item count rather than equal to it (changed with the flicker
# fix: resizing the buffer to the exact count zeroes it before it is refilled)
func assert_buffer_follows(layer: Background.FieldLayer, label: String) -> void:
	var multimesh: MultiMesh = layer.instance.multimesh
	assert_eq(multimesh.visible_instance_count, layer.item_count(), "%s draws every item %s" % [layer.instance.name, label])
	assert_gte(multimesh.instance_count, layer.item_count(), "%s buffer holds every item %s" % [layer.instance.name, label])

	if layer.item_count() > 0:
		assert_gt(multimesh.instance_count, 0, "%s buffer is not empty while items show %s" % [layer.instance.name, label])

func assert_custom_aabb_covers_padded_view(label: String) -> void:
	for layer in background.layers:
		var aabb: AABB = layer.instance.multimesh.custom_aabb
		var rect := Rect2(aabb.position.x, aabb.position.y, aabb.size.x, aabb.size.y)
		assert_ne(aabb, AABB(), "%s has a custom aabb %s" % [layer.instance.name, label])
		assert_true(rect.encloses(layer.padded_view()), "%s custom aabb %s covers the padded view %s %s" % [layer.instance.name, rect, layer.padded_view(), label])

# ids of the generated items whose bounds touch a layer space rect
func items_touching(layer: Background.FieldLayer, rect: Rect2) -> Dictionary:
	var found := {}

	for key in layer.cells:
		var items: Array = layer.cells[key]

		for i in items.size():
			if layer.item_aabb(items[i]).intersects(rect):
				found[Vector3i(key.x, key.y, i)] = items[i]

	return found

func test_layers_exist_in_parallax_order() -> void:
	assert_eq(background.layers.size(), background.star_layers + background.dust_layers + background.cloud_layers)
	assert_eq(background.get_child_count(), background.layers.size(), "one multimesh per layer")

	for layer in background.layers:
		assert_true(layer.instance is MultiMeshInstance2D)
		assert_buffer_follows(layer, "at rest")

	for kind in ["Dust", "Star", "Cloud"]:
		var of_kind := background.layers_of(kind)
		assert_gt(of_kind.size(), 0, "%s layers exist" % kind)

		for i in range(1, of_kind.size()):
			assert_lt(of_kind[i].parallax, of_kind[i - 1].parallax, "%s deeper layers slide less" % kind)

	var dust_max := 0.0
	var star_min := INF

	for layer in background.layers_of("Dust"):
		dust_max = maxf(dust_max, layer.parallax)

	for layer in background.layers_of("Star"):
		star_min = minf(star_min, layer.parallax)

	assert_gt(star_min, dust_max, "stars slide with the camera more than the dust, like the original")
	assert_almost_eq(background.layers_of("Star")[0].parallax, 2.0 / (3.0 + 0.5 / background.star_layers * 10.0), 0.0001)
	assert_almost_eq(background.layers_of("Dust")[0].parallax, 0.5 / (4.0 + 0.5 / background.dust_layers * 10.0), 0.0001)

func test_density_matches_area() -> void:
	assert_kind_density("Star", background.star_density)
	assert_kind_density("Dust", background.dust_density)
	assert_kind_density("Cloud", background.cloud_density)
	assert_view_covered()

func test_moving_two_screens_spawns_ahead_and_frees_behind() -> void:
	var before_keys := {}
	var before_counts := {}

	for layer in background.layers:
		before_keys[layer] = layer.cells.keys()
		before_counts[layer] = layer.item_count()

	camera.global_position += Vector2(background.view_extents.x * 4.0, 0.0)
	await wait_physics_frames(2)
	assert_almost_eq(background.view_center, camera.global_position, Vector2.ONE, "the field saw the camera move")

	for layer in background.layers:
		var name: String = layer.instance.name
		var spawned := 0
		var kept := 0

		for key in layer.cells:
			if key in before_keys[layer]:
				kept += 1
			else:
				spawned += 1

		var freed: int = before_keys[layer].size() - kept
		assert_gt(spawned, 0, "%s spawned cells ahead" % name)
		assert_gt(freed, 0, "%s freed cells behind" % name)
		assert_almost_eq(float(layer.item_count()), float(before_counts[layer]), before_counts[layer] * 0.35 + 2.0, "%s count stays bounded" % name)
		assert_buffer_follows(layer, "after the move")

	assert_view_covered()
	assert_kind_density("Star", background.star_density)

func test_scrolling_back_reproduces_the_same_sky() -> void:
	var snapshots := {}

	for layer in background.layers:
		snapshots[layer] = layer.items_in_rect(layer.view)
		assert_gt(snapshots[layer].size(), 0, "%s has items in view" % layer.instance.name)

	var start := camera.global_position
	camera.global_position = start + Vector2(background.view_extents.x * 6.0, background.view_extents.y * 6.0)
	await wait_physics_frames(2)

	for layer in background.layers:
		assert_ne(layer.items_in_rect(layer.view), snapshots[layer], "%s shows a different sky far away" % layer.instance.name)

	camera.global_position = start
	await wait_physics_frames(2)

	for layer in background.layers:
		assert_eq(layer.items_in_rect(layer.view), snapshots[layer], "%s shows the same sky again" % layer.instance.name)

func test_zoom_change_keeps_the_view_covered() -> void:
	var at_default := kind_count_in_view("Star")

	camera.zoom = Vector2(0.5, 0.5)
	await wait_physics_frames(2)
	assert_view_covered()
	assert_kind_density("Star", background.star_density)
	assert_kind_density("Dust", background.dust_density)
	var zoomed_out := kind_count_in_view("Star")
	assert_gt(zoomed_out, at_default * 3, "zooming out to four times the area shows many more stars")

	camera.zoom = Vector2(2.0, 2.0)
	await wait_physics_frames(2)
	assert_view_covered()
	assert_lt(kind_count_in_view("Star"), at_default, "zooming in shows fewer stars")

	for layer in background.layers:
		assert_lt(layer.item_count(), int(layer.cell_range(layer.padded_view()).get_area()) * int(ceil(layer.density * layer.cell_size * layer.cell_size)) + 1, "%s dropped the cells it no longer needs" % layer.instance.name)

# walks a star cell across and half a cell up per frame over four screens.
# in every frame each item whose bounds touch the view is uploaded, an item
# uploaded last frame that still touches the view is still uploaded, and an
# item that appears was outside the view last frame, so nothing pops in or
# out where it shows. items are tracked by their cell and index id
func test_walking_a_cell_per_frame_never_pops_an_item_in_view() -> void:
	var ppu := RegolithWorld.pixels_per_unit()
	var step := Vector2(8.0 * ppu, 4.0 * ppu)
	var steps := int(ceil(background.view_extents.x * 8.0 / step.x))
	var previous := {}
	var entered := {}
	var shown := {}

	for layer in background.layers:
		entered[layer] = 0
		shown[layer] = 0

	for n in steps + 1:
		if n > 0:
			camera.global_position += step
			await wait_physics_frames(1)

		for layer in background.layers:
			var name: String = layer.instance.name
			var live: Dictionary = layer.live
			var view: Rect2 = layer.view
			var hits := items_touching(layer, view)
			var missing := []
			var vanished := []
			var popped := []
			shown[layer] += hits.size()

			for id in hits:
				if not live.has(id):
					missing.append(id)

			if previous.has(layer):
				var last: Dictionary = previous[layer]

				for id in last["live"]:
					if hits.has(id) and not live.has(id):
						vanished.append(id)

				for id in live:
					if not last["live"].has(id):
						entered[layer] += 1

						if layer.item_aabb(live[id]).intersects(last["view"]):
							popped.append(id)

			assert_eq(missing.size(), 0, "%s step %d: items touching the view are uploaded, missing %s" % [name, n, missing.slice(0, 5)])
			assert_eq(vanished.size(), 0, "%s step %d: items still touching the view stay uploaded, vanished %s" % [name, n, vanished.slice(0, 5)])
			assert_eq(popped.size(), 0, "%s step %d: new items were outside the view last frame, popped %s" % [name, n, popped.slice(0, 5)])
			assert_buffer_follows(layer, "at step %d" % n)
			previous[layer] = {"live": live, "view": view}

	assert_almost_eq(background.view_center, camera.global_position, Vector2.ONE, "the field followed the walk")

	for layer in background.layers:
		assert_gt(entered[layer], 0, "%s had items enter over the walk" % layer.instance.name)
		assert_gt(shown[layer], 0, "%s had items in view over the walk" % layer.instance.name)

func test_every_multimesh_has_a_custom_aabb_over_its_window() -> void:
	assert_custom_aabb_covers_padded_view("at rest")

	camera.global_position += Vector2(background.view_extents.x * 3.0, -background.view_extents.y * 3.0)
	await wait_physics_frames(2)
	assert_custom_aabb_covers_padded_view("after a move")

	camera.zoom = Vector2(0.5, 0.5)
	await wait_physics_frames(2)
	assert_custom_aabb_covers_padded_view("zoomed out")

func test_drift_layers_keep_their_items_while_drifting() -> void:
	var before := {}
	var uploads := {}

	for layer in background.layers:
		before[layer] = layer.live_ids.duplicate()
		uploads[layer] = layer.upload_count

	var frames := Engine.get_process_frames()
	await wait_physics_frames(10)
	var passed := Engine.get_process_frames() - frames
	assert_gt(passed, 0, "process frames ran")

	for layer in background.layers:
		var name: String = layer.instance.name
		var count: int = layer.upload_count - uploads[layer]
		assert_eq(layer.live_ids, before[layer], "%s keeps the same items while the camera rests" % name)
		assert_lte(count, passed, "%s uploads at most once per frame" % name)

		if layer.drifts:
			assert_gt(count, 0, "%s re-uploads as it drifts" % name)
		else:
			assert_eq(count, 0, "%s does not re-upload while nothing changed" % name)

func test_extra_refreshes_fold_into_one_upload_per_frame() -> void:
	var layer := background.layers_of("Cloud")[0]
	var uploads := layer.upload_count
	var frames := Engine.get_process_frames()

	background.refresh()
	background.refresh()
	background.refresh()
	await wait_physics_frames(6)

	var passed := Engine.get_process_frames() - frames
	var count := layer.upload_count - uploads
	assert_gt(count, 0, "the drifting layer uploaded")
	assert_lte(count, passed + 1, "one upload per process frame at most, %d over %d frames" % [count, passed])

func test_layers_are_not_physics_interpolated() -> void:
	assert_eq(background.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF, "the field is placed in _process, so it opts out of interpolation")

	for layer in background.layers:
		assert_false(layer.instance.is_physics_interpolated(), "%s is not interpolated between physics ticks" % layer.instance.name)
