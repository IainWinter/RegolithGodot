extends GutTest

# the gun: an EnemyGun running gun.lua, a ring mount with a barrel part
# pinned to its center. it turns the barrel onto the player while the
# mount holds still, fires from the barrel's muzzle once aimed, in range
# and with a clear line, finds its host over a world joint (the barrel is
# not one) and obeys the host's trigger. built at another size from the
# scale_cells meta the spawner copies on

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const GUN_SCENE := "res://game/scenes/enemies/EnemyGun.tscn"

# a host that can hold the gun's trigger
const HOST_SOURCE := """
extends RegolithSprite
var gun_fire := true
"""

var arena: Node2D
var world: RegolithWorld

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
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

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

# the body takes the node transform as it enters the tree, so the facing
# is set before add_child. the barrel starts along the mount's facing
func add_gun(units: Vector2, facing := 0.0, scale_cells := 0) -> EnemyGun:
	var gun: EnemyGun = load(GUN_SCENE).instantiate()
	gun.position = units * ppu()
	gun.rotation = facing

	if scale_cells > 0:
		gun.set_meta(EnemyGun.META_SCALE_CELLS, scale_cells)

	arena.add_child(gun)
	return gun

# a plain sprite shaped like the gun's mount with a gun_fire property, no
# script logic and no barrel
func add_host(units: Vector2) -> RegolithSprite:
	var host: RegolithSprite = load(GUN_SCENE).instantiate()
	var script := GDScript.new()
	script.source_code = HOST_SOURCE
	script.reload()
	host.set_script(script)
	host.position = units * ppu()
	arena.add_child(host)
	return host

func add_wall(units: Vector2) -> RegolithSprite:
	var wall := RegolithSprite.new()
	wall.dynamic = false
	wall.position = units * ppu()
	arena.add_child(wall)
	wall.create_blank(Vector2i(32, 96))
	wall.fill_rect(Rect2i(0, 0, 32, 96), Color.GRAY, RegolithSprite.CELL_FILLED, 0)
	return wall

func lua_value(gun: EnemyScripted, expression: String) -> Variant:
	assert_eq(Ai.lua.run("__probe = (function(self) return %s end)(__instance(%d))" % [expression, gun.ai_id]), "")
	return Ai.lua.get_global("__probe")

# the barrel's tip in world pixels
func muzzle_pixels(gun: EnemyGun) -> Vector2:
	return gun.barrel.to_global(gun.muzzle_local)

# fires the gun at a player and returns the first shot's spawn spot and the
# barrel's muzzle at that moment, {} when it never fired
func first_shot(gun: EnemyGun, frames: int) -> Dictionary:
	var shot := {}
	gun.weapon.fired.connect(func(bullet: Node2D):
		if shot.is_empty():
			shot["at"] = bullet.global_position
			shot["muzzle"] = muzzle_pixels(gun)
			shot["pivot"] = gun.to_global(gun.pivot_local))

	for i in frames:
		await wait_physics_frames(1)
		if not shot.is_empty():
			break

	return shot

func test_gun_is_scripted_with_its_states() -> void:
	var gun := add_gun(Vector2.ZERO)
	await wait_physics_frames(2)
	assert_eq(gun.ai_class, "gun")
	assert_gt(gun.ai_id, 0)
	assert_true(gun.is_in_group("gun"))
	assert_not_null(gun.weapon)
	assert_eq(gun.weapon.get_parent(), gun, "the weapon stays on the mount so its shots skip the ring")
	assert_eq(gun.state_machine.get_states(), PackedStringArray(["idle", "track", "fire"]))
	assert_eq(gun.state_machine.get_state(), "idle", "no player reported")
	assert_eq(lua_value(gun, "self.cfg.range"), 10.0, "the original Gun numbers")
	assert_eq(lua_value(gun, "self.cfg.muzzle"), 0.4)
	assert_eq(lua_value(gun, "self.cfg.aim_tolerance"), 0.2)

func test_gun_is_a_mount_and_a_barrel_on_a_pin_joint() -> void:
	var gun := add_gun(Vector2.ZERO, 0.5)
	await wait_physics_frames(2)

	assert_true(gun.is_loaded(), "the mount is in the sim")
	assert_gt(gun.count_cells_of_type(RegolithSprite.CELL_CORE), 0, "the mount carries the core")
	assert_eq(gun.art_cells, 32, "the gun art is 32 across")
	assert_true(gun.has_barrel(), "a barrel part")

	var barrel := gun.barrel
	assert_eq(barrel.get_parent(), gun, "the barrel is a part of the gun node")
	assert_true(barrel.is_loaded())
	assert_true(barrel.is_in_group("gun"), "the barrel is a gun for line of sight")
	assert_true(barrel.is_in_group("regolith"))
	assert_gt(barrel.get_active_cell_count(), 20, "above the engine's island floor")
	assert_eq(barrel.count_cells_of_type(RegolithSprite.CELL_CORE), 0, "only the mount has a core")
	assert_almost_eq(barrel.global_rotation, 0.5, 0.01, "the barrel starts along the mount's facing")

	var ids: Array = world.get_joint_ids()
	assert_eq(ids.size(), 1, "one pin joint")
	if ids.size() == 1:
		var sprites: Array = world.get_joint_sprites(ids[0])
		assert_true(sprites.has(gun) and sprites.has(barrel), "between the mount and the barrel")
		assert_eq(gun.joint_id, ids[0])

	var pivot: Vector2 = gun.to_global(gun.pivot_local)
	assert_lt(pivot.distance_to(gun.get_center_of_mass()), cell_px() * 1.5, "the pin sits on the mount's center of mass")
	assert_gt(muzzle_pixels(gun).distance_to(pivot), 8.0 * cell_px(), "the muzzle is out along the barrel")

	assert_eq(Ai.jointed(gun), [barrel], "the runtime sees the barrel across the joint")
	await wait_physics_frames(int(0.5 * 60.0) + 10)
	assert_null(lua_value(gun, "self.host"), "the barrel is not taken as a host")
	assert_true(lua_value(gun, "self.node:is_part(self:jointed()[1])"))

func test_barrel_turns_onto_the_player_while_the_mount_stays() -> void:
	var player := add_player(Vector2(6.0, 0.0))
	var gun := add_gun(Vector2.ZERO, 2.0)
	await wait_physics_frames(2)
	assert_gt(absf(Steering.wrap_angle(gun.barrel.global_rotation)), 1.0, "starts facing away")
	assert_eq(gun.state_machine.get_state(), "track", "seen, not aimed yet")

	var shot := await first_shot(gun, 240)

	assert_true(gun.weapon.triggered, "the barrel swung onto the player and pulled the trigger")
	assert_eq(gun.state_machine.get_state(), "fire")
	assert_lt(absf(Steering.wrap_angle(gun.barrel.global_rotation)), 0.2 + 0.05, "the barrel faces the player within aim_tolerance")
	assert_almost_eq(Steering.wrap_angle(gun.global_rotation - 2.0), 0.0, deg_to_rad(5.0), "the mount stayed within a few degrees")
	assert_false(shot.is_empty(), "gun fired along the barrel")
	assert_true(is_instance_valid(player))

func test_shots_leave_the_barrel_muzzle() -> void:
	add_player(Vector2(6.0, 0.0))
	var gun := add_gun(Vector2.ZERO, 0.3)
	await wait_physics_frames(2)

	var shot := await first_shot(gun, 240)
	assert_false(shot.is_empty(), "fired")
	if shot.is_empty():
		return

	assert_lt(shot["at"].distance_to(shot["muzzle"]), 2.0 * cell_px(), "the bullet spawns at the barrel tip")
	assert_gt(shot["at"].distance_to(shot["pivot"]), 8.0 * cell_px(), "not at the mount's center")
	assert_gt(shot["at"].distance_to(shot["pivot"]), (gun.layout["ring_outer"] + 4.0) * cell_px(), "from the tip out past the ring")
	assert_almost_eq(gun.weapon.fire_origin(), muzzle_pixels(gun), Vector2.ONE * 0.5, "the weapon's origin follows the muzzle")

func test_gun_holds_fire_out_of_range_or_behind_a_wall() -> void:
	var player := add_player(Vector2(20.0, 0.0))
	var gun := add_gun(Vector2.ZERO)
	await wait_physics_frames(60)
	assert_false(gun.weapon.triggered, "player beyond range")
	assert_eq(gun.state_machine.get_state(), "track", "seen but held back")

	player.free()
	add_player(Vector2(8.0, 0.0))
	add_wall(Vector2(4.0, 0.0))
	await wait_physics_frames(90)
	assert_false(gun.weapon.triggered, "wall blocks the muzzle line")
	assert_eq(gun.state_machine.get_state(), "track")

func test_host_can_hold_the_trigger() -> void:
	add_player(Vector2(6.0, 0.0))
	var gun := add_gun(Vector2.ZERO)
	var host := add_host(Vector2(0.0, 3.0))
	await wait_physics_frames(2)

	world.add_distance_joint(gun, host, gun.global_position, host.global_position, 3.0)
	# a loose gun looks for a host again every host_retry_interval
	await wait_physics_frames(int(0.5 * 60.0) + 10)

	assert_true(Ai.jointed(gun).has(host), "the joint partner is what the runtime reports")
	assert_eq(lua_value(gun, "self.host"), host, "the script took the joint partner as host, not its barrel")

	for i in 240:
		await wait_physics_frames(1)
		if gun.weapon.triggered:
			break

	assert_true(gun.weapon.triggered, "a host with gun_fire true lets it fire")

	host.gun_fire = false
	await wait_physics_frames(3)
	assert_false(gun.weapon.triggered, "the host holds the trigger")
	assert_eq(gun.state_machine.get_state(), "track")
	assert_eq(lua_value(gun, "self:host_fires()"), false)

func test_scale_cells_meta_rebuilds_the_parts_at_that_size() -> void:
	var gun := add_gun(Vector2.ZERO, 0.0, 64)
	await wait_physics_frames(2)

	assert_eq(gun.art_cells, 64)
	assert_true(gun.is_loaded())
	assert_gte(gun.get_cell_count().x, 64, "the mount grid holds 64 cells across")
	assert_gt(gun.count_cells_of_type(RegolithSprite.CELL_CORE), 0, "the core pods came along")
	assert_true(gun.has_barrel())
	assert_gt(gun.barrel.get_active_cell_count(), 200, "a bigger barrel")
	assert_gt(muzzle_pixels(gun).distance_to(gun.to_global(gun.pivot_local)), 16.0 * cell_px(), "the muzzle moved out with the size")
	assert_eq(gun.get_node("PlayerSensor").radius, 60.0, "the sensor radius scaled with the parts")

# the farthest cell of a sprite from the pivot along the barrel's facing, cells
func reach_cells(sprite: RegolithSprite, gun: EnemyGun) -> float:
	var pivot := gun.to_global(gun.pivot_local)
	var direction := gun.aim_direction()
	var reach := 0.0

	for step in 400:
		var d := step * 0.5
		if sprite.has_cell(sprite.world_to_cell(pivot + direction * d * cell_px())):
			reach = d

	return reach

func test_barrel_reaches_past_the_mount() -> void:
	var gun := add_gun(Vector2.ZERO, 0.7)
	await wait_physics_frames(2)
	assert_eq(gun.multisprite, "res://game/images/multisprites/gun.json", "built from the gun document")
	assert_true(gun.has_barrel())

	var ring: float = gun.layout["ring_outer"]
	var barrel_reach := reach_cells(gun.barrel, gun)
	var mount_reach := reach_cells(gun, gun)
	# the ring is a hexagon, ring_outer its inradius
	assert_lte(mount_reach, ring / GunArt.COS30 + 1.0, "the ring ends at its outer radius")
	assert_gt(barrel_reach, ring + 8.0, "the tube sticks out well past the ring: %.1f cells against %.1f" % [barrel_reach, ring])
	assert_true(gun.barrel.has_cell(gun.barrel.world_to_cell(gun.to_global(gun.pivot_local))), "the barrel's hub sits on the pivot")
	assert_gt(muzzle_pixels(gun).distance_to(gun.to_global(gun.pivot_local)), barrel_reach * cell_px(), "the muzzle is past the tip")

func test_mount_and_barrel_rest_on_the_pin_without_pushing_apart() -> void:
	var gun := add_gun(Vector2.ZERO, 0.4)
	await wait_physics_frames(2)
	assert_true(gun.has_barrel())
	assert_false(world.get_joint_collide_connected(gun.joint_id), "the pin does not collide connected")

	var start := gun.get_center_of_mass()
	var start_rotation := gun.global_rotation
	var barrel_rotation := gun.barrel.global_rotation
	var widest := 0.0

	for i in 120:
		await wait_physics_frames(1)
		var anchors := world.get_joint_anchors(gun.joint_id)
		widest = maxf(widest, anchors[0].distance_to(anchors[1]))

	assert_lt(widest, cell_px(), "the pivot stays within a cell")
	assert_lt(gun.get_center_of_mass().distance_to(start), cell_px(), "the mount does not drift")
	assert_almost_eq(gun.global_rotation, start_rotation, 0.02, "nor turn")
	assert_almost_eq(gun.barrel.global_rotation, barrel_rotation, 0.05, "the idle barrel is not shoved round")
	assert_lt(gun.barrel.linear_velocity.length(), 0.05, "and rests")

func test_scene_carries_an_editor_only_parts_preview() -> void:
	var gun: EnemyGun = load(GUN_SCENE).instantiate()
	var preview := gun.get_node("PartsPreview") as MultiSpritePreview
	assert_not_null(preview, "the scene shows the barrel in the editor")
	assert_eq(preview.document_path(), "res://game/images/multisprites/gun.json", "drawn from the gun's own document")

	arena.add_child(gun)
	await wait_physics_frames(2)
	assert_false(gun.has_node("PartsPreview"), "gone once the game runs")
	assert_true(gun.has_barrel(), "the real barrel instead")
