extends GutTest

# the missile targeter: holding the trigger with the missiles selected
# paints locks along the aim, letting go ripples missiles at them and
# spends ammo, the weapon itself never fires

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var arena: Node2D
var world: RegolithWorld
var player: Player
var targeter: MissileTargeter
var missiles: Weapon

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
	targeter = player.get_node("MissileTargeter")
	targeter.use_input = false
	missiles = player.get_node("Missiles")
	await wait_physics_frames(2)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func add_rock(units: Vector2) -> RegolithSprite:
	var rock := RegolithSprite.new()
	rock.dynamic = false
	rock.position = player.global_position + units * ppu()
	arena.add_child(rock)
	rock.create_blank(Vector2i(32, 32))
	rock.fill_rect(Rect2i(0, 0, 32, 32), Color.GRAY, RegolithSprite.CELL_FILLED, 0)
	return rock

func test_targeter_finds_its_weapon_and_is_idle_when_not_selected() -> void:
	assert_eq(targeter.weapon, missiles)
	assert_false(targeter.selected(), "cannon is the first weapon")
	targeter.set_fire_state(true, player.global_position + Vector2(300.0, 0.0))
	await wait_physics_frames(5)
	assert_eq(targeter.targets.size(), 0, "no locks without the missiles selected")

func test_hold_locks_then_release_fires_missiles_at_the_lock() -> void:
	var rock := add_rock(Vector2(8.0, 0.0))
	await wait_physics_frames(2)

	player.select_weapon(player.weapons.find(missiles))
	assert_true(targeter.selected())

	var ammo := missiles.ammo
	var launched: Array = []
	targeter.launched.connect(func(missile): launched.append(missile))
	watch_signals(targeter)

	targeter.set_fire_state(true, rock.global_position)
	await wait_physics_frames(20)

	assert_signal_emitted(targeter, "locked")
	assert_eq(targeter.targets.size(), 1, "the same cell locks once")
	assert_eq(targeter.targets[0]["sprite"], rock)
	assert_eq(missiles.ammo, ammo, "nothing fired while held")

	targeter.set_fire_state(false, rock.global_position)
	await wait_physics_frames(10)

	assert_eq(launched.size(), 1, "one missile per lock")
	assert_eq(missiles.ammo, ammo - 1, "each missile spends an ammo")
	var missile: Missile = launched[0]
	assert_true(is_instance_valid(missile))
	assert_eq(missile.target_sprite, rock, "missile flies at the lock")
	assert_almost_eq(missile.speed, MissileTargeter.LAUNCH_SPEED, 0.001, "launched slowly")
	assert_true(targeter.targets.is_empty())

func test_locks_spread_over_a_wide_sprite() -> void:
	var rock := add_rock(Vector2(8.0, 0.0))
	await wait_physics_frames(2)
	player.select_weapon(player.weapons.find(missiles))

	var sweep := [rock.global_position + Vector2(0.0, -0.4 * ppu()), rock.global_position + Vector2(0.0, 0.4 * ppu())]
	targeter.set_fire_state(true, sweep[0])
	await wait_physics_frames(8)
	targeter.set_fire_state(true, sweep[1])
	await wait_physics_frames(8)

	assert_eq(targeter.targets.size(), 2, "two spots far enough apart both lock")
	targeter.set_fire_state(false, sweep[1])
	await wait_physics_frames(2)

func test_targeter_takes_the_trigger_from_the_weapon() -> void:
	player.select_weapon(player.weapons.find(missiles))
	targeter.use_input = true
	missiles.set_fire_state(true, Vector2.RIGHT)
	targeter._process(0.016)
	assert_false(missiles.triggered, "the weapon never fires on its own while targeted")
	targeter.use_input = false
