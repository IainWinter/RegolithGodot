extends GutTest

# the explosion sequence: rides its sprite, sparks and bolts while it
# cooks, then bursts into shrapnel and signals, started through the
# EffectSpawner

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const EFFECTS_SCENE := "res://game/scenes/effects/EffectSpawner.tscn"

var arena: Node2D
var world: RegolithWorld
var effects: EffectSpawner

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
	effects = load(EFFECTS_SCENE).instantiate()
	arena.add_child(effects)
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

func add_rock(at: Vector2) -> RegolithSprite:
	var rock := RegolithSprite.new()
	rock.position = at
	arena.add_child(rock)
	rock.create_blank(Vector2i(32, 32))
	rock.fill_rect(Rect2i(0, 0, 32, 32), Color.GRAY, RegolithSprite.CELL_FILLED, 0)
	return rock

func projectiles() -> Array:
	return get_tree().get_nodes_in_group("projectile")

func test_cook_off_rides_the_sprite_then_bursts() -> void:
	var rock := add_rock(Vector2(0.0, 0.0))
	await wait_physics_frames(2)
	rock.linear_velocity = Vector2(3.0, 0.0)

	var sequence := effects.cook_off(rock, Vector2(10.0, 0.0), 6, 2, 3)
	assert_not_null(sequence)
	sequence.duration = 0.4
	watch_signals(sequence)

	await wait_physics_frames(6)
	assert_lt(sequence.global_position.distance_to(rock.to_global(Vector2(10.0, 0.0))), 0.5, "rides along with the rock")
	assert_false(sequence.done)
	assert_eq(projectiles().size(), 0, "no shrapnel before it goes off")

	var results := {}
	sequence.finished.connect(func(position, items, bias):
		results["position"] = position
		results["items"] = items
		results["bias"] = bias)

	await wait_physics_frames(30)

	assert_signal_emitted(sequence, "exploded")
	assert_true(sequence.done)
	assert_eq(results.get("items"), 3, "item count handed on for the item layer")
	assert_eq(projectiles().size(), 8, "shrapnel of both kinds flew")
	assert_gt(effects.explosions, 0, "the spawner answered the burst")
	assert_gt(sequence.lightning.get_strike_count(), 0, "bolts crackled while cooking")

func test_sequence_detaches_from_a_freed_sprite() -> void:
	var rock := add_rock(Vector2(200.0, 0.0))
	await wait_physics_frames(1)

	var sequence := effects.cook_off(rock, Vector2.ZERO, 1)
	sequence.duration = 5.0
	var at := sequence.global_position
	rock.free()
	await wait_physics_frames(3)

	assert_null(sequence.attached)
	assert_eq(sequence.global_position, at, "stays where the sprite was")
	sequence.queue_free()

func test_cook_off_without_a_scene_returns_null() -> void:
	var bare := EffectSpawner.new()
	arena.add_child(bare)
	assert_null(bare.cook_off(null, Vector2.ZERO, 1))
