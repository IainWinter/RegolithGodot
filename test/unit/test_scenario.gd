extends GutTest

# the scenario level layer: the BeltTurret demo inherits Main and adds a
# Scenario with a PlayerStart, a very large turret placement, a belt ring
# and two spawn zones on it. at runtime the Scenario builds one Region
# whose props mirror the zones, sends the placements over the SpawnBus in
# order with rotation and meta, moves the player to its start and clears
# Main's sample sprites. the editor plugin script parses and claims the
# node family, and the gizmo geometry helpers are checked on their own

const DEMO := "res://game/scenes/scenarios/BeltTurret.tscn"
const PLUGIN_CFG := "res://addons/regolith_scenario/plugin.cfg"
const PLUGIN := "res://addons/regolith_scenario/RegolithScenarioPlugin.gd"
const FIGHTER_SCENE := "res://game/scenes/enemies/EnemyFighter.tscn"
const MESSAGE_SCENE := "res://game/scenes/ai/AiMessage.tscn"
const ROCK_PROPS := preload("res://game/config/rocks/default_rock.tres")
const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")

var requests: Array[SpawnRequest] = []
var demo_root: Node2D

func before_each() -> void:
	requests = []
	SpawnBus.spawn_requested.connect(on_requested)

func after_each() -> void:
	SpawnBus.spawn_requested.disconnect(on_requested)

	if demo_root and is_instance_valid(demo_root):
		get_tree().current_scene = null
		demo_root.free()

	demo_root = null

# spawned fighters send couriers over the same bus, those are not the
# scenario's
func on_requested(request: SpawnRequest) -> void:
	if request.kind != SpawnRequest.Kind.MESSAGE:
		requests.append(request)

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func demo() -> Node2D:
	return load(DEMO).instantiate()

# the demo in the tree as the current scene, the way the game runs it.
# SpawnRequest.Kind has no turret yet, so the placement is switched to
# its fallback name here to keep the fallback warning out of the log
func add_demo() -> Node2D:
	demo_root = demo()
	var turret: EnemyPlacement = demo_root.get_node("Scenario/Turret")

	if turret.resolve_kind() < 0:
		turret.kind_name = &""

	get_tree().root.add_child(demo_root)
	get_tree().current_scene = demo_root
	return demo_root

# demo scene

func test_demo_scene_inherits_main_and_holds_the_layout() -> void:
	var main := demo()

	for path in ["RegolithWorld", "RegolithWorld/StableSpawner", "Player", "Camera", "Background", "EffectSpawner", "DebugSpawnPanel"]:
		assert_true(main.has_node(path), "inherits Main's " + path)

	var scenario := main.get_node("Scenario") as Scenario
	assert_not_null(scenario, "Scenario under the inherited Main")
	if scenario == null:
		main.free()
		return

	assert_eq(scenario.belt_zones().size(), 1)
	assert_eq(scenario.spawn_zones().size(), 2)
	assert_eq(scenario.rock_field_zones().size(), 0)
	assert_eq(scenario.zones().size(), 3)
	assert_eq(scenario.placements().size(), 1)
	assert_not_null(scenario.player_start())
	assert_not_null(scenario.rock_props, "belt rocks have props")

	var turret := scenario.placements()[0]
	assert_eq(turret.kind_name, &"turret")
	assert_eq(turret.effective_kind_name(), &"turret")
	assert_eq(turret.scale_cells, 96, "very large")
	assert_eq(turret.gizmo_label(), "turret")
	assert_lt(turret.global_position.distance_to(scenario.global_position), 1.0, "turret at the center")

	var scale: float = main.get_node("RegolithWorld").pixels_per_cell * RegolithWorld.CELLS_PER_CHUNK
	var belt := scenario.belt_zones()[0]
	var turret_radius_units := turret.scale_cells * 0.5 / RegolithWorld.CELLS_PER_CHUNK
	assert_gt(belt.inner_radius, turret_radius_units + 1.0, "belt clears the turret")
	assert_gt(belt.outer_radius, belt.inner_radius)
	assert_gt(belt.rock_count(), 20, "dense belt")
	assert_lt(belt.global_position.distance_to(turret.global_position), 1.0, "belt rings the turret")

	for zone in scenario.spawn_zones():
		var r := zone.global_position.distance_to(belt.global_position) / scale
		assert_between(r, belt.inner_radius, belt.outer_radius, "%s sits on the belt" % zone.name)
		assert_true(SpawnRequest.Kind.FIGHTER in zone.kinds, "fighters come from the belt")

	var start := scenario.player_start()
	assert_gt(start.global_position.distance_to(turret.global_position) / scale, belt.outer_radius, "player starts outside the belt")

	main.free()

func test_runtime_builds_the_region_from_the_zones_and_clears_the_samples() -> void:
	var main := add_demo()
	var scenario: Scenario = main.get_node("Scenario")
	await wait_physics_frames(2)

	assert_true(scenario.is_started)
	assert_not_null(scenario.region, "one Region child does the scatter")
	if scenario.region == null:
		return

	assert_true(scenario.region.is_generated)
	var props := scenario.region.props
	assert_eq(props.asteroid_belts.size(), 1)
	assert_eq(props.spawn_zones.size(), 2)
	assert_eq(props.rock_fields.size(), 0)
	assert_eq(props.one_time_spawns.size(), 0, "placements go over the bus themselves")

	var zone := scenario.belt_zones()[0]
	var belt := props.asteroid_belts[0]
	assert_almost_eq(belt.min_radius, zone.inner_radius, 0.001)
	assert_almost_eq(belt.max_radius, zone.outer_radius, 0.001)
	assert_eq(belt.count, zone.rock_count(), "density maps to the count")
	assert_almost_eq(belt.angular_speed, zone.angular_speed(), 0.0001)
	assert_eq(belt.min_chunks, zone.min_chunks)
	assert_eq(belt.max_chunks, zone.max_chunks)
	assert_eq(belt.seed, zone.seed)
	assert_not_null(belt.rock_props)
	assert_ne(belt.rock_props, ROCK_PROPS, "the zone works on a copy of the shared props")
	assert_almost_eq(belt.position, (zone.global_position - scenario.global_position) / ppu(), Vector2.ONE * 0.001)

	for i in 2:
		var spawn := scenario.spawn_zones()[i]
		var region_zone := props.spawn_zones[i]
		assert_eq(region_zone.max_alive, spawn.max_alive)
		assert_almost_eq(region_zone.respawn_seconds, spawn.interval, 0.001)
		assert_eq(region_zone.kinds, spawn.kinds)
		assert_almost_eq(region_zone.half_size, spawn.size * 0.5, Vector2.ONE * 0.001)
		assert_almost_eq(region_zone.position, (spawn.global_position - scenario.global_position) / ppu(), Vector2.ONE * 0.001)

	var rocks := requests.filter(func(r: SpawnRequest): return r.is_rock())
	assert_eq(rocks.size(), belt.count, "every belt rock was asked for")
	var center := scenario.global_position / ppu()

	for rock in rocks:
		assert_between(rock.position.distance_to(center), belt.min_radius - 0.01, belt.max_radius + 0.01, "on the ring")

	assert_eq(scenario.requests.size(), 1, "one placement request")
	assert_eq(requests.size(), belt.count + 4 + 1, "rocks, two zones of two fighters, the turret placement")

	for sample in ["Slab", "Rock", "Rock2", "Slab2"]:
		assert_null(main.get_node_or_null(sample), "Main's sample %s cleared" % sample)

	assert_not_null(main.get_node_or_null("Player"), "the player stays")

func test_player_start_moves_the_player_before_it_loads() -> void:
	var main := add_demo()
	var start: PlayerStart = main.get_node("Scenario/PlayerStart")
	var player: RegolithSprite = main.get_node("Player")
	await wait_physics_frames(3)

	assert_true(player.is_loaded(), "player is in the sim")
	assert_lt(player.global_position.distance_to(start.global_position), 2.0, "player stands on its start")
	assert_almost_eq(player.global_rotation, start.global_rotation, 0.01)

# placements

func test_placements_go_over_the_bus_in_order_with_rotation_and_meta() -> void:
	var arena := Node2D.new()
	add_child_autofree(arena)
	var world := RegolithWorld.new()
	world.gravity = Vector2.ZERO
	arena.add_child(world)
	var spawner := StableSpawner.new()
	spawner.fighter_scene = load(FIGHTER_SCENE)
	spawner.message_scene = load(MESSAGE_SCENE)
	spawner.sprite_material = SPRITE_MATERIAL
	arena.add_child(spawner)

	var scenario := Scenario.new()
	scenario.auto_start = false
	scenario.position = Vector2(2.0, 1.0) * ppu()

	var first := EnemyPlacement.new()
	first.name = "First"
	first.kind = SpawnRequest.Kind.FIGHTER
	first.position = Vector2(3.0, 0.0) * ppu()
	first.rotation = 0.5
	first.scale_cells = 12
	scenario.add_child(first)

	var second := EnemyPlacement.new()
	second.name = "Second"
	second.kind = SpawnRequest.Kind.BASE
	second.kind_name = &"fighter"
	second.position = Vector2(-3.0, 0.0) * ppu()
	second.rotation = -1.0
	second.scale_cells = 96
	second.label = "turret"
	scenario.add_child(second)

	arena.add_child(scenario)
	watch_signals(scenario)
	scenario.start()

	assert_true(scenario.is_started)
	assert_signal_emitted(scenario, "started")
	assert_eq(requests.size(), 2, "both placements on the bus")
	if requests.size() < 2:
		return

	assert_eq(requests[0], scenario.requests[0], "in child order")
	assert_eq(requests[1], scenario.requests[1])
	assert_eq(requests[0].kind, SpawnRequest.Kind.FIGHTER)
	assert_eq(requests[1].kind, SpawnRequest.Kind.FIGHTER, "kind_name wins over kind")
	assert_almost_eq(requests[0].position, Vector2(5.0, 1.0), Vector2.ONE * 0.001, "world units")
	assert_almost_eq(requests[1].position, Vector2(-1.0, 1.0), Vector2.ONE * 0.001)
	assert_almost_eq(requests[0].rotation, 0.5, 0.001)
	assert_almost_eq(requests[1].rotation, -1.0, 0.001)
	assert_false(requests[0].wait_for_room, "placements land where they are")
	assert_eq(requests[0].get_meta(EnemyPlacement.META_SCALE_CELLS), 12)
	assert_eq(requests[1].get_meta(EnemyPlacement.META_SCALE_CELLS), 96)
	assert_eq(requests[0].get_meta(EnemyPlacement.META_KIND_NAME), &"fighter")
	assert_eq(requests[1].get_meta(EnemyPlacement.META_KIND_NAME), &"fighter")
	assert_eq(requests[0].get_meta(EnemyPlacement.META_PLACEMENT), "First")

	await wait_physics_frames(2)

	assert_signal_emitted(scenario, "placed")
	assert_not_null(first.node, "placement keeps its node")
	if first.node == null:
		return

	assert_true(first.node is EnemyFighter)
	assert_eq(first.node.get_meta(EnemyPlacement.META_SCALE_CELLS), 12, "meta copied onto the node")
	assert_almost_eq(first.node.global_rotation, 0.5, 0.01)
	assert_lt(first.node.global_position.distance_to(Vector2(5.0, 1.0) * ppu()), 1.0)

func test_kind_name_resolves_against_the_enum_and_names_the_scene() -> void:
	var placement := EnemyPlacement.new()
	placement.kind = SpawnRequest.Kind.BASE
	assert_eq(placement.resolve_kind(), SpawnRequest.Kind.BASE, "no name uses kind")
	assert_eq(placement.effective_kind_name(), &"base")
	assert_eq(placement.scene_path(), "res://game/scenes/enemies/EnemyBase.tscn")

	placement.kind_name = &"boss_compass"
	assert_eq(placement.resolve_kind(), SpawnRequest.Kind.BOSS_COMPASS, "names resolve case free")
	assert_eq(placement.scene_path(), "res://game/scenes/enemies/EnemyBossCompass.tscn")

	placement.kind_name = &"turret"
	assert_eq(placement.scene_path(), "res://game/scenes/enemies/EnemyTurret.tscn")

	var kinds: Dictionary = SpawnRequest.Kind

	if kinds.has("TURRET"):
		assert_eq(placement.resolve_kind(), kinds["TURRET"], "the enum grew a turret")
	else:
		assert_eq(placement.resolve_kind(), -1, "no turret kind yet, make_request warns and falls back to kind")

	placement.free()

func test_silhouette_reads_the_scene_texture_without_instancing() -> void:
	var placement := EnemyPlacement.new()
	placement.kind = SpawnRequest.Kind.FIGHTER
	var texture := placement.silhouette_texture()
	assert_not_null(texture, "fighter scene carries a texture")
	if texture:
		assert_eq(texture.resource_path, "res://game/images/sprites/fighter.png")

	assert_eq(placement.silhouette_texture(), texture, "cached")

	placement.kind_name = &"no_such_enemy"
	assert_null(placement.silhouette_texture(), "no scene, the gizmo draws a circle")
	placement.free()

# zone mappings

func test_belt_zone_maps_density_and_direction_onto_a_region_belt() -> void:
	var zone := AsteroidBeltZone.new()
	zone.inner_radius = 8.0
	zone.outer_radius = 14.0
	zone.density = 0.08
	zone.min_chunks = 2
	zone.max_chunks = 1
	zone.clockwise = false
	zone.orbit_speed = 0.3
	zone.seed = 9

	assert_almost_eq(zone.ring_area(), PI * (14.0 * 14.0 - 8.0 * 8.0), 0.001)
	assert_eq(zone.rock_count(), int(round(0.08 * zone.ring_area())))
	assert_almost_eq(zone.angular_speed(), -0.3, 0.0001, "counterclockwise is negative")

	var belt := zone.to_belt(Vector2(1.0, 2.0), ROCK_PROPS)
	assert_eq(belt.position, Vector2(1.0, 2.0))
	assert_almost_eq(belt.min_radius, 8.0, 0.001)
	assert_almost_eq(belt.max_radius, 14.0, 0.001)
	assert_eq(belt.min_chunks, 2)
	assert_eq(belt.max_chunks, 2, "max never under min")
	assert_eq(belt.count, zone.rock_count())
	assert_eq(belt.seed, 9)
	assert_ne(belt.rock_props, ROCK_PROPS, "a copy")
	assert_almost_eq(belt.rock_props.ore_chance, ROCK_PROPS.ore_chance, 0.0001, "negative keeps the props' chance")
	assert_eq(belt.rock_props.min_chunks, 2)

	zone.ore_chance = 0.5
	assert_almost_eq(zone.to_belt(Vector2.ZERO, ROCK_PROPS).rock_props.ore_chance, 0.5, 0.0001)
	assert_null(zone.to_belt(Vector2.ZERO, null).rock_props, "no props anywhere")

	zone.inner_radius = 20.0
	var flipped := zone.to_belt(Vector2.ZERO, ROCK_PROPS)
	assert_almost_eq(flipped.min_radius, 14.0, 0.001, "radii sort themselves")
	assert_almost_eq(flipped.max_radius, 20.0, 0.001)
	zone.free()

func test_rock_field_and_spawn_zones_map_onto_region_resources() -> void:
	var field := RockFieldZone.new()
	field.size = Vector2(10.0, 4.0)
	field.density = 0.5
	field.seed = 3
	assert_eq(field.rock_count(), 20)
	var region_field := field.to_rock_field(Vector2(-5.0, 0.0), ROCK_PROPS)
	assert_eq(region_field.position, Vector2(-5.0, 0.0))
	assert_eq(region_field.size, Vector2(10.0, 4.0))
	assert_eq(region_field.min_count, 20)
	assert_eq(region_field.max_count, 20)
	assert_eq(region_field.seed, 3)
	assert_not_null(region_field.rock_props)
	field.free()

	var zone := SpawnZone.new()
	zone.shape = SpawnZone.Shape.RECT
	zone.size = Vector2(8.0, 4.0)
	zone.rotation = 0.3
	zone.kinds = [SpawnRequest.Kind.FIGHTER, SpawnRequest.Kind.BOMB]
	zone.weights = [3.0, 1.0]
	zone.max_alive = 4
	zone.interval = 2.5
	zone.burst_count = 0
	var rect := zone.to_spawn_zone(Vector2(7.0, 7.0))
	assert_eq(rect.position, Vector2(7.0, 7.0))
	assert_eq(rect.half_size, Vector2(4.0, 2.0))
	assert_almost_eq(rect.angle, 0.3, 0.001)
	assert_eq(rect.kinds, zone.kinds)
	assert_eq(rect.weights, zone.weights)
	assert_eq(rect.max_alive, 4)
	assert_almost_eq(rect.respawn_seconds, 2.5, 0.001)
	assert_eq(rect.burst_count, 1, "at least one per burst")
	assert_true(rect.endless)

	zone.shape = SpawnZone.Shape.CIRCLE
	zone.radius = 3.0
	var circle := zone.to_spawn_zone(Vector2.ZERO)
	assert_eq(circle.half_size, Vector2(3.0, 3.0), "the circle's bounding box")
	assert_almost_eq(circle.angle, 0.0, 0.001)
	zone.free()

func test_pixels_per_unit_follows_the_scenario_in_the_game() -> void:
	var scenario := Scenario.new()
	var zone := AsteroidBeltZone.new()
	scenario.add_child(zone)
	var outside := Node2D.new()
	assert_eq(Scenario.scenario_of(zone), scenario)
	assert_null(Scenario.scenario_of(outside), "no Scenario above it")
	outside.free()
	assert_almost_eq(Scenario.pixels_per_unit_of(zone), RegolithWorld.pixels_per_unit(), 0.001, "the active world's scale at runtime")
	assert_eq(Scenario.DEFAULT_PIXELS_PER_UNIT, 2.0 * RegolithWorld.CELLS_PER_CHUNK, "Main runs 2 pixels per cell")
	scenario.free()

# editor plugin

func test_plugin_script_parses_and_claims_the_scenario_classes() -> void:
	var script = load(PLUGIN)
	assert_true(script is GDScript, "plugin script loads")
	assert_true(script.can_instantiate(), "plugin script compiles")
	assert_eq(script.get_instance_base_type(), &"EditorPlugin")

	var methods := {}
	for m in script.get_script_method_list():
		methods[m["name"]] = true
	for wanted in ["_handles", "_edit", "_make_visible", "_forward_canvas_draw_over_viewport", "_forward_canvas_force_draw_over_viewport", "_forward_canvas_gui_input", "_enter_tree", "_exit_tree", "handles_of", "handle_value", "commit_drag", "_on_add", "make_node"]:
		assert_true(methods.has(wanted), "plugin implements " + wanted)

	for node in [Scenario.new(), AsteroidBeltZone.new(), RockFieldZone.new(), SpawnZone.new(), PlayerStart.new(), EnemyPlacement.new()]:
		assert_true(script.handles_node(node), "handles " + node.get_script().get_global_name())
		node.free()

	var plain := Node2D.new()
	assert_false(script.handles_node(plain), "leaves other nodes to the editor")
	plain.free()
	assert_false(script.handles_node(RegionProps.new()))

	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PLUGIN_CFG), OK)
	assert_eq(cfg.get_value("plugin", "script"), "RegolithScenarioPlugin.gd")

	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	assert_true(PLUGIN_CFG in enabled, "plugin is enabled in project.godot")

# gizmo geometry

func test_ring_handles_hit_test_and_radius_from_drag() -> void:
	var center := Vector2(100.0, 50.0)
	var handles := ScenarioGizmos.ring_handles(center, 20.0)
	assert_eq(handles.size(), 4)
	assert_eq(handles[0], Vector2(120.0, 50.0), "right")
	assert_eq(handles[1], Vector2(100.0, 70.0), "down")
	assert_eq(handles[2], Vector2(80.0, 50.0), "left")
	assert_eq(handles[3], Vector2(100.0, 30.0), "up")

	assert_eq(ScenarioGizmos.hit_handle(Vector2(121.0, 52.0), handles), 0, "inside the handle radius")
	assert_eq(ScenarioGizmos.hit_handle(Vector2(100.0, 33.0), handles, 3.0), 3, "custom radius")
	assert_eq(ScenarioGizmos.hit_handle(Vector2(100.0, 50.0), handles), -1, "the center hits nothing")
	assert_eq(ScenarioGizmos.hit_handle(Vector2(120.0, 50.0 + ScenarioGizmos.HANDLE_RADIUS + 0.5), handles), -1, "just outside")

	assert_almost_eq(ScenarioGizmos.radius_from_drag(center, Vector2(100.0, 90.0)), 40.0, 0.001)
	assert_almost_eq(ScenarioGizmos.radius_from_drag(center, Vector2(130.0, 90.0)), 50.0, 0.001, "any direction")

func test_rect_handles_and_half_from_drag() -> void:
	var center := Vector2.ZERO
	var half := Vector2(10.0, 5.0)
	var handles := ScenarioGizmos.rect_handles(center, half)
	assert_eq(handles.size(), 8)
	assert_eq(handles[0], Vector2(-10.0, -5.0), "top left corner")
	assert_eq(handles[2], Vector2(10.0, 5.0), "bottom right corner")
	assert_eq(handles[4], Vector2(0.0, -5.0), "top edge")
	assert_eq(handles[5], Vector2(10.0, 0.0), "right edge")

	assert_eq(ScenarioGizmos.half_from_drag(center, 0.0, 2, Vector2(20.0, 8.0), half), Vector2(20.0, 8.0), "corner sets both")
	assert_eq(ScenarioGizmos.half_from_drag(center, 0.0, 0, Vector2(-15.0, -2.0), half), Vector2(15.0, 2.0), "mirrored corner")
	assert_eq(ScenarioGizmos.half_from_drag(center, 0.0, 5, Vector2(30.0, 100.0), half), Vector2(30.0, 5.0), "edge keeps the other axis")
	assert_eq(ScenarioGizmos.half_from_drag(center, 0.0, 6, Vector2(100.0, -7.0), half), Vector2(10.0, 7.0))
	assert_eq(ScenarioGizmos.half_from_drag(center, 0.0, 9, Vector2(1.0, 1.0), half), half, "unknown handle changes nothing")

	var rotated := ScenarioGizmos.half_from_drag(center, PI * 0.5, 5, Vector2(0.0, 30.0), half)
	assert_almost_eq(rotated, Vector2(30.0, 5.0), Vector2.ONE * 0.001, "drag is read in the box frame")

	var corners := ScenarioGizmos.rect_corners(Vector2(1.0, 1.0), Vector2(2.0, 1.0))
	assert_eq(corners.size(), 4)
	assert_eq(corners[0], Vector2(-1.0, 0.0))
	assert_eq(corners[2], Vector2(3.0, 2.0))

func test_arrow_art_rect_fit_scale_and_pascal_case() -> void:
	var arrow := ScenarioGizmos.arrow_points(Vector2.ZERO, 0.0, 10.0)
	assert_eq(arrow.size(), 3)
	assert_almost_eq(arrow[0], Vector2(10.0, 0.0), Vector2.ONE * 0.001, "tip")
	assert_lt(arrow[1].x, 10.0, "barbs sit behind the tip")
	assert_lt(arrow[2].x, 10.0)
	assert_almost_eq(arrow[1].y, -arrow[2].y, 0.001, "barbs mirror")

	var rect := ScenarioGizmos.padded_art_rect(Vector2(13.0, 13.0), 2.0)
	assert_eq(rect.position, Vector2(-32.0, -32.0), "origin is the padded chunk grid center")
	assert_eq(rect.size, Vector2(26.0, 26.0), "art at the grid's top left")
	var wide := ScenarioGizmos.padded_art_rect(Vector2(64.0, 40.0), 2.0)
	assert_eq(wide.position, Vector2(-64.0, -64.0))
	assert_eq(wide.size, Vector2(128.0, 80.0))

	assert_almost_eq(ScenarioGizmos.fit_scale(Vector2(48.0, 24.0), 96), 2.0, 0.001)
	assert_almost_eq(ScenarioGizmos.fit_scale(Vector2(48.0, 24.0), 0), 1.0, 0.001, "zero keeps the art size")

	assert_eq(ScenarioGizmos.pascal_case("boss_compass"), "BossCompass")
	assert_eq(ScenarioGizmos.pascal_case("turret"), "Turret")
	assert_eq(ScenarioGizmos.pascal_case("FIGHTER"), "Fighter")
