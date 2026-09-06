extends GutTest

# Main scene boots: background builds its layers, sprites register with
# the world, dynamic rocks fall

var main: Node2D

func before_each() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(main)

func test_background_builds_layers() -> void:
	await wait_physics_frames(3)
	var background: Node2D = main.get_node("Background")
	assert_gt(background.get_child_count(), 0)
	var world_index := main.get_node("RegolithWorld").get_index()
	assert_lt(background.get_index(), world_index, "background draws under the sprites")

func test_all_sprites_register_with_world() -> void:
	await wait_physics_frames(3)
	var world: RegolithWorld = main.get_node("RegolithWorld")
	var expected := 0
	for child in main.get_children():
		if child is RegolithSprite:
			expected += 1
	assert_eq(world.get_sprite_count(), expected)

func test_world_has_no_gravity_so_rock_floats() -> void:
	var rock: RegolithSprite = main.get_node("Rock")
	var start := rock.global_position
	await wait_physics_frames(60)
	assert_eq(rock.global_position, start)

func test_dynamic_rock_moves_with_velocity() -> void:
	var rock: RegolithSprite = main.get_node("Rock")
	var start := rock.global_position
	rock.linear_velocity = Vector2(5, 0)
	await wait_physics_frames(60)
	assert_gt(rock.global_position.x, start.x + 20.0, "rock drifted right")

func test_static_slab_ignores_velocity() -> void:
	var slab: RegolithSprite = main.get_node("Slab")
	var start := slab.global_position
	slab.linear_velocity = Vector2(5, 0)
	await wait_physics_frames(30)
	assert_eq(slab.global_position, start)
