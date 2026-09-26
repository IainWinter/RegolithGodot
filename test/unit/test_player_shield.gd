extends GutTest

# the player shield: an active shield shoves a rock inside it outward,
# turns an enemy bullet away, throws bolts along its shell, and does
# nothing while off

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const SHIELD_PROPS := preload("res://game/config/player/shield.tres")
const CANNON := preload("res://game/config/weapons/default_cannon.tres")

var arena: Node2D
var world: RegolithWorld
var player: Player
var shield: PlayerShield

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
	player = load("res://game/scenes/player/Player.tscn").instantiate()
	player.set_process(false)
	arena.add_child(player)
	shield = player.get_node("Shield")
	shield.use_input = false
	await wait_physics_frames(2)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func add_rock(units: Vector2) -> RegolithSprite:
	var rock := RegolithSprite.new()
	rock.position = player.global_position + units * ppu()
	arena.add_child(rock)
	rock.create_blank(Vector2i(16, 16))
	rock.fill_rect(Rect2i(0, 0, 16, 16), Color.GRAY, RegolithSprite.CELL_FILLED, 0)
	return rock

func test_player_scene_carries_a_shield() -> void:
	assert_not_null(shield)
	assert_eq(shield.props, SHIELD_PROPS)
	assert_true(shield.is_in_group("player_shield"))
	assert_not_null(shield.lightning, "shell lightning attached")

func test_active_shield_pushes_a_rock_out() -> void:
	var rock := add_rock(Vector2(1.5, 0.0))
	await wait_physics_frames(2)
	watch_signals(shield)

	shield.active = true
	await wait_physics_frames(20)

	assert_signal_emitted(shield, "pushed")
	assert_gt(rock.linear_velocity.x, 0.0, "rock shoved away from the player")
	var distance := rock.global_position.distance_to(player.global_position) / ppu()
	assert_gt(distance, 1.5, "rock moved outward")

func test_inactive_shield_leaves_rocks_alone() -> void:
	var rock := add_rock(Vector2(1.5, 0.0))
	rock.linear_velocity = Vector2.ZERO
	await wait_physics_frames(10)
	assert_lt(absf(rock.linear_velocity.x), 0.5, "no shove while off")
	assert_true(shield.pushes.is_empty())

func test_shield_bends_an_enemy_bullet_away() -> void:
	var enemy := add_rock(Vector2(8.0, 0.0))
	await wait_physics_frames(1)

	shield.active = true
	watch_signals(shield)

	var props: WeaponProps = CANNON.duplicate()
	props.speed = 6.0
	props.lifetime = 5.0
	var bullet: Bullet = props.projectile_scene.instantiate()
	bullet.setup(props, player.global_position + Vector2(2.0 * ppu(), 0.0), Vector2.LEFT, Vector2.ZERO, enemy)
	arena.add_child(bullet)
	await wait_physics_frames(1)

	assert_true(bullet.is_in_group("projectile"))
	var before := bullet.velocity.x
	await wait_physics_frames(6)

	assert_signal_emitted(shield, "deflected")
	assert_gt(bullet.velocity.x, before, "bullet pushed back outward")

func test_shell_lightning_strikes_while_active() -> void:
	shield.active = true
	await wait_physics_frames(10)
	assert_gt(shield.lightning.get_strike_count(), 0, "bolts along the shell")

	shield.active = false
	await wait_physics_frames(1)
	assert_eq(shield.strike_accumulator, 0.0)

func test_arc_helpers() -> void:
	assert_true(PlayerShield.angle_in_arc(0.0, -1.0, 1.0))
	assert_false(PlayerShield.angle_in_arc(2.0, -1.0, 1.0))
	assert_almost_eq(PlayerShield.clamp_to_arc(0.5, -1.0, 1.0), 0.5, 0.001)
	assert_almost_eq(PlayerShield.clamp_to_arc(1.5, -1.0, 1.0), 1.0, 0.001)
	assert_almost_eq(PlayerShield.clamp_to_arc(-1.5, -1.0, 1.0), -1.0, 0.001)
	assert_almost_eq(PlayerShield.capture_accel(Vector2(-4.0, 0.0), Vector2.RIGHT, 1.0), 8.0, 0.001)
	assert_eq(PlayerShield.capture_accel(Vector2(4.0, 0.0), Vector2.RIGHT, 1.0), 0.0)
