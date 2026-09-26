extends GutTest

# the lightning ball is the original: ten slow shots that drift along the
# aim, zap the cells inside their radius and nothing beyond it, and arc to
# each other when they come close

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const BALL := preload("res://game/config/weapons/lightning_ball.tres")

var arena: Node2D
var world: RegolithWorld
var shooter: RegolithSprite

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)
	shooter = add_block(Vector2(-900.0, 0.0))
	await wait_physics_frames(2)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

func add_block(at: Vector2) -> RegolithSprite:
	var block := RegolithSprite.new()
	block.dynamic = false
	block.position = at
	arena.add_child(block)
	block.create_blank(Vector2i(16, 16))
	block.fill_rect(Rect2i(0, 0, 16, 16), Color.WHITE, RegolithSprite.CELL_FILLED, 0)
	return block

# a ball that stays put. sure makes every zap remove cells
func spawn_ball(at: Vector2, sure := false) -> LightningBall:
	var props: LightningWeaponProps = BALL.duplicate()
	props.speed = 0.0

	if sure:
		props.ball_pixels_per_second = 100000.0

	var ball: LightningBall = props.projectile_scene.instantiate()
	ball.setup(props, at, Vector2.RIGHT, Vector2.ZERO, shooter)
	arena.add_child(ball)
	return ball

func has_strike_to(lightning: Lightning, end: Vector2) -> bool:
	for s in lightning.strikes:
		if s.end.distance_to(end) < 1.0:
			return true

	return false

func test_ball_is_the_original_lightning_ball() -> void:
	assert_eq(BALL.ammo, 10)
	assert_eq(BALL.shots_per_ammo, 1)
	assert_almost_eq(BALL.delay_cooldown, 1.2, 0.0001)
	assert_almost_eq(BALL.inaccuracy_angle, 0.1, 0.0001)
	assert_almost_eq(BALL.inaccuracy_tangent, 0.0, 0.0001)
	assert_almost_eq(BALL.speed, 8.0, 0.0001)
	assert_almost_eq(BALL.lifetime, 6.0, 0.0001)
	assert_almost_eq(BALL.ball_radius, 2.0, 0.0001)
	assert_almost_eq(BALL.ball_emit_radius, 0.4, 0.0001)
	assert_eq(BALL.ball_segments, 6)
	assert_almost_eq(BALL.ball_delay_per_hit, 0.02, 0.0001)
	assert_eq(BALL.ball_zaps_per_hit, 10)
	assert_almost_eq(BALL.ball_pixels_per_second, 80.0, 0.0001)

	var shot: Node2D = BALL.projectile_scene.instantiate()
	assert_true(shot is LightningBall)
	shot.free()

func test_ball_flies_at_its_speed_with_no_holder_velocity() -> void:
	var ball: LightningBall = BALL.projectile_scene.instantiate()
	ball.setup(BALL, Vector2.ZERO, Vector2.RIGHT, Vector2(50.0, 50.0), shooter)
	arena.add_child(ball)

	assert_almost_eq(ball.velocity, Vector2(8.0, 0.0), Vector2(0.001, 0.001), "aim times speed, units per second")
	assert_almost_eq(ball.lifetime, 6.0, 0.0001)

func test_ball_zaps_cells_inside_its_radius_only() -> void:
	var ppu := RegolithWorld.pixels_per_unit()
	var near := add_block(Vector2(200.0, 0.0))
	var far := add_block(Vector2(200.0 + 4.0 * ppu, 0.0))
	await wait_physics_frames(1)

	var ball := spawn_ball(near.get_center_of_mass() - Vector2(ppu, 0.0), true)
	var hits: Array = []
	ball.hit_cell.connect(func(sprite, _cell, _position): hits.append(sprite))
	var near_before := near.get_active_cell_count()
	var far_before := far.get_active_cell_count()

	await wait_physics_frames(30)

	assert_gt(hits.size(), 0, "cells zapped")
	assert_true(hits.all(func(sprite): return sprite == near), "every zap on the block one unit away")
	assert_lt(near.get_active_cell_count(), near_before, "near block lost cells")
	assert_eq(far.get_active_cell_count(), far_before, "block five units away untouched")

func test_balls_arc_to_each_other_when_close() -> void:
	var ppu := RegolithWorld.pixels_per_unit()
	var a := spawn_ball(Vector2.ZERO)
	var b := spawn_ball(Vector2(1.5 * ppu, 0.0))
	await wait_physics_frames(4)

	assert_true(has_strike_to(a.lightning, b.global_position), "a arcs to b")
	assert_true(has_strike_to(b.lightning, a.global_position), "b arcs to a")

func test_balls_apart_do_not_arc() -> void:
	var ppu := RegolithWorld.pixels_per_unit()
	var a := spawn_ball(Vector2.ZERO)
	var b := spawn_ball(Vector2(6.0 * ppu, 0.0))
	await wait_physics_frames(4)

	assert_false(has_strike_to(a.lightning, b.global_position), "beyond both radii, no arc")
