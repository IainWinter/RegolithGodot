extends GutTest

# the bullet bore: a shot through a filled block carves along its true line
# (a 45 and a 20 degree tunnel span both axes in proportion, no cardinal
# staircase), the per cell turn bends a tunnel visibly, the minigun eats
# three cells, the cannon speed matches its resource

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const BULLET_SCENE := preload("res://game/scenes/weapons/Bullet.tscn")

var arena: Node2D
var world: RegolithWorld
var ppu := 0.0

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)
	await wait_physics_frames(1)
	ppu = RegolithWorld.pixels_per_unit()

func after_each() -> void:
	arena.free()

# a static filled block of cells, two chunks square by default
func add_block(cells := Vector2i(64, 64)) -> RegolithSprite:
	var block := RegolithSprite.new()
	block.dynamic = false
	arena.add_child(block)
	block.create_blank(cells)
	block.fill_rect(Rect2i(Vector2i.ZERO, cells), Color.WHITE, RegolithSprite.CELL_FILLED, 0)
	return block

func straight_props(life: int) -> WeaponProps:
	var props := WeaponProps.new()
	props.speed = 16.0
	props.lifetime = 5.0
	props.cell_life = life
	props.rotation_factor = 0.0
	props.spit_odds = 0.0
	props.damage_ratio = 0.0
	return props

# fires a bullet from a grid point of the block along a grid space angle and
# runs it until it dies, returning the cells it ate in order
func bore(block: RegolithSprite, props: WeaponProps, start_grid: Vector2, degrees: float, bias := 0.0) -> Dictionary:
	var grid_dir := Vector2.from_angle(deg_to_rad(degrees))
	var start := block.grid_point_to_world(start_grid)
	var direction := (block.grid_point_to_world(start_grid + grid_dir) - start).normalized()
	var bullet: Bullet = BULLET_SCENE.instantiate()
	bullet.setup(props, start, direction, Vector2.ZERO, null)
	bullet.rotation_bias = bias
	var cells: Array[Vector2i] = []
	bullet.hit_cell.connect(func(_sprite, cell: Vector2i, _position): cells.append(cell))
	arena.add_child(bullet)

	for i in 300:
		if not is_instance_valid(bullet) or bullet.dead:
			break
		await wait_physics_frames(1)

	var exit_direction := bullet.velocity.normalized() if is_instance_valid(bullet) else Vector2.ZERO
	return {"cells": cells, "grid_dir": grid_dir, "exit": exit_direction, "entry": direction}

func perpendicular_distance(cell: Vector2i, start_grid: Vector2, grid_dir: Vector2) -> float:
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	return absf(grid_dir.cross(center - start_grid))

func span(cells: Array[Vector2i]) -> Dictionary:
	var columns := {}
	var rows := {}
	var per_row := {}
	for cell in cells:
		columns[cell.x] = true
		rows[cell.y] = true
		per_row[cell.y] = per_row.get(cell.y, 0) + 1
	var longest_row := 0
	for count in per_row.values():
		longest_row = maxi(longest_row, count)
	return {"columns": columns.size(), "rows": rows.size(), "longest_row": longest_row}

func test_cannon_speed_matches_tres_and_aim_assist_reaches_the_screen() -> void:
	var props: WeaponProps = load("res://game/config/weapons/default_cannon.tres")
	assert_eq(props.speed, 11.5, "every bullet flies at half speed, the main gun from 23")
	var bullet: Bullet = BULLET_SCENE.instantiate()
	var flat: WeaponProps = props.duplicate()
	flat.speed_random = 0.0
	bullet.setup(flat, Vector2.ZERO, Vector2.RIGHT, Vector2.ZERO, null)
	assert_almost_eq(bullet.velocity.length(), 11.5, 0.001, "bullet speed comes from the resource")
	bullet.free()
	var range := minf(props.speed * props.lifetime, AimAssist.MAX_RANGE) * ppu
	assert_gt(range, Vector2(1152.0, 648.0).length() * 0.5, "aim assist still reaches the screen corner")

func test_minigun_eats_three_cells() -> void:
	var props: WeaponProps = load("res://game/config/weapons/minigun.tres").duplicate()
	assert_eq(props.cell_life, 3)
	props.spit_odds = 0.0
	props.speed_random = 0.0
	var block := add_block()
	await wait_physics_frames(2)
	var before := block.get_active_cell_count()

	var result := await bore(block, props, Vector2(-4.0, 32.5), 0.0)
	var cells: Array[Vector2i] = result["cells"]

	assert_eq(cells.size(), 3, "one minigun bullet burns three cells then dies")
	assert_gte(before - block.get_active_cell_count(), 3, "the block lost them")

func test_diagonal_bore_carves_along_the_true_line() -> void:
	var block := add_block()
	await wait_physics_frames(2)
	var start := Vector2(-4.0, 20.3)

	var result := await bore(block, straight_props(30), start, 45.0)
	var cells: Array[Vector2i] = result["cells"]
	var s := span(cells)

	assert_eq(cells.size(), 30, "ate its whole cell life")
	assert_gte(s["columns"], 12, "a 45 degree tunnel spans columns")
	assert_gte(s["rows"], 12, "and rows in equal measure")
	assert_lte(s["longest_row"], 3, "no long cardinal runs")
	for cell in cells:
		assert_lt(perpendicular_distance(cell, start, result["grid_dir"]), 0.8, "cell %s sits on the line" % cell)

func test_shallow_bore_keeps_its_angle() -> void:
	var block := add_block()
	await wait_physics_frames(2)
	var start := Vector2(-4.0, 16.3)

	var result := await bore(block, straight_props(30), start, 20.0)
	var cells: Array[Vector2i] = result["cells"]
	var s := span(cells)

	assert_eq(cells.size(), 30, "ate its whole cell life")
	# a 20 degree line over 30 cells climbs about 8 rows across 22 columns
	assert_gte(s["columns"], 18, "a shallow tunnel runs mostly along x")
	assert_gte(s["rows"], 6, "but still climbs row by row, not one flat row")
	assert_lte(s["longest_row"], 5, "each row run is a few cells, no single flat row")
	for cell in cells:
		assert_lt(perpendicular_distance(cell, start, result["grid_dir"]), 0.8, "cell %s sits on the line" % cell)

func test_steep_bore_keeps_its_angle_the_other_way() -> void:
	var block := add_block()
	await wait_physics_frames(2)
	var start := Vector2(-4.0, 10.3)

	var result := await bore(block, straight_props(30), start, 70.0)
	var cells: Array[Vector2i] = result["cells"]
	var s := span(cells)

	assert_eq(cells.size(), 30)
	assert_gte(s["rows"], 18, "a steep tunnel runs mostly along y")
	assert_gte(s["columns"], 6, "and still steps across columns")

# the original turn is strong: at 60 Hz a bias of 0.5 turns the first cell
# by 100 * 0.5 / 60 = 0.83 rad, so the shot starts inside a big block and
# curls there instead of hooking straight back out of the entry face
func test_rotation_factor_bends_the_tunnel() -> void:
	var block := add_block(Vector2i(128, 128))
	await wait_physics_frames(2)
	var props := straight_props(20)
	props.rotation_factor = 100.0
	var start := Vector2(4.5, 64.5)

	var result := await bore(block, props, start, 0.0, 0.5)
	var cells: Array[Vector2i] = result["cells"]

	assert_eq(cells.size(), 20, "the whole curl stays inside the block")
	var deviation := 0.0
	for cell in cells:
		deviation = maxf(deviation, perpendicular_distance(cell, start, result["grid_dir"]))
	assert_gt(deviation, 1.0, "the tunnel leaves the straight line by more than a cell")
	var entry: Vector2 = result["entry"]
	var exit: Vector2 = result["exit"]
	assert_gt(absf(entry.angle_to(exit)), 0.3, "it leaves at a different angle than it entered")

func test_no_rotation_keeps_the_tunnel_straight() -> void:
	var block := add_block(Vector2i(96, 64))
	await wait_physics_frames(2)
	var start := Vector2(-4.0, 32.5)

	var result := await bore(block, straight_props(20), start, 0.0, 0.5)
	var cells: Array[Vector2i] = result["cells"]

	assert_eq(cells.size(), 20)
	assert_eq(span(cells)["rows"], 1, "a flat shot with no turn stays in its row")
	assert_true(result["entry"].is_equal_approx(result["exit"]), "and leaves as it entered")
