extends GutTest

# items: the props carry the original prefab numbers, an item request on the
# SpawnBus lands as an Item node at once while the StableSpawner ignores it,
# loose items drift, damp and expire, the player pulls one in and heals, a
# cloud only takes cores, drop tables roll, a core hit knocks a core off the
# player and a destroyed sprite with a table drops. then the main scene end
# to end: the real player heals one cell per health item, the best
# connected cell nearest the root first, a core rebuilds the cloud without
# double counting, energy items pour sand into the PowerTank and an enemy's
# core burst drops health the player takes

const HEALTH_SMALL := preload("res://game/config/items/health_small.tres")
const HEALTH_MEDIUM := preload("res://game/config/items/health_medium.tres")
const HEALTH_LARGE := preload("res://game/config/items/health_large.tres")
const CORE := preload("res://game/config/items/core.tres")
const GUARANTEED := preload("res://game/config/items/guaranteed_health_item.tres")
const MIXED_OK := preload("res://game/config/items/mixed_ok.tres")
const PLAYER_SCENE := preload("res://game/scenes/player/Player.tscn")
const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner

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
	spawner = StableSpawner.new()
	arena.add_child(spawner)
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()
	free_main()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func add_player(units: Vector2) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = units * ppu()
	player.set_process(false)
	arena.add_child(player)
	return player

func items() -> Array[Node]:
	return get_tree().get_nodes_in_group("item")

# spawns and hands back the item node
func spawn(props: ItemProps, at: Vector2, velocity := Vector2.ZERO) -> Item:
	var seen := {"item": null}
	var request := SpawnRequest.item(props, at, velocity)
	request.item_spawned.connect(func(item): seen["item"] = item)
	SpawnBus.send(request)
	return seen["item"]

func first_cell_of_type(sprite: RegolithSprite, type: int) -> Vector2i:
	var count := sprite.get_cell_count()

	for y in count.y:
		for x in count.x:
			if sprite.get_cell_type(Vector2i(x, y)) == type:
				return Vector2i(x, y)

	return Vector2i(-1, -1)

func test_props_carry_the_original_numbers() -> void:
	var sizes := [ItemProps.Size.SMALL, ItemProps.Size.MEDIUM, ItemProps.Size.LARGE]
	var all := [HEALTH_SMALL, HEALTH_MEDIUM, HEALTH_LARGE]

	for i in all.size():
		var props: ItemProps = all[i]
		assert_eq(props.type, ItemProps.Type.HEALTH)
		assert_eq(props.size, sizes[i])
		assert_eq(props.heal_cells, 1, "one cell per item")
		assert_almost_eq(props.radius, 1.0, 0.0001)
		assert_almost_eq(props.pickup_delay, 0.6, 0.0001)
		assert_almost_eq(props.collect_time, 1.0, 0.0001)
		assert_almost_eq(props.life, 15.0, 0.0001)
		assert_almost_eq(props.damping_min, 3.0, 0.0001)
		assert_almost_eq(props.damping_max, 10.0, 0.0001)
		assert_not_null(props.texture, "size %d has art" % i)
		assert_eq(Items.health_props(sizes[i]), props)

	assert_eq(HEALTH_SMALL.texture.get_size(), Vector2(4, 4))
	assert_eq(HEALTH_MEDIUM.texture.get_size(), Vector2(6, 6), "the original default.png")
	assert_eq(HEALTH_LARGE.texture.get_size(), Vector2(8, 8))

	assert_true(CORE.is_core())
	assert_almost_eq(CORE.speed_min, 4.0, 0.0001)
	assert_almost_eq(CORE.speed_max, 6.0, 0.0001)
	assert_almost_eq(CORE.damping_max, 0.2, 0.0001)
	assert_eq(CORE.texture.get_size(), Vector2(7, 7), "the original core_shard.png")

func test_item_request_spawns_an_item_at_once_and_the_stable_spawner_ignores_it() -> void:
	watch_signals(spawner)
	var request := SpawnRequest.item(HEALTH_MEDIUM, Vector2(3.0, -2.0), Vector2(1.5, 0.0))
	var seen := {"item": null, "expired": false}
	request.item_spawned.connect(func(item): seen["item"] = item)
	request.expired.connect(func(): seen["expired"] = true)
	SpawnBus.send(request)

	var item: Item = seen["item"]
	assert_not_null(item, "placed on the spot, no queue")
	assert_false(seen["expired"])
	assert_eq(spawner.pending(), 0, "the StableSpawner left it alone")
	assert_signal_not_emitted(spawner, "expired")
	if item == null:
		return

	assert_true(request.is_item())
	assert_eq(item.get_parent(), arena, "under the world's parent")
	assert_true(item.is_in_group("item"))
	assert_eq(item.props, HEALTH_MEDIUM)
	assert_almost_eq(item.global_position, Vector2(3.0, -2.0) * ppu(), Vector2.ONE * 0.01)
	assert_almost_eq(item.velocity, Vector2(1.5, 0.0), Vector2.ONE * 0.01)
	assert_between(item.damping, 3.0, 10.0)
	assert_between(item.angular_velocity, -40.0, 40.0)
	assert_eq(item.visual.texture, HEALTH_MEDIUM.texture)
	assert_eq(item.visual.modulate, HEALTH_MEDIUM.tint)
	assert_eq(item.visual.scale, Vector2.ONE * RegolithWorld.pixels_per_cell(), "one texel per cell")

func test_core_items_take_their_own_speed_along_the_spawn_direction() -> void:
	var item := spawn(CORE, Vector2.ZERO, Vector2(0.0, 30.0))
	assert_not_null(item)
	if item == null:
		return

	assert_between(item.velocity.length(), 4.0, 6.0)
	assert_almost_eq(item.velocity.normalized(), Vector2.DOWN, Vector2.ONE * 0.001)
	assert_between(item.damping, 0.0, 0.2)

func test_loose_item_drifts_damps_and_expires() -> void:
	var props: ItemProps = HEALTH_SMALL.duplicate()
	props.life = 0.4
	props.damping_min = 2.0
	props.damping_max = 2.0
	var item := spawn(props, Vector2.ZERO, Vector2(4.0, 0.0))
	watch_signals(item)
	await wait_physics_frames(6)

	assert_gt(item.global_position.x, 0.0, "drifted along its velocity")
	assert_lt(item.velocity.x, 4.0, "damped")
	assert_gt(item.velocity.x, 0.0)

	await wait_seconds(0.6)
	assert_false(is_instance_valid(item), "gone after its life")
	assert_eq(items().size(), 0)

func test_player_pulls_a_health_item_in_and_heals() -> void:
	var player := add_player(Vector2.ZERO)
	await wait_physics_frames(2)
	watch_signals(player)

	var cell := first_cell_of_type(player, RegolithSprite.CELL_FILLED)
	var cells_before := player.get_active_cell_count()
	player.remove_cell(cell)
	await wait_physics_frames(2)
	assert_eq(player.get_active_cell_count(), cells_before - 1)

	var item := spawn(HEALTH_MEDIUM, Vector2(0.5, 0.0))
	watch_signals(item)
	await wait_seconds(0.3)
	assert_false(item.is_collecting(), "nothing pulls during the pickup delay")

	await wait_seconds(0.5)
	assert_true(item.is_collecting(), "pulled once the delay passed")
	assert_eq(item.collecting, player)

	await wait_seconds(1.2)
	assert_false(is_instance_valid(item), "landed")
	assert_signal_emit_count(player, "item_collected", 1)
	assert_eq(player.get_active_cell_count(), cells_before, "one hull cell repaired")

func test_item_out_of_reach_stays_loose() -> void:
	add_player(Vector2.ZERO)
	var item := spawn(HEALTH_MEDIUM, Vector2(2.0, 0.0))
	await wait_seconds(1.0)

	assert_true(is_instance_valid(item))
	assert_false(item.is_collecting(), "a unit radius does not reach two units out")

func test_cloud_only_takes_cores_and_a_core_rebuilds_it() -> void:
	var player := add_player(Vector2.ZERO)
	await wait_physics_frames(3)

	if player.cloud == null:
		pending("no PlayerCloud child on the player scene")
		return

	player.cloud.enter()
	assert_true(player.is_cloud())

	var health := spawn(HEALTH_MEDIUM, Vector2(0.4, 0.0))
	var core := spawn(CORE, Vector2(-0.4, 0.0), Vector2.ZERO)
	watch_signals(player)
	await wait_seconds(0.9)

	assert_false(health.is_collecting(), "a cloud leaves health alone")
	assert_true(core.is_collecting(), "a cloud pulls a core")
	assert_true(player.cloud.collecting, "the death timer waits on the core")

	await wait_seconds(1.2)
	assert_false(is_instance_valid(core), "core landed")
	assert_gt(get_signal_emit_count(player, "item_collected"), 0, "the core was collected")
	assert_false(player.is_cloud(), "a core rebuilds the ship")
	assert_false(player.cloud.collecting)

func test_drop_tables_roll_each_entry() -> void:
	var sure := ItemDropTable.new()
	var entry := ItemDropEntry.new()
	entry.item = HEALTH_LARGE
	entry.chance = 1.0
	entry.count = 2
	var never := ItemDropEntry.new()
	never.item = HEALTH_SMALL
	never.chance = 0.0
	never.count = 5
	sure.entries = [entry, never]

	var drops := sure.roll()
	assert_eq(drops.size(), 2)
	assert_eq(drops[0], HEALTH_LARGE)
	assert_eq(drops[1], HEALTH_LARGE)

	assert_eq(GUARANTEED.entries.size(), 1)
	assert_eq(GUARANTEED.roll().size(), 1, "the original guaranteed_health_item: chance 1, count 1")
	assert_eq(GUARANTEED.roll()[0], HEALTH_MEDIUM)
	assert_eq(MIXED_OK.entries.size(), 2)

func test_drop_table_lookup_reads_property_meta_and_class() -> void:
	var plain := RegolithSprite.new()
	arena.add_child(plain)
	assert_null(Items.drop_table_for(plain), "nothing set")

	plain.set_meta("drop_table", MIXED_OK)
	assert_eq(Items.drop_table_for(plain), MIXED_OK, "meta")

	for class_key in ["EnemyFighter", "EnemyBomb", "EnemyStation", "EnemyBase"]:
		assert_true(Items.DROP_TABLES.has(class_key), "%s has a table, the original prefab named one" % class_key)

	# the class walk, on the player so no enemy scene is needed: its own
	# class first, then a script extending it finds the table up the chain
	var player := add_player(Vector2(6.0, 0.0))
	assert_null(Items.drop_table_for(player), "no table for Player by default")

	Items.set_class_drop_table("Player", GUARANTEED)
	assert_eq(Items.drop_table_for(player), GUARANTEED, "the class table")

	var subclass := GDScript.new()
	subclass.source_code = "extends Player\n"
	subclass.reload()
	var derived: RegolithSprite = subclass.new()
	arena.add_child(derived)
	assert_eq(Items.drop_table_for(derived), GUARANTEED, "found up the base chain")

	Items.set_class_drop_table("Player", null)
	assert_null(Items.drop_table_for(player), "cleared")

func test_core_hit_on_the_player_knocks_a_core_loose() -> void:
	var player := add_player(Vector2.ZERO)
	await wait_physics_frames(2)

	Items.on_core_hit(player, player.global_position, Vector2.RIGHT)
	assert_eq(items().size(), 1)
	var item: Item = items()[0]
	assert_true(item.props.is_core())
	assert_between(item.velocity.length(), 4.0, 6.0, "thrown at the core item speed")

	var rock := RegolithSprite.new()
	arena.add_child(rock)
	rock.create_blank(Vector2i(8, 8))
	Items.on_core_hit(rock, rock.global_position, Vector2.RIGHT)
	assert_eq(items().size(), 1, "only the player sheds cores")

func test_destroyed_sprite_with_a_drop_table_drops_it() -> void:
	var rock := RegolithSprite.new()
	rock.position = Vector2(5.0, 5.0) * ppu()
	rock.set_meta("drop_table", GUARANTEED)
	arena.add_child(rock)
	rock.create_blank(Vector2i(8, 8))
	rock.fill_rect(Rect2i(0, 0, 8, 8), Color.WHITE, RegolithSprite.CELL_FILLED, 0)
	await wait_physics_frames(2)

	# under twenty cells the world drops the sprite at the next commit
	rock.clear_rect(Rect2i(0, 0, 8, 6))
	await wait_physics_frames(3)

	assert_false(is_instance_valid(rock), "destroyed")
	assert_eq(items().size(), 1, "the table rolled once")
	var item: Item = items()[0]
	assert_eq(item.props, HEALTH_MEDIUM)
	assert_lt(item.global_position.distance_to(Vector2(5.0, 5.0) * ppu()), 1.0 * ppu())

# ---- the main scene, end to end ----

const ENERGY_SMALL := preload("res://game/config/items/energy_small.tres")
const ENERGY_MEDIUM := preload("res://game/config/items/energy_medium.tres")
const ENERGY_LARGE := preload("res://game/config/items/energy_large.tres")
const POWER_TANK_MASK := preload("res://game/images/ui/power_tank_mask.png")

# an enemy for the Items autoload: in group enemy with a die, built from a
# filled square with a core cut into it
class FakeEnemy extends RegolithSprite:
	var died := false
	var drop_table: ItemDropTable

	func _ready() -> void:
		add_to_group("enemy")
		add_to_group("regolith")

	func die() -> void:
		died = true
		queue_free()

var main: Node2D
var player: Player

# swaps the arena for Main.tscn: the real player, world, spawner and effects
func use_main() -> void:
	get_tree().current_scene = null
	arena.free()
	arena = Node2D.new()
	main = load("res://game/scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	player = main.get_node("Player")
	player.set_process(false)
	await wait_physics_frames(3)

func free_main() -> void:
	if main != null and is_instance_valid(main):
		main.free()

	main = null

func player_center() -> Vector2:
	return player.get_center_of_mass() / ppu()

# waits for an item to land, up to a timeout
func await_landed(item: Item, timeout := 3.5) -> void:
	var elapsed := 0.0

	while is_instance_valid(item) and elapsed < timeout:
		await wait_physics_frames(1)
		elapsed += get_physics_process_delta_time()

func remove_core_cells() -> void:
	var count := player.get_cell_count()

	for y in count.y:
		for x in count.x:
			if player.get_cell_type(Vector2i(x, y)) == RegolithSprite.CELL_CORE:
				player.remove_cell(Vector2i(x, y))

static func build_images(size: Vector2i, filled: Rect2i, core: Rect2i) -> Array:
	var color := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	for y in range(filled.position.y, filled.end.y):
		for x in range(filled.position.x, filled.end.x):
			color.set_pixel(x, y, Color(0.6, 0.6, 0.6, 1.0))
			mask.set_pixel(x, y, Color8(0, 100, 255, 255))

	for y in range(core.position.y, core.end.y):
		for x in range(core.position.x, core.end.x):
			color.set_pixel(x, y, Color(1.0, 0.6, 0.3, 1.0))
			mask.set_pixel(x, y, Color8(0, 200, 255, 255))

	return [color, mask]

func test_energy_props_carry_the_original_ability_numbers() -> void:
	var cells := [25, 60, 120]
	var all := [ENERGY_SMALL, ENERGY_MEDIUM, ENERGY_LARGE]

	for i in all.size():
		var props: ItemProps = all[i]
		assert_true(props.is_energy())
		assert_false(props.is_core())
		assert_eq(props.power_cells, cells[i], "the ability scripts' cells by size")
		assert_eq(props.heal_cells, 0, "energy repairs nothing")
		assert_gt(props.power_color.a, 0.0)
		assert_almost_eq(props.damping_min, 1.0, 0.0001, "the default damping branch of ItemSpawn")
		assert_almost_eq(props.damping_max, 4.0, 0.0001)
		assert_eq(Items.energy_props(i), props)

func test_in_main_a_health_item_next_to_the_player_regrows_a_hull_cell() -> void:
	await use_main()
	watch_signals(player)
	var cells_before := player.get_active_cell_count()
	var cell := first_cell_of_type(player, RegolithSprite.CELL_FILLED)
	player.remove_cell(cell)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before - 1, "one hull cell shot off")
	assert_false(player.has_cell(cell))

	var item := spawn(HEALTH_MEDIUM, player_center() + Vector2(0.5, 0.0))
	assert_not_null(item)
	assert_eq(item.get_parent(), main, "spawned under Main, the world's parent")
	await await_landed(item)

	assert_false(is_instance_valid(item), "landed on the ship")
	assert_signal_emit_count(player, "item_collected", 1)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before, "the hull cell is back")
	assert_true(player.has_cell(cell), "the one cell missing was the one regrown")
	assert_eq(player.get_cell_type(cell), RegolithSprite.CELL_FILLED)

	free_main()

func test_health_regrows_the_best_connected_cell_nearest_the_root_first() -> void:
	await use_main()
	var cells_before := player.get_active_cell_count()

	# a straight notch up into the hull from the bottom of its middle column,
	# where nothing gets cut off: the innermost cell touches the most live
	# neighbours and sits nearest the root, it comes back first, the edge
	# cell last
	var column := int(player.texture.get_width()) / 2
	var bottom := -1

	for y in player.get_cell_count().y:
		if player.get_cell_type(Vector2i(column, y)) == RegolithSprite.CELL_FILLED:
			bottom = y

	var notch: Array[Vector2i] = []

	for i in 3:
		var cell := Vector2i(column, bottom - i)

		if bottom < 0 or player.get_cell_type(cell) != RegolithSprite.CELL_FILLED:
			break

		notch.append(cell)

	assert_eq(notch.size(), 3, "three hull cells in a column")
	if notch.size() < 3:
		free_main()
		return

	for cell in notch:
		player.remove_cell(cell)

	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before - 3)

	player.collect_item(HEALTH_MEDIUM)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before - 2, "one cell per health item")
	assert_true(player.has_cell(notch[2]), "the innermost cell of the notch first")
	assert_false(player.has_cell(notch[0]), "the outer cell waits")

	player.collect_item(HEALTH_MEDIUM)
	player.collect_item(HEALTH_MEDIUM)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before, "the notch is closed")

	player.collect_item(HEALTH_MEDIUM)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before, "nothing left to repair, nothing grows")

	free_main()

func test_a_core_rebuilds_the_cloud_and_later_heals_do_not_double_count() -> void:
	await use_main()
	var cells_before := player.get_active_cell_count()
	var cores_before := player.count_cells_of_type(RegolithSprite.CELL_CORE)
	assert_gt(cores_before, 0)

	remove_core_cells()
	await wait_physics_frames(6)
	assert_true(player.is_cloud(), "losing the core made a cloud")
	assert_eq(player.count_cells_of_type(RegolithSprite.CELL_CORE), 0)

	var core := spawn(CORE, player_center() + Vector2(0.4, 0.0))
	await await_landed(core)
	assert_false(is_instance_valid(core), "the cloud took the core")
	await wait_physics_frames(3)

	assert_false(player.is_cloud(), "rebuilt")
	assert_eq(player.count_cells_of_type(RegolithSprite.CELL_CORE), cores_before, "core cells back")
	assert_eq(player.get_active_cell_count(), cells_before, "every cell back, none counted twice")

	# the rebuilt hull heals like a fresh one: a cell off, a health item, the
	# cell back and not one more
	var cell := first_cell_of_type(player, RegolithSprite.CELL_FILLED)
	player.remove_cell(cell)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before - 1)

	player.collect_item(HEALTH_MEDIUM)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before, "one cell back")
	assert_true(player.has_cell(cell))

	player.collect_item(HEALTH_MEDIUM)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before, "a full hull stays full")

	player.collect_item(CORE)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before, "a core on a full hull adds nothing")
	assert_eq(player.count_cells_of_type(RegolithSprite.CELL_CORE), cores_before)

	free_main()

func test_an_energy_item_pours_sand_into_the_power_tank() -> void:
	await use_main()
	var tank := PowerTank.new()
	tank.mask = POWER_TANK_MASK
	tank.body = player
	main.add_child(tank)
	assert_true(tank.is_in_group("power_tank"))
	assert_eq(player.power_tank(), tank, "the ship finds the tank on the hud")
	assert_eq(tank.cells_queued + tank.filled_count(), 0)

	var cells_before := player.get_active_cell_count()
	watch_signals(player)
	var item := spawn(ENERGY_MEDIUM, player_center() + Vector2(0.0, 0.5))
	await await_landed(item)

	assert_false(is_instance_valid(item), "landed")
	assert_signal_emit_count(player, "item_collected", 1)
	assert_eq(tank.cells_queued + tank.filled_count(), 60, "sixty cells of sand, queued or already in")
	assert_eq(tank.feed_color, ENERGY_MEDIUM.power_color, "in the item's color")
	assert_eq(player.get_active_cell_count(), cells_before, "energy repairs nothing")

	await wait_seconds(0.3)
	assert_gt(tank.filled_count(), 0, "the sand is falling in")

	player.collect_item(ENERGY_LARGE)
	assert_eq(tank.cells_queued + tank.filled_count(), 180)

	free_main()

func test_a_cloud_leaves_energy_and_health_alone() -> void:
	await use_main()
	remove_core_cells()
	await wait_physics_frames(6)
	assert_true(player.is_cloud())

	var energy := spawn(ENERGY_SMALL, player_center() + Vector2(0.3, 0.0))
	var health := spawn(HEALTH_SMALL, player_center() + Vector2(-0.3, 0.0))
	await wait_seconds(1.0)

	assert_true(is_instance_valid(energy) and not energy.is_collecting(), "energy waits")
	assert_true(is_instance_valid(health) and not health.is_collecting(), "health waits")

	free_main()

func test_an_enemy_core_burst_drops_health_the_player_takes() -> void:
	await use_main()
	var cells_before := player.get_active_cell_count()
	var cell := first_cell_of_type(player, RegolithSprite.CELL_FILLED)
	player.remove_cell(cell)

	# far enough that the burst's shrapnel never reaches the ship
	var enemy := FakeEnemy.new()
	enemy.drop_table = GUARANTEED
	enemy.position = (player_center() + Vector2(14.0, 0.0)) * ppu()
	main.add_child(enemy)
	var images := build_images(Vector2i(24, 24), Rect2i(0, 0, 24, 24), Rect2i(10, 10, 5, 5))
	enemy.load_from_images(images[0], images[1])
	await wait_physics_frames(3)
	assert_eq(enemy.get_core_count(), 1)
	assert_eq(player.get_active_cell_count(), cells_before - 1)

	# 18 of 25 core cells gone: power max(7, 12) = 12, two health items plus
	# the guaranteed one
	var core_cells: Array[Vector2i] = []
	var count := enemy.get_cell_count()

	for y in count.y:
		for x in count.x:
			if enemy.get_cell_type(Vector2i(x, y)) == RegolithSprite.CELL_CORE:
				core_cells.append(Vector2i(x, y))

	for i in 18:
		enemy.remove_cell(core_cells[i])

	watch_signals(Items)
	await wait_physics_frames(3)
	assert_signal_emit_count(Items, "core_exploded", 1, "the core blew")

	await wait_seconds(Items.SEQUENCE_DURATION + 0.4)
	assert_signal_emit_count(Items, "burst_finished", 1)
	assert_false(is_instance_valid(enemy), "the enemy died with the burst")

	var dropped := items()
	assert_eq(dropped.size(), 3, "12 / 5 health items plus the table's drop")

	for node in dropped:
		var item: Item = node
		assert_eq(item.props.type, ItemProps.Type.HEALTH)
		assert_lt(item.pos.distance_to(player_center() + Vector2(14.0, 0.0)), 3.0, "dropped around the core, units")

	if dropped.is_empty():
		free_main()
		return

	# the ship flies over: the drops land in reach of the player
	watch_signals(player)

	for node in dropped:
		var item: Item = node
		item.pos = player_center() + Vector2(0.4, 0.0).rotated(randf() * TAU)
		item.velocity = Vector2.ZERO

	var elapsed := 0.0

	while not items().is_empty() and elapsed < 4.0:
		await wait_physics_frames(1)
		elapsed += get_physics_process_delta_time()

	assert_eq(items().size(), 0, "every drop taken")
	assert_eq(get_signal_emit_count(player, "item_collected"), 3)
	await wait_physics_frames(3)
	assert_eq(player.get_active_cell_count(), cells_before, "the first heal closed the hole, the rest had nothing to do")

	free_main()
