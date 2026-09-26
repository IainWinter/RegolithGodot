extends GutTest

# the player cloud in the main scene: losing the core hides the hull and
# starts the cloud, so does the core blowing with cells left and the whole
# hull going at once, the cloud moves faster and cannot shoot, draws its
# particles through an own additive ParticleEffect node at the core's spot
# and its lightning from the world's parent, dies after death_time unless
# a core is collected, which rebuilds the hull, and dies at once when a
# cell is knocked off the hidden hull after the invincible time

const CLOUD_PROPS := preload("res://game/config/effects/player_cloud.tres")
const FIRE_PROPS := preload("res://game/config/effects/player_cloud_fire.tres")
const BURST_PROPS := preload("res://game/config/effects/player_cloud_burst.tres")
const LIGHTNING_PROPS := preload("res://game/config/effects/player_cloud_lightning.tres")
const ADDITIVE_MATERIAL := preload("res://game/config/effects/player_cloud_additive_material.tres")
const PARTICLE_SCENE := preload("res://game/scenes/effects/ParticleEffect.tscn")

var main: Node2D
var player: Player
var cloud: PlayerCloud
var effects: EffectSpawner

func before_each() -> void:
	main = load("res://game/scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	player = main.get_node("Player")
	cloud = player.cloud
	effects = main.get_node("EffectSpawner")
	await wait_physics_frames(3)

func after_each() -> void:
	Input.action_release("shoot")
	Input.action_release("move_right")
	main.free()

func core_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var count := player.get_cell_count()

	for y in count.y:
		for x in count.x:
			if player.get_cell_type(Vector2i(x, y)) == RegolithSprite.CELL_CORE:
				cells.append(Vector2i(x, y))

	return cells

func remove_core() -> void:
	for cell in core_cells():
		player.remove_cell(cell)

func enter_cloud() -> void:
	remove_core()
	await wait_physics_frames(6)
	assert_true(cloud.is_cloud, "cloud entered")

# the cloud's own particle node, there once it has drawn a frame
func particles() -> ParticleEffect:
	return cloud.particles

func test_player_carries_a_cloud_with_the_original_numbers() -> void:
	assert_not_null(cloud, "Player.tscn has the PlayerCloud child")
	assert_eq(cloud.player, player)
	assert_false(cloud.is_cloud)
	assert_eq(cloud.cloud, CLOUD_PROPS)
	assert_eq(cloud.fire, FIRE_PROPS)
	assert_eq(cloud.burst, BURST_PROPS)
	assert_eq(cloud.lightning, LIGHTNING_PROPS)
	assert_not_null(cloud.lightning_material)
	assert_eq(cloud.particles_scene, PARTICLE_SCENE, "draws through its own copy of the shared particle node")
	assert_eq(cloud.additive_material, ADDITIVE_MATERIAL)

	assert_eq(cloud.cloud_speed, 8.0)
	assert_eq(cloud.death_time, 4.0)
	assert_eq(cloud.invincible_time, 1.0)

	# game/particles/player_cloud of the original
	assert_eq(Vector2i(CLOUD_PROPS.count_min, CLOUD_PROPS.count_max), Vector2i(6, 6))
	assert_eq(CLOUD_PROPS.offset_min, Vector2(-0.2, -0.2))
	assert_eq(CLOUD_PROPS.offset_max, Vector2(0.2, 0.2))
	assert_eq(Vector2(CLOUD_PROPS.life_min, CLOUD_PROPS.life_max), Vector2(0.5, 1.0))
	assert_eq(Vector2(CLOUD_PROPS.damping_min, CLOUD_PROPS.damping_max), Vector2(7.0, 28.0))
	assert_eq(CLOUD_PROPS.velocity_min, Vector2(-10, -10))
	assert_eq(CLOUD_PROPS.velocity_max, Vector2(10, 10))
	assert_eq(Vector2(CLOUD_PROPS.angular_velocity_min, CLOUD_PROPS.angular_velocity_max), Vector2(-3.0, 3.6))
	assert_eq(CLOUD_PROPS.scale_begin_min, Vector2(0.125, 0.125))
	assert_eq(CLOUD_PROPS.scale_end, Vector2.ZERO)
	assert_almost_eq(CLOUD_PROPS.scale_factor, 4.056, 0.001)
	assert_eq(CLOUD_PROPS.color_begin, Color(1, 0.6, 0, 1))
	assert_eq(CLOUD_PROPS.color_end, Color(0, 0, 1, 0.1))
	assert_almost_eq(CLOUD_PROPS.color_factor, 0.698, 0.001)
	assert_gt(CLOUD_PROPS.emissive, 0.0, "the cloud glows")

	# the fire of PlayerCloudEffectSystem::tick
	assert_eq(FIRE_PROPS.emissive, 4.0)
	assert_eq(FIRE_PROPS.velocity_min, Vector2(-3, -3))
	assert_eq(FIRE_PROPS.velocity_max, Vector2(3, 3))
	assert_eq(Vector2(FIRE_PROPS.life_min, FIRE_PROPS.life_max), Vector2(0.2, 0.6))
	assert_eq(FIRE_PROPS.damping_min, 0.05)
	assert_eq(FIRE_PROPS.angular_damping, 0.0, "the fire spins undamped")
	assert_eq(Vector2(FIRE_PROPS.angular_velocity_min, FIRE_PROPS.angular_velocity_max), Vector2(-6.0, 6.0))
	assert_eq(FIRE_PROPS.scale_begin_min, Vector2(0.1, 0.1))
	assert_eq(FIRE_PROPS.scale_begin_max, Vector2(0.2, 0.2))
	assert_eq(FIRE_PROPS.color_end, Color(0.6, 0.05, 0.05, 0))
	assert_eq(cloud.fire_growth, 0.0, "danger shows as color, not more fire")

	# spawn_player_cloud_dead_effect
	assert_eq(Vector2i(BURST_PROPS.count_min, BURST_PROPS.count_max), Vector2i(100, 100))
	assert_eq(Vector2(BURST_PROPS.life_min, BURST_PROPS.life_max), Vector2(5.0, 5.0))
	assert_eq(Vector2(BURST_PROPS.damping_min, BURST_PROPS.damping_max), Vector2(2.0, 8.0))
	assert_eq(BURST_PROPS.velocity_min, Vector2(-10, -10))
	assert_eq(BURST_PROPS.velocity_max, Vector2(10, 10))

	assert_eq(LIGHTNING_PROPS.point_count, 16)
	assert_eq(LIGHTNING_PROPS.lifetime, 0.2)
	assert_almost_eq(LIGHTNING_PROPS.emission, 0.3, 0.001)
	assert_eq(LIGHTNING_PROPS.burn_strength, 0, "the cloud bolts are visual")

func test_additive_material_adds_the_particle_frame() -> void:
	var shader: Shader = ADDITIVE_MATERIAL.shader
	assert_not_null(shader)
	assert_string_contains(shader.code, "blend_premul_alpha", "src + dst * (1 - a) with a = 0 is One / One")
	assert_string_contains(shader.code, "INSTANCE_CUSTOM.z", "the atlas frame pick of the shared canvas material")
	assert_string_contains(shader.code, ", 0.0);", "alpha out is zero, nothing is covered")
	assert_eq(ADDITIVE_MATERIAL.get_shader_parameter("h_frames"), 4)
	assert_eq(ADDITIVE_MATERIAL.get_shader_parameter("v_frames"), 2)

func test_cloud_sits_on_the_core_not_the_node_origin() -> void:
	var core := EffectSpawner.effect_origin(player)
	assert_true(cloud.has_origin, "origin recorded with the snapshot")
	assert_almost_eq(cloud.origin(), core, Vector2.ONE * 0.01)
	assert_gt(cloud.origin().distance_to(player.global_position), 4.0, "the node origin is off the core")

	await enter_cloud()
	assert_almost_eq(cloud.origin(), core, Vector2.ONE * 0.01, "the spot stays after the core is gone")
	assert_eq(player.count_cells_of_type(RegolithSprite.CELL_CORE), 0)

func test_losing_the_core_enters_the_cloud() -> void:
	watch_signals(cloud)
	var cells := player.get_active_cell_count()
	await enter_cloud()

	assert_signal_emit_count(cloud, "entered", 1)
	assert_false(player.visible, "hull hidden")
	assert_true(is_instance_valid(player), "the hull stays in the sim as the cloud's collider")
	assert_gt(player.get_active_cell_count(), 0)
	assert_lt(player.get_active_cell_count(), cells)
	assert_almost_eq(cloud.invincible_timer, 1.0, 0.2, "invincible timer running")
	assert_true(player.is_cloud())
	assert_eq(player.move_speed(), 8.0, "cloud speed")

# the SpriteCoreExplodedEvent of the original: a core damaged past
# core_explode_damage blows with cells still on it, and that is the cloud
func test_the_core_blowing_enters_the_cloud_with_core_cells_left() -> void:
	watch_signals(cloud)
	var exploded := [0]
	player.core_exploded.connect(func(_p, _power, type): exploded[0] += 1 if type == RegolithSprite.CELL_CORE else 0)
	var cells := core_cells()
	assert_gt(cells.size(), 4, "a core of several cells")

	for cell in cells:
		if cloud.is_cloud:
			break
		player.remove_cell(cell)
		await wait_physics_frames(2)

	assert_eq(exploded[0], 1, "the core blew")
	assert_true(cloud.is_cloud)
	assert_signal_emit_count(cloud, "entered", 1)
	assert_gt(player.count_cells_of_type(RegolithSprite.CELL_CORE), 0, "before the last core cell went")

# a ship shredded in one commit: no cell is left for Player.check_core to
# count, the cloud starts from the removal itself
func test_the_whole_hull_going_at_once_enters_the_cloud() -> void:
	watch_signals(cloud)
	player.remove_all_cells()
	await wait_physics_frames(4)

	assert_true(cloud.is_cloud, "cloud entered with nothing left of the hull")
	assert_signal_emit_count(cloud, "entered", 1)
	assert_eq(player.get_active_cell_count(), 0)
	assert_true(is_instance_valid(player))

func test_cloud_draws_through_its_own_additive_node_and_cannot_shoot() -> void:
	assert_null(particles(), "no particle node before the cloud")
	await enter_cloud()
	await wait_process_frames(3)

	var node := particles()
	assert_not_null(node, "the cloud made its particle node")
	assert_ne(node, effects.particles, "not the shared one")
	assert_eq(node.get_parent(), main, "under the world's parent")
	assert_eq(node.material, ADDITIVE_MATERIAL, "additive over the scene")
	assert_eq(node.process_mode, Node.PROCESS_MODE_INHERIT, "a game effect, it freezes with the pause menu")
	assert_true(node.ready_to_emit)
	assert_gt(node.count_of(cloud.cloud), 0, "cloud particles every frame")
	assert_gt(node.count_of(cloud.fire), 0, "fire particles every frame")
	assert_eq(effects.particles.count_of(cloud.cloud), 0, "nothing through the shared node")

	Input.action_press("shoot")
	await wait_process_frames(2)
	assert_false(player.weapon.triggered, "no shooting as a cloud")
	Input.action_release("shoot")

# the cloud reddens as the timer runs down, one fire particle a frame all
# along, the low core alarm carries the timing
func test_cloud_reddens_with_the_danger() -> void:
	await enter_cloud()
	await wait_process_frames(2)
	var base := cloud.cloud.color_begin
	var start := cloud.cloud_color()
	assert_lt(base.g - start.g, 0.05, "its own color at the start, the timer has barely moved")
	assert_lt(cloud.fire.color_begin.g - cloud.fire_color().g, 0.05)

	var node := particles()
	var before: int = node.count_of(cloud.fire)
	await wait_process_frames(4)
	var calm: int = node.count_of(cloud.fire) - before
	assert_between(calm, 4, 8, "one fire particle a frame")

	cloud.death_timer = cloud.death_time * 0.9
	var hot := cloud.cloud_color()
	var want := base.lerp(cloud.danger_color, 0.9)
	assert_almost_eq(hot.r, want.r, 0.001, "nine tenths of the way to the danger color")
	assert_almost_eq(hot.g, want.g, 0.001)
	assert_almost_eq(hot.b, want.b, 0.001)
	assert_lt(hot.g, base.g, "greener parts drain")
	assert_gt(hot.r, 0.9, "red stays")
	assert_lt(cloud.fire_color().g, cloud.fire.color_begin.g, "the fire reddens too")

	before = node.count_of(cloud.fire)
	await wait_process_frames(4)
	var hot_count: int = node.count_of(cloud.fire) - before
	assert_between(hot_count, 4, 8, "still one fire particle a frame at full danger")

func test_lightning_arcs_out_past_a_quarter_of_the_timer() -> void:
	await enter_cloud()
	await wait_process_frames(3)
	assert_eq(cloud.strikes, 0, "no lightning early on")

	cloud.death_timer = cloud.death_time * 0.6
	await wait_process_frames(3)
	assert_gt(cloud.strikes, 0, "bolts once the danger passes a quarter")
	assert_not_null(cloud.lightning_node)
	assert_ne(cloud.lightning_node.get_parent(), player, "bolts draw outside the hidden hull")

# the cloud goes with the player node, so deaths are counted through a
# connection made while it is alive
func count_deaths() -> Array:
	var deaths := [0]
	cloud.died.connect(func(): deaths[0] += 1)
	return deaths

func test_cloud_dies_when_the_timer_runs_out() -> void:
	var deaths := count_deaths()
	await enter_cloud()
	await wait_process_frames(2)
	var node := particles()

	var emitted_before: int = node.emitted
	cloud.death_timer = cloud.death_time - 0.02
	await wait_physics_frames(4)

	assert_eq(deaths[0], 1, "died once")
	assert_eq(node.count_of(BURST_PROPS), 100, "the dead burst in every direction")
	assert_gte(node.emitted - emitted_before, 200, "plus the burst along the velocity")
	assert_false(is_instance_valid(player) and player.is_inside_tree(), "player gone")
	assert_true(is_instance_valid(node) and node.is_inside_tree(), "the burst outlives the cloud")

func test_collecting_holds_the_timer() -> void:
	await enter_cloud()
	cloud.collecting = true
	await wait_physics_frames(10)
	assert_eq(cloud.death_timer, 0.0, "a core flying in holds death off")
	cloud.collecting = false
	await wait_physics_frames(5)
	assert_gt(cloud.death_timer, 0.0)

func test_collecting_a_core_rebuilds_the_hull() -> void:
	watch_signals(cloud)
	var cells := player.get_active_cell_count()
	var cores := player.count_cells_of_type(RegolithSprite.CELL_CORE)
	await enter_cloud()
	await wait_process_frames(2)
	assert_eq(player.count_cells_of_type(RegolithSprite.CELL_CORE), 0)

	cloud.collect_core()
	await wait_physics_frames(3)

	assert_signal_emit_count(cloud, "left", 1)
	assert_false(cloud.is_cloud)
	assert_true(player.visible, "hull shown again")
	assert_eq(player.count_cells_of_type(RegolithSprite.CELL_CORE), cores, "core back")
	assert_eq(player.get_active_cell_count(), cells, "every cell back")
	assert_false(player.is_cloud())
	assert_eq(player.move_speed(), player.speed)
	assert_eq(particles().count_of(cloud.burst), 100, "the burst marks the change")

	Input.action_press("shoot")
	await wait_process_frames(2)
	assert_true(player.weapon.triggered, "shooting again")

func first_hull_cell() -> Vector2i:
	var count := player.get_cell_count()
	for y in count.y:
		for x in count.x:
			if player.has_cell(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func test_a_hit_on_the_cloud_kills_once_invincibility_is_over() -> void:
	var deaths := count_deaths()
	await enter_cloud()

	player.remove_cell(first_hull_cell())
	await wait_physics_frames(3)
	assert_eq(deaths[0], 0, "still invincible")

	cloud.invincible_timer = 0.0
	player.remove_cell(first_hull_cell())
	await wait_physics_frames(3)
	assert_eq(deaths[0], 1, "a cell off the hidden hull kills")
