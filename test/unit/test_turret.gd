extends GutTest

# the turret: SpawnRequest.Kind.TURRET, an EnemyGun running turret.lua
# from EnemyTurret.tscn. it spawns through the StableSpawner at the size
# the request's scale_cells meta asks for (96 across by default, the size
# its art ships at), traverses its barrel slowly and fires the turret
# cannon from the barrel's muzzle, speaking as "turret"

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const TURRET_SCENE := "res://game/scenes/enemies/EnemyTurret.tscn"
const TURRET_CANNON := preload("res://game/config/enemies/turret_cannon.tres")
const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")

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
	spawner.turret_scene = load(TURRET_SCENE)
	spawner.sprite_material = SPRITE_MATERIAL
	arena.add_child(spawner)
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()
	Dialog.clear()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func cell_px() -> float:
	return RegolithWorld.pixels_per_cell()

func add_player(units: Vector2) -> Player:
	var player: Player = load("res://game/scenes/player/Player.tscn").instantiate()
	player.position = units * ppu()
	player.set_process(false)
	arena.add_child(player)
	return player

# a turret placed at once where a scenario placement would put it
func spawn_turret(units: Vector2, facing := 0.0, scale_cells := 0) -> EnemyGun:
	var request := SpawnRequest.enemy(SpawnRequest.Kind.TURRET, units)
	request.rotation = facing
	request.wait_for_room = false

	if scale_cells > 0:
		request.set_meta(EnemyGun.META_SCALE_CELLS, scale_cells)

	var seen := {"node": null}
	request.spawned.connect(func(node): seen["node"] = node)
	SpawnBus.send(request)
	await wait_physics_frames(2)
	return seen["node"] as EnemyGun

func lua_value(turret: EnemyScripted, expression: String) -> Variant:
	assert_eq(Ai.lua.run("__probe = (function(self) return %s end)(__instance(%d))" % [expression, turret.ai_id]), "")
	return Ai.lua.get_global("__probe")

func test_turret_kind_resolves_by_name() -> void:
	assert_true(SpawnRequest.Kind.has("TURRET"))
	assert_eq(spawner.scene_for(SpawnRequest.Kind.TURRET), spawner.turret_scene)
	assert_eq(spawner.kind_name(SpawnRequest.Kind.TURRET), "TURRET")
	assert_true(Ai.has_class("turret"), "turret.lua loaded as a class")

	var placement := EnemyPlacement.new()
	placement.kind_name = &"turret"
	assert_eq(placement.resolve_kind(), SpawnRequest.Kind.TURRET, "a placement named turret spawns the kind")
	assert_eq(placement.scene_path(), TURRET_SCENE)
	placement.free()

func test_turret_spawns_at_its_art_size_by_default() -> void:
	var turret := await spawn_turret(Vector2.ZERO)
	assert_not_null(turret, "spawned")
	if turret == null:
		return

	assert_true(turret is EnemyGun)
	assert_eq(turret.ai_class, "turret")
	assert_gt(turret.ai_id, 0)
	assert_true(turret.is_in_group("turret"))
	assert_true(turret.is_in_group("gun"))
	assert_eq(turret.art_cells, 96, "very large")
	assert_eq(turret.get_cell_count(), Vector2i(96, 96))
	assert_gt(turret.get_active_cell_count(), 2000, "a big ring")
	assert_gt(turret.count_cells_of_type(RegolithSprite.CELL_CORE), 0, "with a core to kill")
	assert_true(turret.has_barrel())
	assert_gt(turret.barrel.get_active_cell_count(), 500, "a long heavy barrel")
	assert_eq(turret.weapon.props, TURRET_CANNON, "the turret cannon")
	assert_eq(turret.state_machine.get_states(), PackedStringArray(["idle", "track", "fire"]), "gun.lua's states")
	assert_eq(lua_value(turret, "self.cfg.max_turn_rate"), 0.6, "the slow traverse")
	assert_eq(lua_value(turret, "self.cfg.range"), 30.0, "the gun's numbers under the turret's own")
	assert_eq(lua_value(turret, "self.cfg.host_retry_interval"), 0.5)

func test_scale_cells_meta_sizes_the_turret_on_spawn() -> void:
	var turret := await spawn_turret(Vector2.ZERO, 0.0, 128)
	assert_not_null(turret)
	if turret == null:
		return

	assert_eq(turret.get_meta(EnemyGun.META_SCALE_CELLS), 128, "the request meta rode onto the node")
	assert_eq(turret.art_cells, 128, "built at the hint")
	assert_gt(turret.get_cell_count().x, int(128 * 0.9), "cells across follow the hint")
	assert_gt(turret.get_active_cell_count(), 3500)
	assert_true(turret.has_barrel())
	assert_gt(turret.barrel.get_cell_count().x, turret.get_cell_count().x, "the barrel's own grid is longer than the mount is wide")
	var muzzle_reach := turret.barrel.to_global(turret.muzzle_local).distance_to(turret.to_global(turret.pivot_local))
	assert_gt(muzzle_reach, 64.0 * cell_px(), "the muzzle past the mount's edge at this size")
	assert_almost_eq(turret.get_node("PlayerSensor").radius, 60.0 * 128.0 / 96.0, 0.01, "the sensor grows with it")

	var ids: Array = world.get_joint_ids()
	assert_eq(ids.size(), 1, "pinned")

func test_turret_traverses_slowly_then_fires_the_cannon() -> void:
	# behind the turret: a half turn to make at 0.6 rad/s
	add_player(Vector2(12.0, 0.0))
	var turret := await spawn_turret(Vector2.ZERO, PI)
	assert_not_null(turret)
	if turret == null:
		return

	assert_eq(turret.state_machine.get_state(), "track", "seen, facing away")
	var start := turret.barrel.global_rotation
	var peak_spin := 0.0
	# headless frames may run several physics ticks, so the swing is
	# measured against the ticks that really ran
	var ticks := TickCounter.new()
	arena.add_child(ticks)

	for i in 60:
		await wait_physics_frames(1)
		peak_spin = maxf(peak_spin, absf(turret.barrel.angular_velocity))

	var elapsed := float(ticks.ticks) / Engine.physics_ticks_per_second
	assert_eq(turret.state_machine.get_state(), "track", "still turning after %.2f s" % elapsed)
	assert_lte(peak_spin, 0.6 + 0.05, "the barrel's spin is capped at max_turn_rate")
	var turned := absf(Steering.wrap_angle(turret.barrel.global_rotation - start))
	assert_gt(turned, 0.1, "moved")
	assert_lte(turned, 0.6 * elapsed + 0.15, "but only about max_turn_rate worth over %.2f s" % elapsed)
	assert_almost_eq(Steering.wrap_angle(turret.global_rotation - PI), 0.0, deg_to_rad(5.0), "the mount holds")

	var shot := {}
	turret.weapon.fired.connect(func(bullet: Node2D):
		if shot.is_empty():
			shot["at"] = bullet.global_position
			shot["muzzle"] = turret.barrel.to_global(turret.muzzle_local)
			shot["props"] = bullet.props)

	for i in 720:
		await wait_physics_frames(1)
		if not shot.is_empty():
			break

	assert_eq(turret.state_machine.get_state(), "fire", "swung onto the player and pulled the trigger")
	assert_false(shot.is_empty(), "the cannon fired")
	if shot.is_empty():
		return

	assert_eq(shot["props"], TURRET_CANNON, "the turret cannon's bullet")
	assert_lt(shot["at"].distance_to(shot["muzzle"]), 2.0 * cell_px(), "from the barrel's muzzle")
	assert_gt(shot["at"].distance_to(turret.to_global(turret.pivot_local)), 20.0 * cell_px(), "far from the mount's center")
	assert_gt(shot["at"].distance_to(turret.to_global(turret.pivot_local)), (turret.layout["ring_outer"] + 8.0) * cell_px(), "out past the ring")

func test_turret_speaks_as_turret_when_the_player_shows() -> void:
	Dialog.clear()
	var turret := await spawn_turret(Vector2.ZERO)
	assert_not_null(turret)
	if turret == null:
		return

	add_player(Vector2(10.0, 0.0))
	await wait_physics_frames(3)

	var texts := Dialog.queued_texts()
	texts.append(Dialog.current_text())
	assert_true(texts.has("Contact. Traversing to bearing."), "the greeting is on screen or waiting: %s" % [texts])
	assert_eq(CharacterRegistry.find_or_placeholder(&"turret").id, &"turret", "speaks under the turret id, a placeholder until a Character .tres exists")

# counts the physics ticks that ran while a test waited
class TickCounter extends Node:
	var ticks := 0

	func _physics_process(_delta: float) -> void:
		ticks += 1
