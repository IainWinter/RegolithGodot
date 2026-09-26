extends GutTest

# GravityAttractor: sprites with a GravityMover child fall toward every
# attractor with an inverse square pull, others drift on

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var arena: Node2D
var world: RegolithWorld

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

func after_each() -> void:
	arena.free()

func add_block(at: Vector2) -> RegolithSprite:
	var block := RegolithSprite.new()
	block.position = at
	arena.add_child(block)
	block.create_blank(Vector2i(16, 16))
	block.fill_rect(Rect2i(0, 0, 16, 16), Color.WHITE, RegolithSprite.CELL_FILLED, 0)
	return block

func add_mover(at: Vector2, strength := 1.0) -> RegolithSprite:
	var block := add_block(at)
	var mover := GravityMover.new()
	mover.strength = strength
	block.add_child(mover)
	return block

func add_attractor(at: Vector2, mass: float) -> GravityAttractor:
	var attractor := GravityAttractor.new()
	attractor.mass = mass
	attractor.position = at
	arena.add_child(attractor)
	return attractor

func test_pull_is_inverse_square_toward_the_mass() -> void:
	var source := Vector2(10.0, 0.0)
	var near := GravityAttractor.pull_at(source, 4.0, Vector2(8.0, 0.0), 1.0)
	var far := GravityAttractor.pull_at(source, 4.0, Vector2(6.0, 0.0), 1.0)
	assert_almost_eq(near.x, 1.0, 0.001, "4 over 2 squared")
	assert_almost_eq(far.x, 0.25, 0.001, "4 over 4 squared")
	assert_eq(GravityAttractor.pull_at(source, 4.0, source, 1.0), Vector2.ZERO, "no pull at the center")
	assert_almost_eq(GravityAttractor.pull_at(source, 4.0, Vector2(8.0, 0.0), 3.0).x, 3.0, 0.001, "strength scales")

func test_movers_fall_toward_the_attractor_and_others_do_not() -> void:
	add_attractor(Vector2(400.0, 0.0), 40.0)
	var mover := add_mover(Vector2(0.0, 0.0))
	var bystander := add_block(Vector2(0.0, 300.0))
	await wait_physics_frames(30)

	assert_gt(mover.linear_velocity.x, 0.0, "mover pulled toward the attractor")
	assert_almost_eq(bystander.linear_velocity.x, 0.0, 0.001, "sprite without a mover untouched")

func test_mover_strength_scales_the_pull() -> void:
	add_attractor(Vector2(400.0, 0.0), 40.0)
	var light := add_mover(Vector2(0.0, 0.0))
	var heavy := add_mover(Vector2(0.0, 400.0), 4.0)
	await wait_physics_frames(20)

	assert_gt(heavy.linear_velocity.length(), light.linear_velocity.length() * 1.5, "stronger mover pulled harder")

func test_every_attractor_pulls() -> void:
	var balanced := add_mover(Vector2(0.0, 0.0))
	var pulled := add_mover(Vector2(0.0, 300.0))
	await wait_physics_frames(1)
	# the pull acts on the center of mass, which sits off the node origin
	# (the art loads into the corner of the chunk padded grid), so the pair
	# of attractors is centered on the mass itself
	var com := balanced.get_center_of_mass()
	add_attractor(com + Vector2(400.0, 0.0), 40.0)
	add_attractor(com - Vector2(400.0, 0.0), 40.0)
	await wait_physics_frames(30)

	assert_almost_eq(balanced.linear_velocity.x, 0.0, 0.01, "two equal pulls cancel")
	assert_gt(absf(pulled.linear_velocity.y), 0.0, "off axis mover drawn toward both")
	assert_lt(pulled.linear_velocity.y, 0.0, "toward the attractors' line")
