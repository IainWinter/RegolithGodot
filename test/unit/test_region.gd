extends GutTest

# Region: one time spawns land at once, zones fill to their count, belts
# scatter seeded rocks that ride an OrbitMover once placed, rock fields
# fill a box. everything goes through the SpawnBus and StableSpawner, so
# the requests are read off the bus

const FIGHTER_SCENE := "res://game/scenes/enemies/EnemyFighter.tscn"
const BOMB_SCENE := "res://game/scenes/enemies/EnemyBomb.tscn"
const ROCK_PROPS := preload("res://game/config/rocks/default_rock.tres")
const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")
const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const DEFAULT_REGION := preload("res://game/config/regions/default.tres")

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner
var requests: Array[SpawnRequest] = []

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	world = RegolithWorld.new()
	world.gravity = Vector2.ZERO
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)
	spawner = StableSpawner.new()
	spawner.fighter_scene = load(FIGHTER_SCENE)
	spawner.bomb_scene = load(BOMB_SCENE)
	spawner.sprite_material = SPRITE_MATERIAL
	arena.add_child(spawner)
	requests = []
	SpawnBus.spawn_requested.connect(on_requested)
	await wait_physics_frames(1)

func after_each() -> void:
	SpawnBus.spawn_requested.disconnect(on_requested)
	get_tree().current_scene = null
	arena.free()

# the region's own requests: spawned fighters send couriers over the same
# bus once they are up, those are not the region's
func on_requested(request: SpawnRequest) -> void:
	if request.kind != SpawnRequest.Kind.MESSAGE:
		requests.append(request)

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func add_region(props: RegionProps, at := Vector2.ZERO) -> Region:
	var region := Region.new()
	region.props = props
	region.position = at * ppu()
	arena.add_child(region)
	return region

func rock_props() -> RockProps:
	var props: RockProps = ROCK_PROPS.duplicate()
	props.min_chunks = 1
	props.max_chunks = 1
	props.ore_chance = 0.0
	return props

func test_one_time_spawn_lands_at_its_offset() -> void:
	var props := RegionProps.new()
	var spawn := RegionSpawn.new()
	spawn.kind = SpawnRequest.Kind.FIGHTER
	spawn.position = Vector2(3.0, -2.0)
	spawn.rotation = 0.5
	props.one_time_spawns = [spawn]

	var region := add_region(props, Vector2(10.0, 10.0))
	watch_signals(region)
	await wait_physics_frames(3)

	assert_true(region.is_generated)
	assert_signal_emitted(region, "generated")
	assert_eq(region.spawned.size(), 1, "one fighter spawned")
	var fighter: RegolithSprite = region.spawned[0]
	assert_lt(fighter.global_position.distance_to(Vector2(13.0, 8.0) * ppu()), 1.0)
	assert_almost_eq(fighter.global_rotation, 0.5, 0.01)

func test_zone_fills_to_its_count_with_bursts() -> void:
	var props := RegionProps.new()
	var zone := RegionSpawnZone.new()
	zone.kinds = [SpawnRequest.Kind.FIGHTER, SpawnRequest.Kind.BOMB]
	zone.weights = [1.0, 0.0]
	zone.half_size = Vector2(6.0, 6.0)
	zone.max_alive = 3
	zone.burst_count = 2
	props.spawn_zones = [zone]

	add_region(props, Vector2(40.0, 0.0))
	await wait_physics_frames(2)

	assert_eq(requests.size(), 3, "count caps the bursts")

	for request in requests:
		assert_eq(request.kind, SpawnRequest.Kind.FIGHTER, "zero weight kind never picked")
		assert_lt(request.position.distance_to(Vector2(40.0, 0.0)), 6.0 * sqrt(2.0) + 0.01, "inside the zone box")

	zone.endless = false
	zone.spawn_count = 5
	assert_eq(zone.count(), 5)

func test_belt_rocks_orbit_their_center() -> void:
	var props := RegionProps.new()
	var belt := RegionAsteroidBelt.new()
	belt.rock_props = rock_props()
	belt.count = 4
	belt.min_radius = 8.0
	belt.max_radius = 10.0
	belt.angular_speed = 1.0
	belt.seed = 7
	props.asteroid_belts = [belt]

	var region := add_region(props, Vector2(0.0, 80.0))
	await wait_physics_frames(2)

	assert_eq(requests.size(), 4)

	for request in requests:
		assert_true(request.is_rock())
		var r := request.position.distance_to(Vector2(0.0, 80.0))
		assert_between(r, 7.99, 10.01, "on the ring")

	for i in 60:
		await wait_physics_frames(1)
		if region.spawned.size() == 4:
			break

	assert_eq(region.spawned.size(), 4, "every belt rock placed")

	var rock: RegolithSprite = region.spawned[0]
	var mover := rock.get_node_or_null("OrbitMover") as OrbitMover
	assert_not_null(mover, "rock rides an OrbitMover")
	if mover == null:
		return

	assert_eq(mover.center, Vector2(0.0, 80.0), "around the belt center")
	assert_almost_eq(mover.angular_speed, 1.0, 0.001)
	assert_false(rock.dynamic, "orbiting rock is a kinematic rail")
	assert_true(world.sprite_split.is_connected(OrbitMover.release_piece), "one split watcher for the belt")
	var angle_before := mover.angle
	var start := rock.global_position

	await wait_physics_frames(30)

	assert_gt(mover.angle, angle_before, "orbit advances")
	assert_gt(rock.global_position.distance_to(start), 1.0, "rock moved along the ring")
	var radius_now := rock.global_position.distance_to(Vector2(0.0, 80.0) * ppu()) / ppu()
	assert_almost_eq(radius_now, mover.radius, 0.05, "rock keeps its orbit radius")

func test_belt_layout_repeats_from_its_seed() -> void:
	var props := RegionProps.new()
	var belt := RegionAsteroidBelt.new()
	belt.rock_props = rock_props()
	belt.count = 3
	belt.seed = 99
	props.asteroid_belts = [belt]

	add_region(props, Vector2(0.0, 200.0))
	await wait_physics_frames(1)
	add_region(props, Vector2(0.0, 200.0))
	await wait_physics_frames(1)

	assert_eq(requests.size(), 6)
	if requests.size() < 6:
		return

	for i in 3:
		assert_eq(requests[i].position, requests[3 + i].position)
		assert_eq(requests[i].chunks, requests[3 + i].chunks)

func test_rock_field_fills_its_box() -> void:
	var props := RegionProps.new()
	var field := RegionRockField.new()
	field.rock_props = rock_props()
	field.size = Vector2(10.0, 4.0)
	field.min_count = 3
	field.max_count = 3
	props.rock_fields = [field]

	add_region(props, Vector2(-60.0, 0.0))
	await wait_physics_frames(2)

	assert_eq(requests.size(), 3)

	for request in requests:
		assert_true(request.is_rock())
		assert_lt(absf(request.position.x + 60.0), 5.01)
		assert_lt(absf(request.position.y), 2.01)

func test_default_region_matches_the_original_layout() -> void:
	assert_eq(DEFAULT_REGION.one_time_spawns.size(), 1)
	assert_eq(DEFAULT_REGION.one_time_spawns[0].kind, SpawnRequest.Kind.BOSS_COMPASS)
	assert_lt(DEFAULT_REGION.one_time_spawns[0].position.distance_to(Vector2(0.3274, 5.34023)), 0.001)
