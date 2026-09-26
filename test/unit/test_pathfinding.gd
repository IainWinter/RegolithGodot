extends GutTest

# world queries ported from SpriteRaycast and SpritePathfinding: rays walk
# the tree along the segment and can pass groups, paths go around walls,
# and a repairable sprite that loses every cell stays as an empty node

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var arena: Node2D
var world: RegolithWorld
var wall: RegolithSprite

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)

	wall = RegolithSprite.new()
	wall.dynamic = false
	wall.position = Vector2(200.0, 0.0)
	wall.add_to_group("wall")
	arena.add_child(wall)
	wall.create_blank(Vector2i(32, 96))
	wall.fill_rect(Rect2i(0, 0, 32, 96), Color.GRAY, RegolithSprite.CELL_FILLED, 0)
	await wait_physics_frames(2)

func after_each() -> void:
	arena.free()

func test_ray_cast_hits_wall_and_reports_local_point() -> void:
	var hit: Dictionary = world.ray_cast(Vector2(0.0, 0.0), Vector2(400.0, 0.0))
	assert_false(hit.is_empty(), "ray hits the wall")
	assert_eq(hit["sprite"], wall)
	assert_true(hit.has("local_position"))
	assert_lt(absf(hit["position"].x - 168.0), 4.0, "hit on the near face of the wall")
	assert_lt(hit["distance"], 200.0)

func test_ray_cast_passes_ignored_groups() -> void:
	var hit: Dictionary = world.ray_cast(Vector2(0.0, 0.0), Vector2(400.0, 0.0), null, PackedStringArray(["wall"]))
	assert_true(hit.is_empty(), "wall group is ignored")
	assert_false(world.has_line_of_sight(Vector2(0.0, 0.0), Vector2(400.0, 0.0)))
	assert_true(world.has_line_of_sight(Vector2(0.0, 0.0), Vector2(400.0, 0.0), null, PackedStringArray(["wall"])))
	assert_true(world.has_line_of_sight(Vector2(0.0, 0.0), Vector2(400.0, 0.0), wall))

func test_point_blocked_inside_wall_only() -> void:
	assert_true(world.is_point_blocked(Vector2(200.0, 0.0)))
	assert_false(world.is_point_blocked(Vector2(100.0, 0.0)))
	assert_false(world.is_point_blocked(Vector2(200.0, 0.0), null, PackedStringArray(["wall"])))

func test_find_path_goes_around_wall() -> void:
	var from := Vector2(0.0, 0.0)
	var to := Vector2(400.0, 0.0)
	var path: PackedVector2Array = world.find_path(from, to, 32.0)

	assert_gt(path.size(), 1, "detour has waypoints")
	assert_eq(path[path.size() - 1], to, "path ends at the goal")
	assert_true(world.is_path_clear(from, path, to), "every leg has line of sight")

	var clears := true
	for point in path:
		if world.is_point_blocked(point):
			clears = false
	assert_true(clears, "no waypoint inside the wall")

func test_find_path_with_line_of_sight_is_the_goal() -> void:
	var path: PackedVector2Array = world.find_path(Vector2(0.0, 300.0), Vector2(400.0, 300.0), 32.0)
	assert_eq(path.size(), 1)
	assert_eq(path[0], Vector2(400.0, 300.0))

	var through: PackedVector2Array = world.find_path(Vector2(0.0, 0.0), Vector2(400.0, 0.0), 32.0, null, PackedStringArray(["wall"]))
	assert_eq(through.size(), 1, "ignored wall does not block the path")

func test_advance_waypoints_drops_reached_and_passed_points() -> void:
	var path := PackedVector2Array([Vector2(10.0, 0.0), Vector2(50.0, 0.0), Vector2(100.0, 0.0)])
	var advanced: PackedVector2Array = RegolithWorld.advance_waypoints(path, Vector2(12.0, 0.0), 5.0)
	assert_eq(advanced.size(), 2, "first point within capture radius is dropped")
	assert_eq(advanced[0], Vector2(50.0, 0.0))

	advanced = RegolithWorld.advance_waypoints(path, Vector2(60.0, 0.0), 1.0)
	assert_eq(advanced.size(), 2, "the point behind a closer one is dropped")
	assert_eq(advanced[0], Vector2(50.0, 0.0))

func test_repairable_sprite_empties_instead_of_dying() -> void:
	var block := RegolithSprite.new()
	block.dynamic = false
	block.repairable = true
	block.position = Vector2(0.0, 400.0)
	arena.add_child(block)
	block.create_blank(Vector2i(8, 8))
	block.fill_rect(Rect2i(0, 0, 8, 8), Color.WHITE, RegolithSprite.CELL_FILLED, 0)
	await wait_physics_frames(2)

	watch_signals(world)
	var count := world.get_sprite_count()

	for y in 7:
		for x in 8:
			block.remove_cell(Vector2i(x, y))
	await wait_physics_frames(3)

	assert_signal_emitted(world, "sprite_emptied")
	assert_signal_not_emitted(world, "sprite_destroyed")
	assert_true(is_instance_valid(block), "node survives")
	assert_eq(block.get_active_cell_count(), 0)
	assert_eq(world.get_sprite_count(), count)

	block.repair_all_cells()
	await wait_physics_frames(2)
	assert_eq(block.get_active_cell_count(), 64, "repair brings every cell back")

func test_tree_covers_rope_nodes_for_segment_queries() -> void:
	# a plain sprite's box is just its body, the query outside it finds nothing
	assert_eq(world.query_segment(Vector2(200.0, 300.0), Vector2(200.0, 400.0)).size(), 0)

func test_enemy_path_steer_target_detours_around_wall() -> void:
	var bomb: EnemyBomb = load("res://game/scenes/enemies/EnemyBomb.tscn").instantiate()
	bomb.position = Vector2(0.0, 0.0)
	bomb.seek_thrower = false
	arena.add_child(bomb)
	await wait_physics_frames(2)

	var ppu := RegolithWorld.pixels_per_unit()
	var goal := Vector2(400.0, 0.0) / ppu
	var seek: Vector2 = bomb.path_steer_target(goal, 0.1)

	assert_false(bomb.path_blocked, "a path around the wall exists")
	assert_ne(seek, goal, "first waypoint is not the goal while the wall blocks the view")
	assert_gt(bomb.path.size(), 0)

	var open := Vector2(0.0, 300.0) / ppu
	bomb.linear_velocity = Vector2.ZERO
	var direct: Vector2 = bomb.path_steer_target(open, 0.1)
	assert_true(bomb.path.is_empty(), "a goal in sight clears the path")
	assert_eq(direct, open)
