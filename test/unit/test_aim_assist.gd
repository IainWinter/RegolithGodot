extends GutTest

# PlayerShoot's aim assist: the intercept solver, the fan of rays and its
# order, the hit cell over the center of mass, the lead on moving targets,
# the range cap, the debug lines and the gates on the player

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")

var arena: Node2D
var world: RegolithWorld
var ppu := 0.0

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)
	await wait_physics_frames(1)
	ppu = RegolithWorld.pixels_per_unit()

func after_each() -> void:
	arena.free()

# a one unit square block
func add_block(at: Vector2, dynamic := true) -> RegolithSprite:
	var block := RegolithSprite.new()
	block.dynamic = dynamic
	block.position = at
	arena.add_child(block)
	block.create_blank(Vector2i(32, 32))
	block.fill_rect(Rect2i(0, 0, 32, 32), Color.WHITE, RegolithSprite.CELL_FILLED, 0)
	return block

func cannon(degrees := 8.0) -> WeaponProps:
	var props := WeaponProps.new()
	props.speed = 16.0
	props.lifetime = 5.0
	props.aim_assist_degrees = degrees
	return props

func test_intercept_time_solves_head_on_and_still_targets() -> void:
	assert_almost_eq(AimAssist.solve_intercept_time(Vector2(100.0, 0.0), Vector2.ZERO, 50.0), 2.0, 0.001)
	assert_almost_eq(AimAssist.solve_intercept_time(Vector2(100.0, 0.0), Vector2(-10.0, 0.0), 40.0), 2.0, 0.001)
	assert_lt(AimAssist.solve_intercept_time(Vector2(100.0, 0.0), Vector2(200.0, 0.0), 50.0), 0.0, "no intercept on a faster target running away")

func test_fan_starts_at_the_center_and_alternates_outward() -> void:
	var rays := AimAssist.ray_directions(Vector2.RIGHT, deg_to_rad(8.0))
	assert_eq(rays.size(), AimAssist.RAYS)
	assert_almost_eq(rays[0].angle(), 0.0, 0.0001, "the center ray comes first")
	assert_almost_eq(rays[1].angle(), deg_to_rad(2.0), 0.0001, "then one step to the positive side")
	assert_almost_eq(rays[2].angle(), deg_to_rad(-2.0), 0.0001, "then one step to the other side")
	assert_almost_eq(rays[7].angle(), deg_to_rad(8.0), 0.0001, "the last pair reaches the half angle")
	assert_almost_eq(rays[8].angle(), deg_to_rad(-8.0), 0.0001)

func test_aim_assist_bends_toward_a_sprite_in_the_fan() -> void:
	var shooter := add_block(Vector2(0.0, 0.0))
	var rock := add_block(Vector2(400.0, 30.0), false)
	await wait_physics_frames(2)

	var props := cannon(8.0)
	var aim := AimAssist.apply(world, shooter, props, shooter.global_position, Vector2.RIGHT)
	assert_gt(aim.y, 0.0, "aim bent down toward the rock")
	assert_lt(absf(aim.angle()), deg_to_rad(8.0) + 0.01)

	props.aim_assist_degrees = 0.5
	var straight := AimAssist.apply(world, shooter, props, shooter.global_position, Vector2.RIGHT)
	assert_true(straight.is_equal_approx(Vector2.RIGHT) or straight.angle() < deg_to_rad(0.6), "a narrow fan misses the rock")
	assert_true(is_instance_valid(rock))

# the first ray in fan order wins, not the nearest sprite: a far rock on the
# positive side beats a near one on the other side
func test_first_ray_in_fan_order_wins_over_a_nearer_sprite() -> void:
	var shooter := add_block(Vector2.ZERO)
	var far := add_block(Vector2.from_angle(deg_to_rad(7.5)) * 8.0 * ppu, false)
	var near := add_block(Vector2.from_angle(deg_to_rad(-7.5)) * 6.0 * ppu, false)
	await wait_physics_frames(2)

	var aim := AimAssist.apply(world, shooter, cannon(30.0), Vector2.ZERO, Vector2.RIGHT)
	assert_gt(aim.y, 0.0, "bent onto the positive side rock, the far one")
	assert_gt(aim.length(), 7.0 * ppu, "and onto that rock's near face, not the nearer rock")
	assert_true(is_instance_valid(far) and is_instance_valid(near))

# a still target is aimed at the cell the ray hit, not its center of mass
func test_still_target_is_aimed_at_the_hit_cell() -> void:
	var shooter := add_block(Vector2.ZERO)
	var rock := add_block(Vector2(8.0 * ppu, 20.0), false)
	await wait_physics_frames(2)

	var range := minf(16.0 * 5.0, AimAssist.MAX_RANGE) * ppu
	var hit: Dictionary = world.ray_cast(Vector2.ZERO, Vector2.RIGHT * range, shooter)
	assert_false(hit.is_empty())
	assert_eq(hit["sprite"], rock)

	var aim := AimAssist.apply(world, shooter, cannon(8.0), Vector2.ZERO, Vector2.RIGHT)
	assert_true(aim.is_equal_approx(hit["position"]), "the hit cell center: %s vs %s" % [aim, hit["position"]])
	assert_lt(absf(aim.y), 3.0, "the near face on the center ray, not the rock's center 20 px down")

# a moving target gets the intercept lead in its direction of travel
func test_moving_target_is_led() -> void:
	var shooter := add_block(Vector2.ZERO, false)
	var rock := add_block(Vector2(8.0 * ppu, 0.0))
	rock.linear_velocity = Vector2(0.0, 2.0)
	await wait_physics_frames(2)

	var still: Dictionary = world.ray_cast(Vector2.ZERO, Vector2.RIGHT * AimAssist.MAX_RANGE * ppu, shooter)
	assert_false(still.is_empty())

	var aim := AimAssist.apply(world, shooter, cannon(8.0), Vector2.ZERO, Vector2.RIGHT)
	var hit_point: Vector2 = still["position"]
	var flight := hit_point.length() / (16.0 * ppu)
	var lead := 2.0 * ppu * flight
	assert_gt(aim.y, hit_point.y + lead * 0.5, "led down the way the rock moves")
	assert_lt(aim.y, hit_point.y + lead * 1.5)

# a spinning target's hit cell is followed around its center of mass
func test_spinning_target_lead_follows_the_spin() -> void:
	var shooter := add_block(Vector2.ZERO, false)
	var rock := add_block(Vector2(8.0 * ppu, 0.0))
	rock.angular_velocity = 1.0
	await wait_physics_frames(2)

	var aim := AimAssist.apply(world, shooter, cannon(8.0), Vector2.ZERO, Vector2.RIGHT)
	var com := rock.get_center_of_mass()
	# the near face cell sits at -x from the center of mass, a positive spin
	# rotates that offset toward -y
	assert_lt(aim.y, -5.0, "the near face cell swings to -y with a positive spin")
	assert_lt(aim.x, com.x, "and stays on the near half")

# the fan reaches min(speed * lifetime, 30) units and no further
func test_range_is_capped() -> void:
	var shooter := add_block(Vector2.ZERO)
	var beyond := add_block(Vector2(31.5 * ppu, 0.0), false)
	await wait_physics_frames(2)

	var props := cannon(8.0)
	assert_true(AimAssist.apply(world, shooter, props, Vector2.ZERO, Vector2.RIGHT).is_equal_approx(Vector2.RIGHT), "past 30 units the aim is untouched")

	beyond.free()
	var within := add_block(Vector2(28.0 * ppu, 0.0), false)
	await wait_physics_frames(2)

	var aim := AimAssist.apply(world, shooter, props, Vector2.ZERO, Vector2.RIGHT)
	assert_gt(aim.length(), 27.0 * ppu, "at 28 units the rock is reached")

	props.lifetime = 1.0
	assert_true(AimAssist.apply(world, shooter, props, Vector2.ZERO, Vector2.RIGHT).is_equal_approx(Vector2.RIGHT), "a short lived shot does not reach it")
	assert_true(is_instance_valid(within))

# zero speed and a zero aim leave the direction alone
func test_degenerate_inputs_pass_through() -> void:
	var shooter := add_block(Vector2.ZERO)
	add_block(Vector2(8.0 * ppu, 0.0), false)
	await wait_physics_frames(2)

	var props := cannon(8.0)
	assert_eq(AimAssist.apply(world, shooter, props, Vector2.ZERO, Vector2.ZERO), Vector2.ZERO)
	props.speed = 0.0
	assert_eq(AimAssist.apply(world, shooter, props, Vector2.ZERO, Vector2.RIGHT), Vector2.RIGHT)

func test_fan_draws_under_the_aim_assist_debug_name() -> void:
	var draw := get_tree().get_first_node_in_group("regolith_debug_draw") as RegolithDebugDraw
	assert_not_null(draw, "the DebugDraw autoload")

	if draw == null:
		return

	var shooter := add_block(Vector2.ZERO)
	await wait_physics_frames(2)
	draw.visible = true
	draw.set_name_enabled(RegolithDebugDraw.AIM_ASSIST, true)

	var peak := 0

	for i in 3:
		AimAssist.apply(world, shooter, cannon(8.0), Vector2.ZERO, Vector2.RIGHT)
		await get_tree().process_frame
		peak = maxi(peak, draw.get_line_count())

	draw.visible = false
	assert_gte(peak, AimAssist.RAYS, "every missed ray is drawn")

# the player gates the assist on the setting and the weapon's degrees and
# aims from where the shot leaves
func test_player_gates_and_aims_from_the_fire_origin() -> void:
	arena.free()
	arena = load("res://game/scenes/Main.tscn").instantiate()
	get_tree().root.add_child(arena)
	await wait_physics_frames(3)

	var player: Player = arena.get_node("Player")
	var settings := get_node("/root/GameSettings")
	var before: bool = settings.aim_assist

	assert_true(player.aim_origin().is_equal_approx(player.weapon.fire_origin()))
	assert_almost_eq(player.aim_direction().length(), 1.0, 0.0001)

	settings.aim_assist = false
	assert_true(player.assisted_aim().is_equal_approx(player.aim_direction()), "off in the settings")

	settings.aim_assist = true
	var props: WeaponProps = player.weapon.props.duplicate()
	props.aim_assist_degrees = 0.0
	player.weapon.props = props
	assert_true(player.assisted_aim().is_equal_approx(player.aim_direction()), "off on the weapon")

	settings.aim_assist = before
