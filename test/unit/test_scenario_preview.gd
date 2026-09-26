extends GutTest

# the scenario editor preview: Region.plan runs the same draws as
# Region.generate so the planned rocks are the spawned ones, Scenario.plan
# wraps it over the zones, the ScenarioPreview child exists only when the
# editor (or a test) asks for it and caches one texture per planned rock
# until the plan drops it, zone setters and reroll_seed replan once,
# deferred, and the plugin toolbar carries the Preview toggle and the
# Reroll seed button

const PLUGIN := "res://addons/regolith_scenario/RegolithScenarioPlugin.gd"
const DEMO := "res://game/scenes/scenarios/BeltTurret.tscn"
const ROCK_PROPS := preload("res://game/config/rocks/default_rock.tres")
const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")
const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var requests: Array[SpawnRequest] = []

func before_each() -> void:
	requests = []
	SpawnBus.spawn_requested.connect(on_requested)

func after_each() -> void:
	SpawnBus.spawn_requested.disconnect(on_requested)
	get_tree().current_scene = null

func on_requested(request: SpawnRequest) -> void:
	if request.kind != SpawnRequest.Kind.MESSAGE:
		requests.append(request)

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

# a Scenario with a sparse belt and a sparse rock field, in the tree, not
# started. counts are small and the seeds chosen so no two rocks overlap
# (the spawner would hold one) and the test is quick
func make_scenario(seed_belt := 5, seed_field := 34) -> Scenario:
	var scenario := Scenario.new()
	scenario.auto_start = false
	scenario.clear_scene_sprites = false
	scenario.rock_props = ROCK_PROPS
	scenario.position = Vector2(4.0, -2.0) * ppu()

	var belt := AsteroidBeltZone.new()
	belt.name = "Belt"
	belt.inner_radius = 8.0
	belt.outer_radius = 12.0
	# four rocks on a wide ring so none blocks another
	belt.density = 4.0 / belt.ring_area()
	belt.min_chunks = 1
	belt.max_chunks = 2
	belt.seed = seed_belt
	scenario.add_child(belt)

	var field := RockFieldZone.new()
	field.name = "Field"
	field.position = Vector2(40.0, 0.0) * ppu()
	field.size = Vector2(30.0, 30.0)
	field.density = 3.0 / field.area()
	field.min_chunks = 1
	field.max_chunks = 3
	field.seed = seed_field
	scenario.add_child(field)

	var zone := SpawnZone.new()
	zone.name = "Spawn"
	zone.position = Vector2(0.0, 20.0) * ppu()
	zone.kinds = [SpawnRequest.Kind.FIGHTER]
	zone.max_alive = 2
	scenario.add_child(zone)

	return scenario

func rocks_of(items: Array[Dictionary]) -> Array[Dictionary]:
	return items.filter(func(item: Dictionary) -> bool: return item["type"] == Region.PLAN_ROCK)

func enemies_of(items: Array[Dictionary]) -> Array[Dictionary]:
	return items.filter(func(item: Dictionary) -> bool: return item["type"] == Region.PLAN_ENEMY)

# plan

func test_plan_is_deterministic_for_a_seed_and_changes_with_it() -> void:
	var scenario := make_scenario()
	add_child_autofree(scenario)

	var first := scenario.plan()
	var second := scenario.plan()
	var rocks := rocks_of(first)

	assert_eq(rocks.size(), 4 + 3, "belt rocks plus field rocks")
	assert_eq(enemies_of(first).size(), 2, "the spawn zone's fill")
	assert_eq(first.size(), second.size())

	for i in first.size():
		assert_eq(first[i]["position"], second[i]["position"], "same spot twice")

		if first[i]["type"] == Region.PLAN_ROCK:
			assert_eq(first[i]["chunks"], second[i]["chunks"])
			assert_eq(first[i]["rock"]["seed"], second[i]["rock"]["seed"])
			assert_eq(first[i]["rock"]["rotation"], second[i]["rock"]["rotation"])

	var belt_center: Vector2 = scenario.get_node("Belt").global_position / ppu()

	for rock in rocks.slice(0, 4):
		assert_between(rock["position"].distance_to(belt_center), 7.99, 12.01, "belt rock on the ring")
		assert_between(rock["chunks"], 1, 2)
		assert_eq(rock["orbit_center"], belt_center)
		assert_almost_eq(rock["angular_speed"], 0.05, 0.0001)
		assert_true(rock["rock"].has("config"), "enough to generate the pixels")
		assert_true(rock["rock"].has("ore"))

	var field_center: Vector2 = scenario.get_node("Field").global_position / ppu()

	for rock in rocks.slice(4):
		assert_lt(absf(rock["position"].x - field_center.x), 15.01, "field rock in the box")
		assert_lt(absf(rock["position"].y - field_center.y), 15.01)
		assert_between(rock["chunks"], 1, 3)
		assert_false(rock.has("orbit_center"), "field rocks drift")

	scenario.get_node("Belt").seed = 22
	var rerolled := rocks_of(scenario.plan())
	assert_eq(rerolled.size(), 7, "the count comes from the density, not the seed")
	var moved := 0

	for i in 4:
		if rerolled[i]["position"] != rocks[i]["position"]:
			moved += 1

	assert_gt(moved, 0, "a new belt seed lays the belt out anew")
	assert_eq(rerolled[4]["position"], rocks[4]["position"], "the field keeps its seed")

func test_region_plan_mirrors_generate_request_for_request() -> void:
	var props := RegionProps.new()
	var belt := RegionAsteroidBelt.new()
	belt.rock_props = ROCK_PROPS
	belt.count = 5
	belt.seed = 77
	belt.position = Vector2(2.0, 3.0)
	props.asteroid_belts = [belt]
	var field := RegionRockField.new()
	field.rock_props = ROCK_PROPS
	field.min_count = 2
	field.max_count = 6
	field.seed = 5
	props.rock_fields = [field]

	var origin := Vector2(10.0, -10.0)
	var planned := Region.plan(props, origin)

	var region := Region.new()
	region.props = props
	region.auto_generate = false
	region.position = origin * ppu()
	add_child_autofree(region)
	region.generate()

	assert_eq(requests.size(), planned.size(), "one request per planned item")
	if requests.size() != planned.size():
		return

	for i in planned.size():
		assert_eq(requests[i].position, planned[i]["position"], "request %d at the planned spot" % i)
		assert_true(requests[i].is_rock())

		if i < belt.count:
			assert_eq(requests[i].chunks, planned[i]["chunks"], "belt request %d asks the planned chunks" % i)
		else:
			assert_eq(requests[i].chunks, 0, "field requests leave the chunks to the spawner")

		# the request's rng is the planned rock's, one step behind: it makes
		# the same draws once the spawner runs it
		var rng := RandomNumberGenerator.new()
		rng.seed = requests[i].rng.seed
		var described := RockGenerator.plan_rock(rng, ROCK_PROPS, requests[i].chunks)
		assert_eq(described["seed"], planned[i]["rock"]["seed"], "same rock seed")
		assert_eq(described["chunks"], planned[i]["chunks"])
		assert_eq(described["rotation"], planned[i]["rock"]["rotation"])

func test_plan_matches_what_start_spawns() -> void:
	var arena := Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	var world := RegolithWorld.new()
	world.gravity = Vector2.ZERO
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)
	var spawner := StableSpawner.new()
	spawner.sprite_material = SPRITE_MATERIAL
	arena.add_child(spawner)
	await wait_physics_frames(1)

	var scenario := make_scenario()
	# no fighters: the spawner has no fighter scene here and the zone's
	# spots are random anyway. a still belt, so the rocks stay where they
	# landed while the test looks
	var spawn: SpawnZone = scenario.get_node("Spawn")
	spawn.kinds = []
	var belt: AsteroidBeltZone = scenario.get_node("Belt")
	belt.orbit_speed = 0.0
	arena.add_child(scenario)
	var planned := rocks_of(scenario.plan())
	scenario.start()

	var rock_requests := requests.filter(func(r: SpawnRequest): return r.is_rock())
	assert_eq(rock_requests.size(), planned.size())

	for i in planned.size():
		assert_eq(rock_requests[i].position, planned[i]["position"], "request %d asks for the planned spot" % i)

	var spawned := {}
	var on_spawned := func(request: SpawnRequest, node: RegolithSprite) -> void:
		spawned[request] = node
	spawner.spawned.connect(on_spawned)

	for i in 90:
		await wait_physics_frames(1)

		if spawned.size() == planned.size():
			break

	assert_eq(spawned.size(), planned.size(), "every planned rock spawned")
	var cell := 1.0 / RegolithWorld.CELLS_PER_CHUNK

	for i in planned.size():
		var node: RegolithSprite = spawned.get(rock_requests[i])

		if node == null:
			continue

		var item := planned[i]
		assert_lt(node.global_position.distance_to(item["position"] * ppu()) / ppu(), cell, "rock %d stands where planned" % i)
		assert_eq(Steering.cell_count(node), Vector2.ONE * item["chunks"] * RegolithWorld.CELLS_PER_CHUNK, "rock %d has the planned size" % i)
		assert_almost_eq(angle_difference(node.global_rotation, item["rock"]["rotation"]), 0.0, 0.01, "rock %d sits at the planned angle" % i)

	spawner.spawned.disconnect(on_spawned)
	get_tree().current_scene = null
	arena.free()

# preview node

func test_preview_node_exists_only_when_asked_and_never_at_runtime() -> void:
	var scenario := make_scenario()
	add_child_autofree(scenario)
	await wait_process_frames(1)

	assert_null(scenario.preview_node, "no preview in the game")
	assert_eq(scenario.get_child_count(true), scenario.get_child_count(false), "no hidden children either")
	assert_eq(scenario.zones().size(), 3)

	var demo: Node2D = load(DEMO).instantiate()
	var demo_scenario: Scenario = demo.get_node("Scenario")
	demo_scenario.auto_start = false
	demo_scenario.clear_scene_sprites = false
	get_tree().root.add_child(demo)
	get_tree().current_scene = demo
	await wait_process_frames(1)
	assert_null(demo_scenario.preview_node, "the demo scene runs without one")
	assert_eq(demo_scenario.get_child_count(true), demo_scenario.get_child_count(false))
	get_tree().current_scene = null
	demo.free()

	var preview := scenario.ensure_preview()
	assert_not_null(preview)
	assert_eq(scenario.ensure_preview(), preview, "one preview")
	assert_eq(preview.get_parent(), scenario)
	assert_null(preview.owner, "never saved with the scene")
	assert_eq(scenario.get_child_count(false), 3, "internal, get_children skips it")
	assert_eq(scenario.get_child_count(true), 4)
	assert_eq(scenario.zones().size(), 3, "zones ignore it")
	assert_true(preview.visible)

	scenario.preview = false
	assert_false(preview.visible, "the export hides it")
	scenario.preview = true
	assert_true(preview.visible)

func test_preview_plans_once_deferred_and_caches_textures_until_the_plan_drops_them() -> void:
	var scenario := make_scenario()
	add_child_autofree(scenario)
	watch_signals(scenario)
	var preview := scenario.ensure_preview()

	assert_true(scenario.replan_queued, "ensure_preview asks for a plan")
	assert_eq(preview.items.size(), 0, "nothing yet, the plan is deferred")
	await wait_process_frames(1)

	assert_false(scenario.replan_queued)
	assert_signal_emit_count(scenario, "replanned", 1)
	assert_eq(preview.rock_count(), 7)
	assert_eq(preview.enemy_count(), 2)
	assert_eq(preview.belts.size(), 1, "one belt ring for the arrows")
	assert_almost_eq(preview.pixels_per_unit, ppu(), 0.001)
	# the preview's own _process may have built some or all within its
	# frame budget already, the rest comes now
	assert_eq(preview.pending_count() + preview.texture_count(), 7, "every rock built or queued")
	preview.build_pending(-1)
	assert_eq(preview.pending_count(), 0)
	assert_false(preview.is_processing(), "done building, nothing per frame")
	var keys := {}

	for item in rocks_of(preview.items):
		keys[item["key"]] = true
		var texture: Texture2D = preview.texture_of(item)
		assert_not_null(texture, "every planned rock has its texture")

		if texture:
			assert_eq(texture.get_size(), Vector2.ONE * item["chunks"] * RegolithWorld.CELLS_PER_CHUNK, "the rock's pixels")

	assert_eq(preview.texture_count(), keys.size(), "one texture per distinct rock")
	var before: Dictionary = preview.textures.duplicate()

	# one setter, one deferred replan
	var belt: AsteroidBeltZone = scenario.get_node("Belt")
	belt.orbit_speed = 0.2
	belt.clockwise = false
	assert_true(scenario.replan_queued)
	assert_signal_emit_count(scenario, "replanned", 1, "not yet")
	await wait_process_frames(1)
	assert_signal_emit_count(scenario, "replanned", 2, "one replan for two edits")
	assert_almost_eq(preview.belts[0]["angular_speed"], -0.2, 0.0001, "the arrows follow")
	assert_eq(preview.pending_count(), 0, "same rocks, nothing to build")

	for key in before:
		assert_eq(preview.textures.get(key), before[key], "texture %s kept" % key)

	# a moved zone keeps its textures, the rocks only move
	belt.position += Vector2(3.0, 0.0) * ppu()
	belt.mark_dirty()
	await wait_process_frames(1)
	assert_eq(preview.pending_count(), 0, "moved rocks reuse their textures")
	assert_eq(preview.texture_count(), keys.size())

	# a new seed drops the old textures and builds new ones
	var old_seed := belt.seed
	var new_seed := belt.reroll_seed()
	assert_ne(new_seed, old_seed)
	assert_eq(belt.seed, new_seed)
	assert_true(scenario.replan_queued, "reroll replans")
	await wait_process_frames(1)
	preview.build_pending(-1)
	assert_eq(preview.texture_count(), 7, "one texture per rock again")

	for item in rocks_of(preview.items).slice(0, 4):
		assert_false(before.has(item["key"]), "belt rock %s is new" % item["key"])
		assert_not_null(preview.texture_of(item), "and built")

	var dropped := 0

	for key in before:
		if not preview.textures.has(key):
			dropped += 1

	assert_gt(dropped, 0, "the old belt's textures are gone")
	var field_keys := 0

	for item in rocks_of(preview.items).slice(4):
		if before.has(item["key"]):
			field_keys += 1

	assert_eq(field_keys, 3, "the field's textures were kept")

	preview.clear_cache()
	assert_eq(preview.texture_count(), 0)

	# a zone removed replans too
	var field: RockFieldZone = scenario.get_node("Field")
	scenario.remove_child(field)
	field.free()
	await wait_process_frames(1)
	assert_eq(preview.rock_count(), 4, "the field's rocks left the plan")

func test_spawn_zone_plan_and_scenario_rerolls() -> void:
	var scenario := make_scenario()
	add_child_autofree(scenario)
	var zone: SpawnZone = scenario.get_node("Spawn")
	zone.max_alive = 3
	zone.kinds = [SpawnRequest.Kind.FIGHTER, SpawnRequest.Kind.BOMB]
	zone.weights = [1.0, 0.0]

	var enemies := enemies_of(scenario.plan())
	assert_eq(enemies.size(), 3)
	var center := zone.global_position / ppu()

	for enemy in enemies:
		assert_eq(enemy["kind"], SpawnRequest.Kind.FIGHTER, "zero weight never picked")
		assert_lt(absf(enemy["position"].x - center.x), 4.01, "inside the zone")
		assert_lt(absf(enemy["position"].y - center.y), 4.01)

	assert_eq(enemies_of(scenario.plan())[0]["position"], enemies[0]["position"], "the preview holds still")

	var belt: AsteroidBeltZone = scenario.get_node("Belt")
	var field: RockFieldZone = scenario.get_node("Field")
	var belt_seed := belt.seed
	var field_seed := field.seed
	var rerolled := scenario.reroll_seeds()
	assert_eq(rerolled.size(), 2, "the two seeded zones")
	assert_ne(belt.seed, belt_seed)
	assert_ne(field.seed, field_seed)

	assert_eq(EnemyPlacement.kind_to_name(SpawnRequest.Kind.BOSS_COMPASS), &"boss_compass")
	assert_eq(EnemyPlacement.kind_to_name(-1), &"")
	assert_eq(EnemyPlacement.scene_path_for(&"fighter"), "res://game/scenes/enemies/EnemyFighter.tscn")
	var texture := EnemyPlacement.scene_texture(EnemyPlacement.scene_path_for(&"fighter"))
	assert_not_null(texture, "the preview's fighter silhouette")
	assert_null(EnemyPlacement.scene_texture("res://game/scenes/enemies/EnemyNoSuch.tscn"))

# rock description

func test_describe_and_plan_rock_make_the_spawner_draws() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var images := RockGenerator.make_rock(rng, ROCK_PROPS)

	rng.seed = 9
	var described := RockGenerator.describe_rock(rng, ROCK_PROPS)
	assert_eq(described["chunks"], images["chunks"])
	assert_eq(described["seed"], images["seed"])
	assert_eq(RockGenerator.generate_described(described)["color"].get_data(), images["color"].get_data(), "the same pixels")

	rng.seed = 9
	var planned := RockGenerator.plan_rock(rng, ROCK_PROPS, 2)
	assert_eq(planned["chunks"], 2, "given chunks are kept")
	assert_between(planned["rotation"], 0.0, TAU)
	assert_ne(RockGenerator.describe_key(planned), RockGenerator.describe_key(described), "size is in the key")
	rng.seed = 9
	assert_eq(RockGenerator.describe_key(RockGenerator.plan_rock(rng, ROCK_PROPS, 2)), RockGenerator.describe_key(planned), "same draws, same key")

# plugin

func test_plugin_toolbar_carries_preview_and_reroll_and_the_inspector_claims_seeded_zones() -> void:
	# an EditorPlugin only exists inside the editor, the toolbar builder is
	# static for this reason
	var script = load(PLUGIN)
	var on_add := func(_id: int) -> void: pass
	var on_preview := func(_on: bool) -> void: pass
	var on_reroll := func() -> void: pass
	var made: Dictionary = script.make_toolbar(on_add, on_preview, on_reroll)
	var toolbar: HBoxContainer = made["toolbar"]

	assert_eq(toolbar.name, "ScenarioToolbar")
	var toggle := toolbar.get_node_or_null(script.PREVIEW_TOGGLE_NAME) as CheckBox
	var reroll := toolbar.get_node_or_null(script.REROLL_BUTTON_NAME) as Button
	assert_not_null(toolbar.get_node_or_null("Menu") as MenuButton, "the Add menu stays")
	assert_eq(made["menu"], toolbar.get_node_or_null("Menu"))
	assert_eq(made["preview_toggle"], toggle, "Preview toggle")
	assert_eq(made["reroll_button"], reroll, "Reroll seed button")

	if toggle:
		assert_true(toggle.button_pressed, "preview defaults on")
		assert_true(toggle.toggled.is_connected(on_preview))

	if reroll:
		assert_true(reroll.pressed.is_connected(on_reroll))

	var methods := {}
	for m in script.get_script_method_list():
		methods[m["name"]] = true
	for wanted in ["make_toolbar", "_on_preview_toggled", "_on_reroll", "reroll", "seeded_zones"]:
		assert_true(methods.has(wanted), "plugin implements " + wanted)

	var belt := AsteroidBeltZone.new()
	var field := RockFieldZone.new()
	var zone := SpawnZone.new()
	var scenario := Scenario.new()
	scenario.add_child(belt)
	scenario.add_child(field)
	scenario.add_child(zone)
	var seeded: Array = script.seeded_zones(scenario)
	assert_eq(seeded.size(), 2, "belts and fields carry seeds, spawn zones do not")
	assert_true(belt in seeded)
	assert_true(field in seeded)
	assert_false(zone in seeded)
	assert_true(script.ZoneInspector.handles_seed(belt))
	assert_true(script.ZoneInspector.handles_seed(field))
	assert_true(script.ZoneInspector.handles_seed(scenario), "reroll all on the Scenario")
	assert_false(script.ZoneInspector.handles_seed(zone))
	scenario.free()
	toolbar.free()
