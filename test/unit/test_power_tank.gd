extends GutTest

# PowerTank: the mask sorts inlets, outlets and barriers, queued cells drop
# in and fall, the open outlet drains them for power, a hit bounces them up

const MASK := preload("res://game/images/ui/power_tank_mask.png")

var tank: PowerTank

func before_each() -> void:
	tank = PowerTank.new()
	tank.mask = MASK
	tank.update_rate = 0.001
	add_child_autofree(tank)

func test_mask_builds_inlets_outlets_and_barriers() -> void:
	assert_eq(tank.width, MASK.get_width())
	assert_eq(tank.height, MASK.get_height())
	assert_gt(tank.inlet.size(), 0, "blue pixels are inlets")
	assert_gt(tank.outlet.size(), 0, "red pixels are outlets")

	var barriers := 0
	for c in tank.cells_write:
		if c.is_static:
			barriers += 1
	assert_gt(barriers, 0, "the frame is static")
	assert_eq(tank.filled_count(), 0)

func test_queued_cells_drop_in_and_fall() -> void:
	tank.queue_cells(5, Color8(200, 50, 50, 200))
	assert_eq(tank.feed_color, Color8(200, 50, 50, 200))

	for i in 5:
		tank.update()

	assert_eq(tank.cells_queued, 0, "one cell per update comes in")
	assert_eq(tank.filled_count(), 5)

	var top := INF
	for y in tank.height:
		for x in tank.width:
			var c := tank.cells_write[tank.index(x, y)]
			if c.color.a > 0.0 and not c.is_static:
				top = minf(top, y)

	for i in 60:
		tank.update()

	var lowest := -INF
	for y in tank.height:
		for x in tank.width:
			var c := tank.cells_write[tank.index(x, y)]
			if c.color.a > 0.0 and not c.is_static:
				lowest = maxf(lowest, y)

	assert_eq(tank.filled_count(), 5, "no cell lost while falling")
	assert_gt(lowest, top, "sand fell down the tank")

func test_open_outlet_drains_cells_for_power() -> void:
	tank.queue_cells(20)

	for i in 200:
		tank.update()

	var drained := {"power": 0.0}
	tank.power_drained.connect(func(amount): drained["power"] += amount)
	tank.open_outlet = true

	for i in 400:
		tank.update()

	assert_gt(drained["power"], 0.0, "cells at the outlet became power")
	assert_lt(tank.filled_count(), 20, "drained cells left the tank")

func test_bounce_lifts_sand_for_a_moment() -> void:
	tank.queue_cells(4)

	for i in 120:
		tank.update()

	var before := 0.0
	for y in tank.height:
		for x in tank.width:
			var c := tank.cells_write[tank.index(x, y)]
			if c.color.a > 0.0 and not c.is_static:
				before += y

	tank.bounce()
	assert_gt(tank.bounce_timer, 0.0)

	for i in 30:
		tank.update()

	var after := 0.0
	for y in tank.height:
		for x in tank.width:
			var c := tank.cells_write[tank.index(x, y)]
			if c.color.a > 0.0 and not c.is_static:
				after += y

	assert_lt(after, before, "sand rose while bouncing")
