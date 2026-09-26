extends GutTest

# the player's lightning bolt is the original lightning gun: an instant bolt
# from the muzzle that zaps the first cell within its range while the
# trigger is held, reaches nothing beyond it, and costs one ammo a shot.
# the boss keeps the homing bolt

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const BOLT := preload("res://game/config/weapons/lightning_bolt.tres")
const BOSS_BOLT := preload("res://game/config/enemies/boss_bolt.tres")

var arena: Node2D
var world: RegolithWorld
var shooter: RegolithSprite
var gun: Weapon
var hits: Array = []
var shots: Array = []
var peak_strikes := 0

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
	shooter = add_block(Vector2.ZERO)
	hits = []
	shots = []
	peak_strikes = 0
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

# the bolt gun on the shooter. sure makes every zap remove cells so a short
# hold is enough to see damage. shots and the sprites they hit are kept
func add_gun(sure: bool) -> Weapon:
	var props: LightningWeaponProps = BOLT.duplicate()

	if sure:
		props.bolt_pixels_per_second = 1000.0

	gun = Weapon.new()
	gun.props = props
	shooter.add_child(gun)
	gun.fired.connect(func(bullet: Node2D):
		shots.append(bullet)
		bullet.hit_cell.connect(func(sprite, _cell, _position): hits.append(sprite)))
	return gun

func hold_fire(frames: int) -> void:
	for i in frames:
		gun.set_fire_state(true, Vector2.RIGHT)
		await wait_physics_frames(1)
		var effect := shared_effect()

		if effect != null:
			peak_strikes = maxi(peak_strikes, effect.get_strike_count())

	gun.set_fire_state(false, Vector2.RIGHT)
	await wait_physics_frames(2)

func shared_effect() -> Lightning:
	return arena.get_node_or_null(NodePath(LightningZap.SHARED_LIGHTNING_NAME)) as Lightning

func range_pixels() -> float:
	return BOLT.bolt_range * RegolithWorld.pixels_per_unit()

func test_bolt_gun_is_the_original_lightning_gun() -> void:
	assert_eq(BOLT.ammo, 1000)
	assert_eq(BOLT.shots_per_ammo, 1)
	assert_almost_eq(BOLT.delay_cooldown, 0.02, 0.0001)
	assert_almost_eq(BOLT.delay_charge, 0.0, 0.0001)
	assert_almost_eq(BOLT.inaccuracy_angle, 0.1, 0.0001)
	assert_almost_eq(BOLT.inaccuracy_tangent, 0.0, 0.0001)
	assert_almost_eq(BOLT.bolt_range, 3.0, 0.0001)
	assert_almost_eq(BOLT.bolt_pixels_per_second, 20.0, 0.0001)
	assert_almost_eq(BOLT.bolt_arc_radius, 2.4, 0.0001)
	assert_not_null(BOLT.lightning)
	assert_not_null(BOLT.lightning_hit)

	var shot: Node2D = BOLT.projectile_scene.instantiate()
	assert_true(shot is LightningZap, "the player fires instant zaps")
	shot.free()

	var boss_shot: Node2D = BOSS_BOLT.projectile_scene.instantiate()
	assert_true(boss_shot is LightningBolt, "the boss keeps the homing bolt")
	boss_shot.free()
	assert_almost_eq(BOSS_BOLT.speed, 9.0, 0.0001)
	assert_almost_eq(BOSS_BOLT.turn_speed, 2.0, 0.0001)
	assert_almost_eq(BOSS_BOLT.delay_charge, 1.5, 0.0001)
	assert_eq(BOSS_BOLT.cell_life, 8)

func test_damage_odds_average_pixels_per_second_at_the_fire_rate() -> void:
	assert_almost_eq(LightningZap.damage_chance(20.0, 50.0), 0.08, 0.0001, "twenty pixels a second at fifty zaps of five")
	assert_almost_eq(LightningZap.damage_chance(1000.0, 50.0), 1.0, 0.0001, "clamped")
	assert_eq(LightningZap.damage_chance(20.0, 0.0), 0.0)

func test_bolt_gun_zaps_cells_within_range_while_held() -> void:
	var block := add_block(Vector2(range_pixels() * 0.5, 0.0))
	add_gun(true)
	await wait_physics_frames(1)
	var before := block.get_active_cell_count()
	var ammo := gun.ammo
	# sure zaps can carve the small block apart, later zaps then land on the
	# split pieces, which are still the block in range
	var pieces := [block]
	world.sprite_split.connect(func(source, piece):
		if source in pieces:
			pieces.append(piece))

	await hold_fire(30)

	assert_gt(shots.size(), 10, "a shot every cooldown while held")
	assert_eq(gun.ammo, ammo - shots.size(), "each shot costs one ammo")
	assert_gt(hits.size(), 0, "cells zapped")
	assert_true(hits.all(func(sprite): return sprite in pieces), "every hit lands on the block in range or a piece split off it")
	assert_lt(block.get_active_cell_count(), before, "block lost cells")
	assert_gt(peak_strikes, 0, "bolts drawn to the hit")
	assert_not_null(shared_effect(), "the zaps share one lightning under the projectile parent")
	assert_eq(arena.get_children().filter(func(child): return child is Lightning).size(), 1, "one shared lightning, not one per shot")
	assert_true(shots.all(func(shot): return not is_instance_valid(shot)), "a zap frees itself after its shot")

func test_bolt_gun_reaches_nothing_beyond_its_range() -> void:
	var block := add_block(Vector2(range_pixels() * 1.5, 0.0))
	add_gun(true)
	await wait_physics_frames(1)
	var before := block.get_active_cell_count()

	await hold_fire(30)

	assert_gt(shots.size(), 10, "shots still fire")
	assert_eq(hits.size(), 0, "nothing within range to zap")
	assert_eq(block.get_active_cell_count(), before, "block beyond range untouched")
	assert_gt(peak_strikes, 0, "bolts still drawn to the end of the range")

func test_bolt_gun_stops_when_released() -> void:
	add_block(Vector2(range_pixels() * 0.5, 0.0))
	add_gun(true)
	await wait_physics_frames(1)

	await hold_fire(6)
	var fired := shots.size()
	await wait_physics_frames(10)

	assert_eq(shots.size(), fired, "no shots after release")
