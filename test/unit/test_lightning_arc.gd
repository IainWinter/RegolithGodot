extends GutTest

# the lightning ball and the zap gun arc at other people's projectiles
# inside their radius, shoving them away and breaking their homing, the
# boss's bolt included

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const BALL := preload("res://game/config/weapons/lightning_ball.tres")
const BOLT := preload("res://game/config/weapons/lightning_bolt.tres")
const BOSS_BOLT := preload("res://game/config/enemies/boss_bolt.tres")
const MISSILES := preload("res://game/config/weapons/missiles.tres")
const CANNON := preload("res://game/config/weapons/default_cannon.tres")

var arena: Node2D
var world: RegolithWorld
var shooter: RegolithSprite
var enemy: RegolithSprite

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
	shooter = add_block(Vector2(-600.0, 0.0))
	enemy = add_block(Vector2(600.0, 0.0))
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

func spawn_ball(at: Vector2) -> LightningBall:
	var props: LightningWeaponProps = BALL.duplicate()
	props.speed = 0.0
	var ball: LightningBall = props.projectile_scene.instantiate()
	ball.setup(props, at, Vector2.RIGHT, Vector2.ZERO, shooter)
	arena.add_child(ball)
	return ball

func spawn_enemy_bullet(at: Vector2) -> Bullet:
	var props: WeaponProps = CANNON.duplicate()
	props.speed = 4.0
	props.lifetime = 5.0
	var bullet: Bullet = props.projectile_scene.instantiate()
	bullet.setup(props, at, Vector2.RIGHT, Vector2.ZERO, enemy)
	arena.add_child(bullet)
	return bullet

func test_ball_arcs_at_an_enemy_bullet_and_shoves_it() -> void:
	var ball := spawn_ball(Vector2.ZERO)
	var bullet := spawn_enemy_bullet(Vector2(0.0, 20.0))
	watch_signals(ball)
	await wait_physics_frames(4)

	assert_signal_emitted(ball, "arced")
	assert_gt(bullet.velocity.y, 0.0, "bullet shoved away from the ball")
	assert_gt(ball.lightning.get_strike_count(), 0)

func test_ball_ignores_its_own_shooters_bullets() -> void:
	var ball := spawn_ball(Vector2.ZERO)
	var props: WeaponProps = CANNON.duplicate()
	props.speed = 4.0
	var bullet: Bullet = props.projectile_scene.instantiate()
	bullet.setup(props, Vector2(0.0, 20.0), Vector2.RIGHT, Vector2.ZERO, shooter)
	arena.add_child(bullet)
	watch_signals(ball)
	await wait_physics_frames(4)

	assert_signal_not_emitted(ball, "arced")
	assert_almost_eq(bullet.velocity.y, 0.0, 0.001)

func test_ball_breaks_a_missiles_lock() -> void:
	var ball := spawn_ball(Vector2.ZERO)
	var props: HomingWeaponProps = MISSILES.duplicate()
	props.speed = 1.0
	props.coast_time = 10.0
	var missile: Missile = props.projectile_scene.instantiate()
	missile.setup(props, Vector2(0.0, 30.0), Vector2.RIGHT, Vector2.ZERO, enemy)
	arena.add_child(missile)
	missile.set_target(shooter, Vector2.ZERO)
	assert_eq(missile.target_sprite, shooter)
	await wait_physics_frames(4)

	assert_null(missile.target_sprite, "the arc cleared the lock")
	assert_true(is_instance_valid(ball))

func test_ball_shoves_a_boss_bolt_off_course() -> void:
	var ball := spawn_ball(Vector2.ZERO)
	var bolt: LightningBolt = BOSS_BOLT.projectile_scene.instantiate()
	bolt.setup(BOSS_BOLT, Vector2(0.0, 30.0), Vector2.RIGHT, Vector2.ZERO, enemy)
	arena.add_child(bolt)
	assert_almost_eq(bolt.velocity, Vector2(BOSS_BOLT.speed, 0.0), Vector2(0.001, 0.001), "flies by velocity")
	watch_signals(ball)
	await wait_physics_frames(3)

	assert_signal_emitted(ball, "arced")
	assert_true(is_instance_valid(bolt))
	assert_gt(bolt.velocity.y, 0.0, "bolt shoved away from the ball")
	assert_almost_eq(bolt.angle, bolt.velocity.angle(), 0.001, "its heading follows the shove")

func test_zap_arcs_at_an_enemy_bullet_and_shoves_it() -> void:
	var props: LightningWeaponProps = BOLT.duplicate()
	var zap: LightningZap = props.projectile_scene.instantiate()
	zap.setup(props, Vector2.ZERO, Vector2.RIGHT, Vector2.ZERO, shooter)
	var arcs := {"count": 0}
	zap.arced.connect(func(_projectile): arcs["count"] += 1)
	var bullet := spawn_enemy_bullet(Vector2(0.0, 20.0))
	arena.add_child(zap)
	await wait_physics_frames(3)

	assert_eq(arcs["count"], 1, "the one bullet in reach was arced at")
	assert_gt(bullet.velocity.y, 0.0, "bullet shoved away from the muzzle")
	assert_false(is_instance_valid(zap), "the zap is gone after its shot")

func test_zap_leaves_a_bullet_beyond_its_arc_radius_alone() -> void:
	var props: LightningWeaponProps = BOLT.duplicate()
	var zap: LightningZap = props.projectile_scene.instantiate()
	zap.setup(props, Vector2.ZERO, Vector2.RIGHT, Vector2.ZERO, shooter)
	var arcs := {"count": 0}
	zap.arced.connect(func(_projectile): arcs["count"] += 1)
	var bullet := spawn_enemy_bullet(Vector2(0.0, props.bolt_arc_radius * RegolithWorld.pixels_per_unit() + 40.0))
	arena.add_child(zap)
	await wait_physics_frames(3)

	assert_eq(arcs["count"], 0)
	assert_almost_eq(bullet.velocity.y, 0.0, 0.001)
