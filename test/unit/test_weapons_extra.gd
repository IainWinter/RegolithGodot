extends GutTest

# the ported player weapons in the main scene: each one takes cells off the
# rock, missiles and force bullets home, the laser burns while held, the
# player switches slots

var main: Node2D
var world: RegolithWorld
var player: Player
var rock: RegolithSprite

func before_each() -> void:
	main = load("res://game/scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	world = main.get_node("RegolithWorld")
	player = main.get_node("Player")
	rock = main.get_node("Rock")
	player.set_process(false)
	await wait_physics_frames(3)

func after_each() -> void:
	main.free()

func weapon_named(name: String) -> Weapon:
	return player.get_node(name) as Weapon

func to_rock() -> Vector2:
	return rock.global_position - player.global_position

func hold_fire(weapon: Weapon, frames: int, direction: Vector2) -> void:
	for i in frames:
		weapon.set_fire_state(true, direction)
		await wait_physics_frames(1)
	weapon.set_fire_state(false, direction)

func test_player_weapon_slots() -> void:
	assert_eq(player.weapons.size(), 7)
	assert_eq(player.weapon, player.weapons[0])
	assert_eq(player.weapons[5].props.resource_path, "res://game/config/weapons/lightning_bolt.tres", "slot 6 is the lightning bolt")
	assert_eq(player.weapon.props.resource_path, "res://game/config/weapons/default_cannon.tres")
	for w in player.weapons:
		assert_not_null(w.props.projectile_scene, "%s names its projectile scene" % w.name)

func test_minigun_fires_fast_and_removes_cells() -> void:
	var minigun := weapon_named("Minigun")
	var counts := {"bullets": 0}
	minigun.fired.connect(func(_bullet: Node2D): counts["bullets"] += 1)
	var rock_cells := rock.get_active_cell_count()
	var ammo := minigun.ammo

	await hold_fire(minigun, 60, to_rock())
	await wait_physics_frames(60)

	assert_gt(counts["bullets"], 30, "a burst of bullets in a second")
	assert_eq(minigun.ammo, ammo - counts["bullets"], "each bullet costs one ammo")
	assert_lt(rock.get_active_cell_count(), rock_cells, "rock lost cells")

func test_missiles_fire_salvo_and_remove_cells() -> void:
	var missiles := weapon_named("Missiles")
	var spawned: Array = []
	var counts := {"exploded": 0}
	missiles.fired.connect(func(bullet: Node2D):
		spawned.append(bullet)
		bullet.exploded.connect(func(_position): counts["exploded"] += 1))
	var rock_cells := rock.get_active_cell_count()

	await hold_fire(missiles, 1, to_rock())
	assert_eq(spawned.size(), missiles.props.shots_per_ammo, "one salvo")
	assert_eq(missiles.ammo, missiles.props.ammo - 1, "a salvo costs one ammo")

	for i in 240:
		if counts["exploded"] == spawned.size():
			break
		await wait_physics_frames(1)
	await wait_physics_frames(60)

	assert_gt(counts["exploded"], 0, "missiles exploded")
	assert_lt(rock.get_active_cell_count(), rock_cells, "rock lost cells")

func test_missile_homes_toward_off_axis_target() -> void:
	var missiles := weapon_named("Missiles")
	var props: HomingWeaponProps = missiles.props.duplicate()
	props.shots_per_ammo = 1
	props.inaccuracy_angle = 0.0
	props.inaccuracy_tangent = 0.0
	missiles.props = props

	var spawned: Array = []
	missiles.fired.connect(func(bullet: Node2D): spawned.append(bullet))

	var direction := to_rock().normalized()
	var across := Vector2(-direction.y, direction.x)
	await hold_fire(missiles, 1, across)
	assert_eq(spawned.size(), 1)
	if spawned.is_empty():
		return

	var missile: Missile = spawned[0]
	missile.set_target(rock, Vector2.ZERO)
	var start_alignment := missile.velocity.normalized().dot((rock.global_position - missile.global_position).normalized())
	assert_almost_eq(start_alignment, 0.0, 0.05, "launched across the rock")

	await wait_physics_frames(int(props.coast_time * 60.0) + 20)
	assert_true(is_instance_valid(missile) and not missile.dead, "still flying")
	if not is_instance_valid(missile) or missile.dead:
		return

	var alignment := missile.velocity.normalized().dot((rock.global_position - missile.global_position).normalized())
	assert_gt(alignment, 0.7, "turned toward the rock")
	assert_gt(missile.speed, props.speed, "motor accelerates")

func force_gun_straight() -> Weapon:
	var force_gun := weapon_named("ForceGun")
	var props: HomingWeaponProps = force_gun.props.duplicate()
	props.inaccuracy_angle = 0.0
	force_gun.props = props
	return force_gun

func test_force_bullet_hits_target_and_explodes() -> void:
	var force_gun := force_gun_straight()
	var spawned: Array = []
	var hits := {"sprite": null, "exploded": false}
	force_gun.fired.connect(func(bullet: Node2D):
		spawned.append(bullet)
		bullet.hit_cell.connect(func(sprite, _cell, _position): hits["sprite"] = sprite)
		bullet.exploded.connect(func(_position): hits["exploded"] = true))
	var rock_cells := rock.get_active_cell_count()

	await hold_fire(force_gun, 1, to_rock())
	assert_eq(spawned.size(), 1)
	if spawned.is_empty():
		return

	var bullet: ForceBullet = spawned[0]
	bullet.set_target(rock, Vector2.ZERO)
	assert_eq(bullet.target_sprite, rock)
	assert_gt(bullet.orb_radius(), bullet.props.width * RegolithWorld.pixels_per_unit(), "starts as a wide orb")

	for i in 600:
		if hits["exploded"]:
			break
		await wait_physics_frames(1)
	await wait_physics_frames(60)

	assert_true(hits["exploded"], "force bullet went off")
	assert_eq(hits["sprite"], rock, "it hit the rock")
	assert_lt(rock.get_active_cell_count(), rock_cells, "rock lost cells")

func test_force_bullet_curves_to_off_axis_target() -> void:
	var force_gun := force_gun_straight()
	var spawned: Array = []
	force_gun.fired.connect(func(bullet: Node2D): spawned.append(bullet))

	var direction := to_rock().normalized()
	await hold_fire(force_gun, 1, Vector2(-direction.y, direction.x))
	assert_eq(spawned.size(), 1)
	if spawned.is_empty():
		return

	var bullet: ForceBullet = spawned[0]
	bullet.set_target(rock, Vector2.ZERO)
	assert_false(bullet.homing_locked)

	var closest := INF
	var closest_speed := 0.0
	var locked := false
	for i in 600:
		if not is_instance_valid(bullet) or bullet.dead:
			break
		locked = locked or bullet.homing_locked
		var distance := bullet.global_position.distance_to(rock.global_position) / RegolithWorld.pixels_per_unit()
		if distance < closest:
			closest = distance
			closest_speed = bullet.speed
		await wait_physics_frames(1)

	assert_true(locked, "locked on once the rock was ahead")
	assert_lt(closest, 3.0, "swung in close to the rock")
	assert_gt(closest_speed, bullet.props.speed, "sped up on the way")

func test_super_laser_burns_while_held_and_stops_on_release() -> void:
	var laser := weapon_named("SuperLaser")
	var props: BeamWeaponProps = laser.props
	var spawned: Array = []
	laser.fired.connect(func(bullet: Node2D): spawned.append(bullet))
	var rock_cells := rock.get_active_cell_count()
	var charge := laser.charge
	var ticks_start := Engine.get_physics_frames()

	for i in 30:
		laser.set_fire_state(true, to_rock())
		await wait_physics_frames(1)

	var ticks := Engine.get_physics_frames() - ticks_start

	assert_eq(spawned.size(), 1, "one beam for the whole hold")
	if spawned.is_empty():
		return
	var beam: SuperLaser = spawned[0]
	assert_gt(beam.cells_burned, 0, "burned cells")
	assert_lt(rock.get_active_cell_count(), rock_cells, "rock lost cells")
	assert_lt(laser.charge, charge, "charge drained")
	assert_almost_eq(laser.charge, charge - props.charge_drain * (ticks - 1) / 60.0, props.charge_drain * 2.0 / 60.0, "drains at the charge rate")

	laser.set_fire_state(false, to_rock())
	await wait_physics_frames(2)
	assert_true(not is_instance_valid(beam) or beam.dead, "beam released")
	var charge_after := laser.charge

	await wait_physics_frames(30)
	assert_false(is_instance_valid(beam), "beam faded out")
	assert_eq(laser.charge, charge_after, "no drain after release")
	assert_eq(spawned.size(), 1, "no new beam while released")

	laser.set_fire_state(true, to_rock())
	await wait_physics_frames(3)
	laser.set_fire_state(false, to_rock())
	assert_eq(spawned.size(), 2, "new beam on the next hold")
	assert_true(spawned.size() < 2 or is_instance_valid(spawned[1]), "the new beam is alive")

func test_super_laser_stops_when_charge_runs_out() -> void:
	var laser := weapon_named("SuperLaser")
	var props: BeamWeaponProps = laser.props
	laser.charge = props.charge_drain * 5.0 / 60.0
	var spawned: Array = []
	laser.fired.connect(func(bullet: Node2D): spawned.append(bullet))

	for i in 8:
		laser.set_fire_state(true, to_rock())
		await wait_physics_frames(1)

	assert_eq(spawned.size(), 1)
	assert_eq(laser.charge, 0.0, "charge spent")
	if not spawned.is_empty():
		assert_true(not is_instance_valid(spawned[0]) or spawned[0].dead, "beam went out with the charge")

	for i in 20:
		laser.set_fire_state(true, to_rock())
		await wait_physics_frames(1)
	laser.set_fire_state(false, to_rock())
	assert_eq(spawned.size(), 1, "no beam without charge")

func test_weapon_actions_switch_slots() -> void:
	player.set_process(true)
	var changes := {"count": 0}
	player.weapon_changed.connect(func(_weapon: Weapon): changes["count"] += 1)

	Input.action_press("weapon_2")
	await wait_process_frames(2)
	Input.action_release("weapon_2")
	assert_eq(player.weapon, weapon_named("Minigun"))
	assert_eq(player.weapon.props.resource_path, "res://game/config/weapons/minigun.tres")

	Input.action_press("weapon_5")
	await wait_process_frames(2)
	Input.action_release("weapon_5")
	assert_eq(player.weapon, weapon_named("ForceGun"))

	Input.action_press("next_weapon")
	await wait_process_frames(2)
	Input.action_release("next_weapon")
	assert_eq(player.weapon, weapon_named("LightningBolt"), "q steps to the next slot")

	Input.action_press("weapon_6")
	await wait_process_frames(2)
	Input.action_release("weapon_6")
	assert_eq(player.weapon, weapon_named("LightningBolt"), "already selected, no change")

	player.select_weapon(player.weapons.size() - 1)
	Input.action_press("next_weapon")
	await wait_process_frames(2)
	Input.action_release("next_weapon")
	assert_eq(player.weapon, weapon_named("Cannon"), "wraps to the first slot")
	assert_eq(changes["count"], 5)

func test_switching_releases_the_old_weapon() -> void:
	var cannon := weapon_named("Cannon")
	cannon.set_fire_state(true, to_rock())
	player.select_weapon(1)
	assert_false(cannon.triggered, "the old weapon stops firing")
	assert_eq(player.weapon, weapon_named("Minigun"))

func test_empty_weapon_falls_back_to_cannon() -> void:
	player.set_process(true)
	player.select_weapon(3)
	var missiles := weapon_named("Missiles")
	watch_signals(missiles)
	missiles.ammo = 0
	await wait_process_frames(2)
	assert_signal_emitted(missiles, "emptied")
	assert_eq(player.weapon, weapon_named("Cannon"))
