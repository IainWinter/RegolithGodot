extends GutTest

# AsteroidGenerator wraps RockGenerator (the albedo and mask port) and adds
# the normal map the C++ generator also wrote: same size, solid exactly where
# the colour is, facing the viewer in the middle, deterministic per seed

const PROPS := preload("res://game/config/rocks/default_rock.tres")

func test_normal_map_matches_the_colour_silhouette() -> void:
	var images := AsteroidGenerator.generate(5, Vector2i(64, 64), PROPS)
	var color: Image = images["color"]
	var normal: Image = images["normal"]
	assert_eq(normal.get_size(), Vector2i(64, 64))
	assert_eq(images["mask"].get_size(), Vector2i(64, 64), "the RockGenerator outputs still come back")

	var dc := color.get_data()
	var dn := normal.get_data()
	var mismatches := 0
	for i in 64 * 64:
		if (dc[i * 4 + 3] == 255) != (dn[i * 4 + 3] == 255):
			mismatches += 1
	assert_eq(mismatches, 0, "normal alpha follows the colour alpha")

	var middle := normal.get_pixel(32, 32)
	assert_gt(middle.b8, 200, "the dome faces the viewer in the middle")
	assert_between(middle.r8, 90, 165, "no sideways lean in the middle")
	assert_between(middle.g8, 90, 165, "no sideways lean in the middle")

func test_normal_map_is_deterministic_for_a_seed() -> void:
	var a := AsteroidGenerator.generate(11, Vector2i(32, 32), PROPS)
	var b := AsteroidGenerator.generate(11, Vector2i(32, 32), PROPS)
	var c := AsteroidGenerator.generate(12, Vector2i(32, 32), PROPS)
	assert_eq(a["normal"].get_data(), b["normal"].get_data())
	assert_ne(a["normal"].get_data(), c["normal"].get_data())

func test_edges_of_the_dome_lean_outward() -> void:
	var images := AsteroidGenerator.generate(3, Vector2i(64, 64), PROPS)
	var normal: Image = images["normal"]
	var color: Image = images["color"]
	var left_x := -1
	for x in 32:
		if color.get_pixel(x, 32).a8 == 255:
			left_x = x
			break
	assert_gt(left_x, -1, "the disc reaches the middle row")
	var edge := normal.get_pixel(left_x + 1, 32)
	assert_lt(edge.r8, 120, "the left rim leans left (x below half)")

func test_generation_fits_the_budget() -> void:
	var start := Time.get_ticks_usec()
	AsteroidGenerator.generate(7, Vector2i(96, 96), PROPS)
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	assert_lt(ms, 1000.0, "96x96 rock with normals took %.1f ms" % ms)
