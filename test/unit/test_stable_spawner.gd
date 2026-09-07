extends GutTest

# StableSpawner: requests on the SpawnBus spawn once the spot is clear with
# the spawner's materials, group and parent, wait behind a blocker, expire
# after their lifetime, hold while the camera can see the spot, and skip the
# room check when told to

const FIGHTER_SCENE := "res://game/scenes/enemies/EnemyFighter.tscn"
const ROCK_PROPS := preload("res://game/config/rocks/default_rock.tres")
const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")
const ROPE_MATERIAL := preload("res://game/shaders/regolith_rope_material.tres")

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner

func before_each() -> void:
	arena = Node2D.new()
	add_child_autofree(arena)
	world = RegolithWorld.new()
	world.gravity = Vector2.ZERO
	arena.add_child(world)
	spawner = StableSpawner.new()
	spawner.fighter_scene = load(FIGHTER_SCENE)
	spawner.sprite_material = SPRITE_MATERIAL
	spawner.rope_material = ROPE_MATERIAL
	arena.add_child(spawner)
	await wait_physics_frames(1)

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

# a loaded sprite sitting on a spot, in the tree after a step
func add_blocker(units: Vector2) -> RegolithSprite:
	var blocker: RegolithSprite = load(FIGHTER_SCENE).instantiate()
	blocker.position = units * ppu()
	arena.add_child(blocker)
	return blocker

# the node, and where it was and how fast it went the moment it spawned
func watch(request: SpawnRequest) -> Dictionary:
	var seen := {"node": null, "expired": false}
	request.spawned.connect(func(node):
		seen["node"] = node
		seen["position"] = node.global_position
		seen["rotation"] = node.global_rotation
		seen["velocity"] = node.linear_velocity)
	request.expired.connect(func(): seen["expired"] = true)
	return seen

func test_request_spawns_on_a_clear_spot_with_the_spawners_setup() -> void:
	watch_signals(spawner)
	var request := SpawnRequest.enemy(SpawnRequest.Kind.FIGHTER, Vector2(4.0, -3.0), Vector2(1.5, 0.0))
	request.rotation = 0.7
	var seen := watch(request)
	SpawnBus.send(request)

	assert_eq(spawner.pending(), 1, "queued on arrival")
	await wait_physics_frames(2)

	var node: RegolithSprite = seen["node"]
	assert_not_null(node, "spawned once the step ran")
	assert_eq(spawner.pending(), 0)
	assert_signal_emitted(spawner, "spawned")
	if node == null:
		return

	assert_true(node is EnemyFighter)
	assert_eq(node.get_parent(), arena, "under the world's parent")
	assert_true(node.is_in_group("regolith"))
	assert_eq(node.material, SPRITE_MATERIAL)
	assert_eq(node.rope_material, ROPE_MATERIAL)
	assert_almost_eq(seen["position"], Vector2(4.0, -3.0) * ppu(), Vector2.ONE * 0.01)
	assert_almost_eq(seen["rotation"], 0.7, 0.001)
	assert_almost_eq(seen["velocity"], Vector2(1.5, 0.0), Vector2.ONE * 0.01)

func test_request_waits_behind_a_blocker_then_spawns() -> void:
	var spot := Vector2(3.0, 3.0)
	var blocker := add_blocker(spot)
	await wait_physics_frames(2)

	var request := SpawnBus.spawn(SpawnRequest.Kind.FIGHTER, spot)
	var seen := watch(request)
	await wait_physics_frames(5)

	assert_null(seen["node"], "held while the blocker sits there")
	assert_eq(spawner.pending(), 1)

	# the sim owns a dynamic sprite's transform, it moves by velocity
	blocker.linear_velocity = Vector2(500.0, 500.0)
	await wait_physics_frames(5)

	assert_not_null(seen["node"], "spawned once the spot cleared")
	assert_eq(spawner.pending(), 0)

func test_request_expires_after_its_lifetime() -> void:
	var spot := Vector2(3.0, 3.0)
	add_blocker(spot)
	await wait_physics_frames(2)

	watch_signals(spawner)
	var request := SpawnBus.spawn(SpawnRequest.Kind.FIGHTER, spot, Vector2.ZERO, false, 0.1)
	var seen := watch(request)
	await wait_physics_frames(15)

	assert_null(seen["node"])
	assert_true(seen["expired"], "gave up")
	assert_signal_emitted(spawner, "expired")
	assert_eq(spawner.pending(), 0)
	assert_eq(world.get_sprite_count(), 1, "only the blocker is in the world")

func test_ignored_sprites_may_touch_the_spot() -> void:
	var spot := Vector2(3.0, 3.0)
	var blocker := add_blocker(spot)
	await wait_physics_frames(2)

	var request := SpawnRequest.enemy(SpawnRequest.Kind.FIGHTER, spot)
	request.ignore = [blocker]
	var seen := watch(request)
	SpawnBus.send(request)
	await wait_physics_frames(2)

	assert_not_null(seen["node"], "the blocker was allowed")

func test_no_room_check_places_at_once() -> void:
	var spot := Vector2(3.0, 3.0)
	add_blocker(spot)
	await wait_physics_frames(2)

	var request := SpawnRequest.enemy(SpawnRequest.Kind.FIGHTER, spot)
	request.wait_for_room = false
	var seen := watch(request)
	SpawnBus.send(request)
	await wait_physics_frames(2)

	assert_not_null(seen["node"], "placed over the blocker")

func test_offscreen_only_holds_while_the_camera_sees_the_spot() -> void:
	var spot := Vector2(2.0, 1.0)
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = spot * ppu()
	arena.add_child(camera)
	camera.make_current()
	await wait_physics_frames(1)

	var request := SpawnBus.spawn(SpawnRequest.Kind.FIGHTER, spot, Vector2.ZERO, true)
	var seen := watch(request)
	await wait_physics_frames(5)

	assert_null(seen["node"], "held in view")
	assert_true(spawner.camera_sees(Rect2(spot, Vector2.ONE)))

	camera.position = (spot + Vector2(500.0, 500.0)) * ppu()
	await wait_physics_frames(5)

	assert_not_null(seen["node"], "spawned once the camera looked away")

func test_kind_without_a_scene_expires_on_arrival() -> void:
	var request := SpawnRequest.enemy(SpawnRequest.Kind.BOSS_COMPASS, Vector2.ZERO)
	var seen := watch(request)
	SpawnBus.send(request)

	assert_true(seen["expired"])
	assert_eq(spawner.pending(), 0)

func test_rock_request_spawns_a_rock_of_the_asked_size_with_the_velocity() -> void:
	var request := SpawnRequest.rock(ROCK_PROPS, Vector2(6.0, 2.0), Vector2(0.0, -2.0))
	request.chunks = 2
	request.rng = RandomNumberGenerator.new()
	request.rng.seed = 7
	var seen := watch(request)
	SpawnBus.send(request)
	await wait_physics_frames(2)

	var rock: RegolithSprite = seen["node"]
	assert_not_null(rock)
	if rock == null:
		return

	assert_true(rock.is_in_group("regolith"))
	assert_eq(rock.material, SPRITE_MATERIAL)
	assert_eq(rock.get_cell_count(), Vector2i.ONE * 2 * RegolithWorld.CELLS_PER_CHUNK)
	assert_almost_eq(seen["velocity"], Vector2(0.0, -2.0), Vector2.ONE * 0.01)

func test_two_requests_on_one_spot_spawn_one_after_the_other() -> void:
	var spot := Vector2(5.0, 5.0)
	var first := watch(SpawnBus.spawn(SpawnRequest.Kind.FIGHTER, spot))
	var second := watch(SpawnBus.spawn(SpawnRequest.Kind.FIGHTER, spot))
	await wait_physics_frames(3)

	assert_not_null(first["node"], "the first took the spot")
	assert_null(second["node"], "the second waits on the first")
	assert_eq(spawner.pending(), 1)

	first["node"].linear_velocity = Vector2(500.0, 500.0)
	await wait_physics_frames(5)
	assert_not_null(second["node"], "the second got the spot once it was free")
