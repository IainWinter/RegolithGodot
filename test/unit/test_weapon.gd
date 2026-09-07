extends GutTest

# Weapon and Bullet in the main scene: firing at the rock spawns bullets,
# bullets hit cells and remove them, world queries see the rock

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
	await wait_physics_frames(3)

func after_each() -> void:
	main.free()

func test_world_queries_find_rock() -> void:
	var hit: Dictionary = world.ray_cast(player.global_position, rock.global_position, player)
	assert_false(hit.is_empty(), "ray from player reaches something")
	assert_gt(world.query_segment(player.global_position, rock.global_position).size(), 0)
	assert_true(rock in world.query_rect(Rect2(rock.global_position - Vector2(10, 10), Vector2(20, 20))))

func test_firing_hits_rock_and_removes_cells() -> void:
	var counts := {"bullets": 0, "hits": 0}
	player.weapon.fired.connect(func(bullet: Node2D):
		counts["bullets"] += 1
		bullet.hit_cell.connect(func(_sprite, _cell, _position): counts["hits"] += 1))

	var rock_cells := rock.get_active_cell_count()
	rock.linear_velocity = Vector2(0.5, 0.0)
	rock.angular_velocity = 0.5
	var to_rock := rock.global_position - player.global_position

	for i in 120:
		player.weapon.set_fire_state(true, to_rock)
		await wait_physics_frames(1)
	player.weapon.set_fire_state(false, to_rock)
	await wait_physics_frames(60)

	assert_gt(counts["bullets"], 0, "bullets fired")
	assert_gt(counts["hits"], 0, "cells hit")
	assert_lt(rock.get_active_cell_count(), rock_cells, "rock lost cells")

func test_slow_bullets_with_trail_still_hit() -> void:
	var slow: WeaponProps = player.weapon.props.duplicate()
	slow.speed = 4.0
	slow.cell_life = 40
	slow.trail_length = 2.0
	slow.delay_cooldown = 0.25
	player.weapon.props = slow

	var rock_cells := rock.get_active_cell_count()
	var to_rock := rock.global_position - player.global_position
	for i in 50:
		player.weapon.set_fire_state(i < 20, to_rock)
		await wait_physics_frames(1)
	await wait_physics_frames(90)

	assert_lt(rock.get_active_cell_count(), rock_cells)

func test_embedded_bullet_rides_fast_sprite() -> void:
	var slow: WeaponProps = player.weapon.props.duplicate()
	slow.speed = 1.0
	slow.cell_life = 60
	slow.lifetime = 10.0
	slow.delay_cooldown = 0.05
	slow.inaccuracy_angle = 0.0
	slow.inaccuracy_tangent = 0.0
	slow.rotation_factor = 0.0
	slow.damage = 0
	slow.damage_ratio = 0.0
	player.weapon.props = slow

	player.set_process(false)

	var stuck: Array = []
	player.weapon.fired.connect(func(bullet: Node2D):
		bullet.hit_cell.connect(func(sprite, _cell, _position):
			if sprite == rock and stuck.is_empty():
				stuck.append(bullet)))

	rock.linear_velocity = Vector2(6.0, -8.0)
	await wait_physics_frames(60)

	var to_rock := rock.global_position - player.global_position
	rock.linear_velocity = -to_rock.normalized() * 10.0

	player.weapon.set_fire_state(true, to_rock)
	await wait_physics_frames(1)
	player.weapon.set_fire_state(false, to_rock)
	player.desired_velocity = Vector2(to_rock.y, -to_rock.x).normalized() * player.speed

	for i in 240:
		if not stuck.is_empty():
			break
		await wait_physics_frames(1)

	assert_false(stuck.is_empty(), "the bullet lodged in the rock")
	if stuck.is_empty():
		return

	var bullet: Bullet = stuck[0]

	var pixels_per_unit := RegolithWorld.pixels_per_unit()
	var own_step := slow.speed * pixels_per_unit / 60.0
	var cell := pixels_per_unit / RegolithWorld.CELLS_PER_CHUNK
	var frames := 12
	var bullet_start := bullet.global_position
	var rock_start := rock.global_transform
	var ticks_start := Engine.get_physics_frames()
	var embedded_frames := 0

	for i in frames:
		if bullet.embedded_sprite == rock:
			embedded_frames += 1

		var bullet_before := bullet.global_position
		var rock_before := rock.global_transform
		var ticks_before := Engine.get_physics_frames()
		await wait_physics_frames(1)
		var ticks := Engine.get_physics_frames() - ticks_before

		assert_true(is_instance_valid(bullet) and not bullet.dead, "bullet still alive at frame %d" % i)
		if not is_instance_valid(bullet) or bullet.dead:
			return

		var carried := rock.global_transform * (rock_before.affine_inverse() * bullet_before) - bullet_before
		var bullet_delta := bullet.global_position - bullet_before
		var slack := (own_step + cell) * ticks
		assert_gt(carried.length(), slack * 2.0, "rock outruns the bullet at frame %d" % i)
		assert_almost_eq(bullet_delta, carried, Vector2.ONE * slack, "bullet moves with the rock at frame %d" % i)

	assert_gt(embedded_frames, 0, "bullet was embedded in the rock during the run")

	var slack_total := (own_step + cell) * (Engine.get_physics_frames() - ticks_start)
	var carried_total := rock.global_transform * (rock_start.affine_inverse() * bullet_start) - bullet_start
	assert_gt(carried_total.length(), slack_total * 2.0, "rock outran the bullet over the run")
	assert_almost_eq(bullet.global_position - bullet_start, carried_total, Vector2.ONE * slack_total, "bullet carried with the rock over the run")
