extends GutTest

# the gameplay visuals: one ParticleEffect node under the EffectSpawner
# draws every effect off the particles atlas in one draw call, each props
# gets a slot in the uniform arrays of its own material, smoke props pick
# the atlas puffs and sparks the square, a weapon's shot flashes its muzzle
# effects and bursts the explosion when it goes off, a missile trails
# exhaust once its motor runs, and a cannon bullet that hits the rock
# sparks and shows its tapered trail

const ATLAS_PATH := "res://game/images/effects/particles_atlas.png"
const ATLAS_SIZE := Vector2i(128, 64)
const SMOKE_FRAMES := Vector2i(0, 5)
const SQUARE_FRAME := 6

const MISSILE_PROPS := preload("res://game/config/weapons/missiles.tres")
const FORCE_PROPS := preload("res://game/config/weapons/force_gun.tres")
const CANNON_PROPS := preload("res://game/config/weapons/default_cannon.tres")
const SHARED_MATERIAL := preload("res://game/shaders/regolith_particles_material.tres")
const CANVAS_MATERIAL_PATH := "res://game/shaders/regolith_particles_canvas_material.tres"
const CANVAS_SHADER_PATH := "res://game/shaders/regolith_particles_canvas.gdshader"
const LIGHTNING_SPARK := preload("res://game/config/effects/lightning_spark.tres")
const LIGHTNING_HIT_SPARK := preload("res://game/config/effects/lightning_hit_spark.tres")
const CORE_SPARK := preload("res://game/config/items/core_spark.tres")
const BOLT_HIT_LIGHTNING := preload("res://game/config/weapons/bolt_hit_lightning.tres")
const BALL_ZAP_LIGHTNING := preload("res://game/config/weapons/ball_zap_lightning.tres")

const SMOKE_PROPS := [
	preload("res://game/config/effects/explosion_smoke.tres"),
	preload("res://game/config/effects/cannon_muzzle_smoke.tres"),
	preload("res://game/config/effects/missile_smoke.tres"),
	preload("res://game/config/effects/bomb_fuse_puff.tres"),
]

const SQUARE_PROPS := [
	preload("res://game/config/effects/explosion_spark.tres"),
	preload("res://game/config/effects/hit_spark.tres"),
	preload("res://game/config/effects/cannon_muzzle_spark.tres"),
	preload("res://game/config/effects/cannon_casing.tres"),
	preload("res://game/config/effects/missile_flame.tres"),
	preload("res://game/config/effects/missile_launch_puff.tres"),
	preload("res://game/config/effects/force_launch_puff.tres"),
	preload("res://game/config/effects/lightning_spark.tres"),
	preload("res://game/config/effects/lightning_hit_spark.tres"),
	preload("res://game/config/items/core_spark.tres"),
]

var main: Node2D
var world: RegolithWorld
var player: Player
var rock: RegolithSprite
var effects: EffectSpawner
var particles: ParticleEffect

func before_each() -> void:
	main = load("res://game/scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	world = main.get_node("RegolithWorld")
	player = main.get_node("Player")
	rock = main.get_node("Rock")
	effects = main.get_node("EffectSpawner")
	particles = effects.particles
	await wait_physics_frames(3)

func after_each() -> void:
	main.free()

func spawner_props() -> Array:
	return [effects.explosion_spark, effects.explosion_smoke, effects.hit_spark, effects.missile_flame, effects.missile_smoke, effects.bomb_fuse_puff]

# one straight shot from the named player weapon, aimed away from the rock
func fire_one(weapon_name: String) -> Node2D:
	var weapon: Weapon = player.get_node(weapon_name)
	var props: WeaponProps = weapon.props.duplicate()
	props.shots_per_ammo = 1
	props.inaccuracy_angle = 0.0
	props.inaccuracy_tangent = 0.0
	weapon.props = props

	var spawned: Array = []
	weapon.fired.connect(func(bullet: Node2D): spawned.append(bullet))
	var away := (player.global_position - rock.global_position).normalized()
	weapon.set_fire_state(true, away)
	await wait_physics_frames(1)
	weapon.set_fire_state(false, away)

	assert_eq(spawned.size(), 1, "one shot from %s" % weapon_name)
	return spawned[0] if not spawned.is_empty() else null

func test_atlas_exists_with_the_expected_layout() -> void:
	assert_true(FileAccess.file_exists(ATLAS_PATH), "atlas png present, rerun tools/MakeParticlesAtlas.gd")
	var atlas: Texture2D = load(ATLAS_PATH)
	assert_not_null(atlas)
	if atlas:
		assert_eq(Vector2i(atlas.get_size()), ATLAS_SIZE)
		var image := atlas.get_image()
		assert_eq(image.get_pixel(2 * 32 + 16, 32 + 16), Color.WHITE, "frame 6 is the solid square")
		assert_gt(image.get_pixel(16, 16).a, 0.0, "frame 0 is a smoke puff")

func test_one_particles_node_draws_everything() -> void:
	var nodes := effects.find_children("*", "GPUParticles2D", true, false)
	assert_eq(nodes.size(), 1, "exactly one GPUParticles2D under the spawner")
	assert_eq(nodes[0], particles)
	assert_true(particles.ready_to_emit)
	assert_false(particles.emitting, "never emits on its own")
	assert_eq(particles.texture.resource_path, ATLAS_PATH)
	assert_eq(particles.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)

	var canvas := particles.material as ShaderMaterial
	assert_not_null(canvas, "the shared canvas material picks the atlas frame and adds onto the scene")
	if canvas:
		assert_eq(canvas.resource_path, CANVAS_MATERIAL_PATH)
		assert_eq(canvas.shader.resource_path, CANVAS_SHADER_PATH)
		assert_eq(particles.atlas_frames(), Vector2i(4, 2))
		assert_eq(particles.frame_count, 8)

# the particle pass of the original blended One / One: a quad adds
# color.rgb * (color.a + emissive) onto the scene and covers nothing. the
# canvas shader writes alpha 0 under blend_premul_alpha, src + dst * (1 - 0)
func test_particles_add_onto_the_scene_like_the_original() -> void:
	var canvas: ShaderMaterial = particles.material
	var code: String = canvas.shader.code
	assert_string_contains(code, "blend_premul_alpha", "src + dst * (1 - a) with a written as 0 is One / One")
	assert_string_contains(code, "COLOR = vec4(tex.rgb * tex.a * COLOR.rgb, 0.0);", "alpha 0 so the blend adds")
	assert_string_contains(code, "INSTANCE_CUSTOM.z", "the atlas frame pick of CanvasItemMaterial.particles_animation")
	var particles_code: String = SHARED_MATERIAL.shader.code
	assert_string_contains(particles_code, "vec3 hdr = color.rgb * (color.a + cf.y) * EXPOSURE;", "particle.hlsl: rgb * (a + emissive)")
	assert_string_contains(particles_code, "COLOR = vec4(lit, color.a);")

# the original drew its particles into an RGBA16F scene and rc_composite.hlsl
# put the whole scene through the extended Reinhard at exposure 1 and white
# point 2 before it reached the screen, so no particle showed at its raw
# value: the cannon's muzzle flash (1, 1.1, 0.85) came out (0.63, 0.66,
# 0.56), and the hit spark's overbright (2.0, 1.16, 0.21) came out (1.0,
# 0.69, 0.18), orange rather than the yellow a plain clamp makes of it. an
# earlier port only brought colors over 1 down and left the rest untouched,
# which made every flash, casing and puff brighter than the original, so
# the shader now runs the whole curve per particle. the trail runs the same
# curve on its colors
func test_particles_go_through_the_tonemap_of_the_original() -> void:
	var code: String = SHARED_MATERIAL.shader.code
	assert_string_contains(code, "const float EXPOSURE = 1.0;")
	assert_string_contains(code, "const float WHITE_POINT = 2.0;")
	assert_string_contains(code, "vec3 lit = hdr * (1.0 + hdr / (WHITE_POINT * WHITE_POINT)) / (1.0 + hdr);")
	assert_false(code.contains("max(1.0, peak"), "no peak only clamp, the whole range is mapped")

	var flash := Trail.tonemapped(Color(1.0, 1.1, 0.85, 1.0))
	assert_almost_eq(flash.r, 0.625, 0.001)
	assert_almost_eq(flash.g, 0.668, 0.001)
	assert_almost_eq(flash.b, 0.557, 0.001)
	assert_almost_eq(flash.a, 1.0, 0.0001, "alpha is not mapped")
	assert_almost_eq(Trail.tonemapped(Color(0.4, 0.4, 0.4, 1.0)).r, 0.314, 0.001, "the casing gray")
	assert_almost_eq(Trail.tonemapped(Color(0.9, 0.9, 0.9, 1.0)).r, 0.580, 0.001, "the cannon trail")

# the original particle quad spanned -1..1 in its scale, so a scale is a
# half extent and a spark of scale 0.1 is 0.2 units long. the transform
# scales the quad GPUParticles2D builds, which is the whole texture
# (gpu_particles_2d.cpp sizes its mesh at texture.get_size(), the canvas
# material's frames only move the UVs), so the shader divides by the atlas
# size. dividing by one frame's 32 px, as the port first did, drew every
# spark, flash, casing and puff four times as long and twice as tall
func test_particle_scale_is_a_half_extent_of_the_whole_quad() -> void:
	assert_string_contains(SHARED_MATERIAL.shader.code, "* 2.0 * pixels_per_unit / quad_size", "twice the scale across, over the whole texture sized quad")
	assert_false(SHARED_MATERIAL.shader.code.contains("frame_size"), "no frame sized quad")

func test_material_is_an_own_copy_with_the_atlas_quad_size() -> void:
	var material: ShaderMaterial = particles.process_material
	assert_ne(material, SHARED_MATERIAL, "the shared material is never patched")
	assert_eq(material.shader, SHARED_MATERIAL.shader)
	assert_eq(material.get_shader_parameter("pixels_per_unit"), RegolithWorld.pixels_per_unit())
	assert_eq(material.get_shader_parameter("quad_size"), Vector2(ATLAS_SIZE), "the whole atlas, what the node's quad spans")
	assert_eq(material.get_shader_parameter("frame_count"), 8.0)
	assert_eq(particles.fixed_fps, 0)

func test_every_props_gets_its_own_slot_in_the_uniforms() -> void:
	var seen := {}
	for props in spawner_props():
		var slot: int = particles.slot_for(props)
		assert_between(slot, 0, ParticleEffect.MAX_SLOTS - 1, props.resource_path)
		assert_false(seen.has(slot), "slots are distinct")
		seen[slot] = props
		assert_eq(particles.slot_for(props), slot, "the same props keep their slot")

		var life_damping: PackedVector4Array = particles.process_material.get_shader_parameter("life_damping")
		var color_frames: PackedVector4Array = particles.process_material.get_shader_parameter("color_frames")
		assert_eq(life_damping[slot], Vector4(props.life_min, props.life_max, props.damping_min, props.damping_max))
		assert_eq(color_frames[slot], Vector4(props.color_factor, props.emissive, props.frame_min, props.frame_max))

func test_smoke_props_use_the_puffs_and_sparks_the_square() -> void:
	for props in SMOKE_PROPS:
		assert_eq(Vector2i(props.frame_min, props.frame_max), SMOKE_FRAMES, props.resource_path)
	for props in SQUARE_PROPS:
		assert_eq(Vector2i(props.frame_min, props.frame_max), Vector2i(SQUARE_FRAME, SQUARE_FRAME), props.resource_path)

func test_all_effects_route_to_the_one_node() -> void:
	var props := ParticleProps.new()
	props.count_min = 3
	props.count_max = 3
	effects.emit(props, Vector2(10, 10))
	assert_eq(particles.emitted, 3)
	assert_eq(particles.count_of(props), 3)
	effects.spark(Vector2(10, 10), 0.0)
	assert_between(particles.count_of(effects.hit_spark), effects.hit_spark.count_min, effects.hit_spark.count_max)

func test_explosion_bursts_spark_and_smoke() -> void:
	effects.explosion(Vector2(100, 100))

	assert_eq(effects.explosions, 1)
	assert_between(particles.count_of(effects.explosion_spark), effects.explosion_spark.count_min, effects.explosion_spark.count_max)
	assert_between(particles.count_of(effects.explosion_smoke), effects.explosion_smoke.count_min, effects.explosion_smoke.count_max)

func test_missile_flashes_on_launch_trails_exhaust_and_explodes() -> void:
	var puff: ParticleProps = MISSILE_PROPS.muzzle_effects[0]
	var missile: Missile = await fire_one("Missiles")
	if missile == null:
		return

	assert_eq(particles.count_of(puff), puff.count_min, "launch puff on the shot")
	assert_eq(particles.count_of(effects.missile_flame), 0, "no exhaust while coasting")
	missile.coast_remaining = 0.0
	await wait_physics_frames(3)
	assert_gt(particles.count_of(effects.missile_flame), 0, "exhaust once the motor runs")
	assert_gt(particles.count_of(effects.missile_smoke), 0)

	missile.explode(missile.global_position)
	assert_eq(effects.explosions, 1, "the weapon's shot bursts when it goes off")
	assert_gt(particles.count_of(effects.explosion_spark), 0)

func test_force_bullet_burst_shows_the_explosion() -> void:
	var puff: ParticleProps = FORCE_PROPS.muzzle_effects[0]
	var bullet: ForceBullet = await fire_one("ForceGun")
	if bullet == null:
		return

	assert_eq(particles.count_of(puff), puff.count_min)

	bullet.explode(bullet.global_position)
	assert_eq(effects.explosions, 1)

func test_cannon_bullet_has_trail_flashes_and_sparks_on_hit() -> void:
	player.weapon.props = CANNON_PROPS
	var trails: Array = []
	player.weapon.fired.connect(func(bullet: Node2D):
		var trail: Trail = bullet.trail
		trails.append({"tapered": trail != null and trail.width_curve != null, "faded": trail != null and trail.gradient != null, "width": trail.width if trail else 0.0, "front": trail.gradient.get_color(1) if trail else Color.BLACK}))

	var to_rock := rock.global_position - player.global_position
	for i in 90:
		player.weapon.set_fire_state(true, to_rock)
		await wait_physics_frames(1)
	player.weapon.set_fire_state(false, to_rock)
	await wait_physics_frames(30)

	assert_gt(trails.size(), 0, "bullets fired")
	for trail in trails:
		assert_almost_eq(trail["width"], RegolithWorld.pixels_per_cell() * 0.5, 0.001, "the original's C.cell_local_scale width is half a cell, the missile's twice that one cell")
		assert_eq(trail["front"], Trail.tonemapped(CANNON_PROPS.color_front), "trail colors through the original's tonemap")
	for muzzle in CANNON_PROPS.muzzle_effects:
		assert_gt(particles.count_of(muzzle), 0, "muzzle effect on every shot: " + muzzle.resource_path)
	assert_gt(particles.count_of(effects.hit_spark), 0, "sparks where bullets entered the rock")

	for trail in trails:
		assert_true(trail["tapered"], "bullet spawned with a trail that tapers to the tip")
		assert_true(trail["faded"], "trail fades to the back color")

# every value of engine/particles/spark.json of the original, the spark of
# SpriteEffectsEventHandler on a bullet hitting a surface cell. sim units
# and seconds
func test_hit_spark_matches_the_original_spark_asset() -> void:
	var p: ParticleProps = effects.hit_spark
	assert_eq(Vector2i(p.count_min, p.count_max), Vector2i(1, 5))
	assert_eq(p.offset_min, Vector2(0.2, 0))
	assert_eq(p.offset_max, Vector2(0.2, 0))
	assert_almost_eq(p.angle_min, -0.2, 0.0001)
	assert_almost_eq(p.angle_max, 0.2, 0.0001)
	assert_eq(p.angle_xy_min, Vector2(-5, 0))
	assert_eq(p.angle_xy_max, Vector2(-5, 0))
	assert_eq(p.velocity_min, Vector2(50, -5))
	assert_eq(p.velocity_max, Vector2(-2.5, 5))
	assert_almost_eq(p.damping_min, 5.0, 0.0001)
	assert_almost_eq(p.damping_max, 82.9, 0.0001)
	assert_almost_eq(p.angular_velocity_min, -5.0, 0.0001)
	assert_almost_eq(p.angular_velocity_max, 5.0, 0.0001)
	assert_eq(p.angular_velocity_xy_min, Vector2(-5, 5))
	assert_eq(p.angular_velocity_xy_max, Vector2(-5, 5))
	assert_almost_eq(p.angular_damping, 12.25, 0.0001)
	assert_almost_eq(p.life_min, 0.01, 0.0001)
	assert_almost_eq(p.life_max, 0.12, 0.0001)
	assert_eq(p.scale_begin_min, Vector2(0.06, 0.1))
	assert_eq(p.scale_begin_max, Vector2(0.1, 0))
	assert_eq(p.scale_end, Vector2(0.01, 0))
	assert_almost_eq(p.scale_factor, 0.85, 0.0001)
	assert_eq(p.color_begin, Color(1, 1.1, 0.85, 1))
	assert_eq(p.color_end, Color(0.95, 0.55, 0.1, 0.5))
	assert_almost_eq(p.color_factor, 0.05, 0.0001)
	assert_almost_eq(p.emissive, 1.6, 0.0001)
	assert_eq(Vector2i(p.frame_min, p.frame_max), Vector2i(SQUARE_FRAME, SQUARE_FRAME), "an untextured quad")

# game/particles/explosion_spark.json of the original, the ExplosionEvent's
# and ExplosionSequence's sparks
func test_explosion_spark_matches_the_original_asset() -> void:
	var p: ParticleProps = effects.explosion_spark
	assert_eq(Vector2i(p.count_min, p.count_max), Vector2i(35, 50))
	assert_eq(p.velocity_min, Vector2(-10, -10))
	assert_eq(p.velocity_max, Vector2(10, 10))
	assert_almost_eq(p.damping_min, 4.1, 0.0001)
	assert_almost_eq(p.damping_max, 13.85, 0.0001)
	assert_almost_eq(p.angular_damping, 5.95, 0.0001)
	assert_almost_eq(p.life_min, 0.01, 0.0001)
	assert_almost_eq(p.life_max, 0.47, 0.0001)
	assert_eq(p.scale_begin_min, Vector2(0.06, 0.1))
	assert_eq(p.scale_begin_max, Vector2(0.1, 0))
	assert_eq(p.scale_end, Vector2(0.01, 0))
	assert_almost_eq(p.scale_factor, 0.85, 0.0001)
	assert_eq(p.color_begin, Color(1, 0.55, 0.25, 1))
	assert_eq(p.color_end, Color(0.2, 0.2, 0.2, 0.5))
	assert_almost_eq(p.color_factor, 1.0, 0.0001)
	assert_almost_eq(p.emissive, 0.0, 0.0001)

# engine/particles/core_spark.json, the damaged_effect of a core
func test_core_spark_matches_the_original_asset() -> void:
	var p: ParticleProps = CORE_SPARK
	assert_eq(Vector2i(p.count_min, p.count_max), Vector2i(1, 3))
	assert_eq(p.velocity_min, Vector2(-6, -6))
	assert_eq(p.velocity_max, Vector2(6, 6))
	assert_almost_eq(p.damping_min, 10.0, 0.0001)
	assert_almost_eq(p.damping_max, 40.0, 0.0001)
	assert_almost_eq(p.life_min, 0.05, 0.0001)
	assert_almost_eq(p.life_max, 0.35, 0.0001)
	assert_eq(p.scale_begin_min, Vector2(0.01, 0.01))
	assert_eq(p.scale_begin_max, Vector2(0.025, 0.025))
	assert_eq(p.scale_end, Vector2.ZERO)
	assert_almost_eq(p.scale_factor, 0.9, 0.0001)
	assert_eq(p.color_begin, Color(1, 0.75, 0.3, 1))
	assert_eq(p.color_end, Color(0.9, 0.4, 0.05, 0.3))
	assert_almost_eq(p.color_factor, 0.6, 0.0001)
	assert_almost_eq(p.emissive, 24.0, 0.0001)

# the spark ParticleSpawn inside the original's lightning assets: every
# LightningProps sparks with weapon_bolt.json's by default, the hit props
# (weapon_bolt_hit.json, ball_zap.json) with the long lived tilted one
func test_lightning_sparks_match_the_original_lightning_assets() -> void:
	assert_eq(LightningProps.new().spark, LIGHTNING_SPARK, "the default spark")
	assert_eq(BOLT_HIT_LIGHTNING.spark, LIGHTNING_HIT_SPARK)
	assert_eq(BALL_ZAP_LIGHTNING.spark, LIGHTNING_HIT_SPARK)

	for p in [LIGHTNING_SPARK, LIGHTNING_HIT_SPARK]:
		assert_eq(Vector2i(p.count_min, p.count_max), Vector2i(1, 5), p.resource_path)
		assert_almost_eq(p.angle_min, -0.3, 0.0001)
		assert_almost_eq(p.angle_max, 0.3, 0.0001)
		assert_eq(p.velocity_min, Vector2(-3, -3))
		assert_eq(p.velocity_max, Vector2(3, 3))
		assert_almost_eq(p.damping_min, 10.0, 0.0001)
		assert_almost_eq(p.damping_max, 40.0, 0.0001)
		assert_almost_eq(p.angular_velocity_min, -10.0, 0.0001)
		assert_almost_eq(p.angular_velocity_max, 10.0, 0.0001)
		assert_almost_eq(p.angular_damping, 0.9, 0.0001)
		assert_eq(p.scale_begin_min, Vector2(0.015, 0.015))
		assert_eq(p.scale_begin_max, Vector2(0.03, 0.03))
		assert_eq(p.scale_end, Vector2.ZERO)
		assert_eq(p.color_end, Color(0.1, 0.1, 1, 0))

	assert_almost_eq(LIGHTNING_SPARK.life_min, 0.02, 0.0001)
	assert_almost_eq(LIGHTNING_SPARK.life_max, 1.35, 0.0001)
	assert_eq(LIGHTNING_SPARK.color_begin, Color(0.6, 0.7, 1, 0.9))
	assert_almost_eq(LIGHTNING_SPARK.color_factor, 1.0, 0.0001)
	assert_almost_eq(LIGHTNING_SPARK.emissive, 1.6, 0.0001)

	assert_almost_eq(LIGHTNING_HIT_SPARK.life_min, 0.42, 0.0001)
	assert_almost_eq(LIGHTNING_HIT_SPARK.life_max, 0.471, 0.0001)
	assert_eq(LIGHTNING_HIT_SPARK.color_begin, Color(0.6, 0.7, 1, 0.8))
	assert_almost_eq(LIGHTNING_HIT_SPARK.color_factor, 0.15, 0.0001)
	assert_almost_eq(LIGHTNING_HIT_SPARK.emissive, 0.8, 0.0001)
	assert_eq(LIGHTNING_HIT_SPARK.angle_xy_min, Vector2(-6.05, -8.3))
	assert_eq(LIGHTNING_HIT_SPARK.angle_xy_max, Vector2(7.05, 7.45))
	assert_eq(LIGHTNING_HIT_SPARK.angular_velocity_xy_min, Vector2(-6.3, 4.5))
	assert_eq(LIGHTNING_HIT_SPARK.angular_velocity_xy_max, Vector2(4.95, 4.85))

# a lightning strike's sparks are particles of its spark props off the one
# node, not cell particles
func test_lightning_sparks_draw_through_the_particle_node() -> void:
	var before := particles.count_of(LIGHTNING_SPARK)
	Lightning.spawn_spark(world, Vector2(20, 20), LightningProps.new(), RegolithWorld.pixels_per_unit())
	var count := particles.count_of(LIGHTNING_SPARK) - before
	assert_between(count, LIGHTNING_SPARK.count_min, LIGHTNING_SPARK.count_max)

# the original sparked at every cell hit at a sprite's surface, out along
# its distance field gradient. the port reads the normal off the empty
# cells around the hit cell: a cell on the top edge of the rock has a
# normal pointing up, a cell surrounded by filled cells has none
func test_bullet_sparks_fly_out_along_the_surface_normal() -> void:
	var center := rock.get_center_of_mass()
	var cell_px := float(world.pixels_per_cell)
	var last_filled := Vector2i(-1, -1)
	var probe := center

	for i in 400:
		var cell := rock.world_to_cell(probe)
		if rock.has_cell(cell):
			last_filled = cell
		elif last_filled != Vector2i(-1, -1):
			break
		probe += Vector2(0, -cell_px)

	assert_ne(last_filled, Vector2i(-1, -1), "walked up out of the rock")
	if last_filled == Vector2i(-1, -1):
		return

	var normal := Bullet.surface_normal(rock, last_filled)
	assert_almost_eq(normal.length(), 1.0, 0.001, "a surface cell has a unit normal")
	assert_lt(normal.y, -0.3, "pointing out of the top of the rock: " + str(normal))

	var inner := rock.world_to_cell(center)
	var solid := true
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			solid = solid and rock.has_cell(inner + Vector2i(dx, dy))
	if solid:
		assert_eq(Bullet.surface_normal(rock, inner, Vector2.LEFT), Vector2.ZERO, "no spark deep inside")

# the original decided "surface" off the sprite's distance field, and that
# field was rebuilt only at the frame's SpriteCommit, so a cell the bullet
# had just bored still read as filled for the rest of the frame: the cell
# behind it was no surface cell and stayed silent. the port records what
# was filled around each hit before it lands and hands surface_normal that
# record to count as filled
func test_surface_normal_counts_the_cells_bored_this_frame_as_filled() -> void:
	var cell_px := float(world.pixels_per_cell)
	var top := top_surface_cell()
	assert_ne(top, Vector2i(-1, -1), "walked up out of the rock")
	if top == Vector2i(-1, -1):
		return

	# bore straight down from the top cell to the first cell that is no
	# surface cell while the rock is whole, the way a bullet does
	var bored: Array = []
	var deep := top
	var probe := rock.cell_to_world(top)
	for i in 16:
		bored.append(deep)
		probe += Vector2(0, cell_px)
		deep = rock.world_to_cell(probe)
		if not rock.has_cell(deep):
			pending("the rock is too thin under its top cell")
			return
		if Bullet.surface_normal(rock, deep, Vector2.LEFT) == Vector2.ZERO:
			break

	assert_eq(Bullet.surface_normal(rock, deep, Vector2.LEFT), Vector2.ZERO, "a cell inside the whole rock is silent")
	if Bullet.surface_normal(rock, deep, Vector2.LEFT) != Vector2.ZERO:
		return

	var record: Dictionary = Bullet.record_filled_around(rock, top)
	assert_true(record.has(top), "the hit cell is on record before the hit lands")
	assert_true(record.has(deep) or bored.size() > Bullet.FRACTURE_RADIUS, "and so is everything the fracture can reach")
	assert_eq(Bullet.filled_this_frame(rock), record, "the frame's record is shared")

	for cell in bored:
		rock.remove_cell(cell)
	assert_false(rock.has_cell(top), "a bored cell is gone at once")
	assert_ne(Bullet.surface_normal(rock, deep, Vector2.LEFT), Vector2.ZERO, "read live, the cell at the end of the tunnel looks like a surface cell")
	var as_set := {}
	for cell in bored:
		as_set[cell] = true
	assert_eq(Bullet.surface_normal(rock, deep, Vector2.LEFT, as_set), Vector2.ZERO, "with the tunnel's cells still counted as filled it is not, %d cells bored" % bored.size())

# one cannon bullet straight into the rock: bursts at the cells of the
# outer layer it comes through, none at the cells of its tunnel behind
# them, where the port sparked before. straight, since the original's hook
# (rotation_factor 100 on a -1..1 bias) can skim a shot along the outside
# where every cell is a surface cell. the rock's face is jagged, so the
# outer layer runs a few cells deep along the bore, and a bore that runs
# on into the next frame sparks once more there, its last cell truly empty
# by then as it was for the original once SpriteCommit rebuilt the field:
# the test replays that rule at every hit off the frame's record and expects
# exactly those bursts, fewer than the cells bored
func test_one_cannon_bullet_sparks_at_the_outer_layer_only() -> void:
	var weapon: Weapon = player.weapon
	var props: WeaponProps = CANNON_PROPS.duplicate()
	props.shots_per_ammo = 1
	props.inaccuracy_angle = 0.0
	props.inaccuracy_tangent = 0.0
	props.spit_odds = 0.0
	props.rotation_factor = 0.0
	weapon.props = props

	var hits: Array = []
	var expected: Array = [0]
	weapon.fired.connect(func(bullet: Node2D): bullet.hit_cell.connect(func(sprite: RegolithSprite, cell: Vector2i, _p):
		hits.append(cell)
		var record: Dictionary = Bullet.filled_before.get(sprite.get_instance_id(), {})
		if Bullet.surface_normal(sprite, cell, Vector2.LEFT, record) != Vector2.ZERO:
			expected[0] += 1))

	# at the center of mass, into the thick of it, not the padded grid's center
	var to_rock := rock.get_center_of_mass() - player.global_position
	weapon.set_fire_state(true, to_rock)
	await wait_physics_frames(1)
	weapon.set_fire_state(false, to_rock)
	await wait_physics_frames(90)

	assert_gte(hits.size(), 6, "the bullet bored deep, %d cells" % hits.size())
	assert_gt(effects.sparks, 0, "a burst where it entered")
	assert_eq(effects.sparks, expected[0], "a burst at each outer layer cell of the %d bored" % hits.size())
	assert_lt(effects.sparks, hits.size(), "the cells behind the outer layer stay silent")
	assert_between(particles.count_of(effects.hit_spark), effects.sparks * effects.hit_spark.count_min, effects.sparks * effects.hit_spark.count_max, "particles per burst")

# the top most filled cell straight up from the rock's center of mass
func top_surface_cell() -> Vector2i:
	var cell_px := float(world.pixels_per_cell)
	var last_filled := Vector2i(-1, -1)
	var probe := rock.get_center_of_mass()

	for i in 400:
		var cell := rock.world_to_cell(probe)
		if rock.has_cell(cell):
			last_filled = cell
		elif last_filled != Vector2i(-1, -1):
			break
		probe += Vector2(0, -cell_px)

	return last_filled

# the largest length in a set of start velocities, units per second
func top_of(velocities: PackedVector2Array) -> float:
	var top := 0.0
	for v in velocities:
		top = maxf(top, v.length())
	return top

# the hit sparks opt in to the speed of what caused them, the other sparks
# fly their own range
func test_only_hit_sparks_take_the_source_speed() -> void:
	assert_true(effects.hit_spark.speed_from_source, "hit_spark")
	assert_true(LIGHTNING_HIT_SPARK.speed_from_source, "lightning_hit_spark")
	assert_false(effects.explosion_spark.speed_from_source, "explosion_spark")
	assert_false(LIGHTNING_SPARK.speed_from_source, "lightning_spark")
	assert_false(preload("res://game/config/effects/cannon_muzzle_spark.tres").speed_from_source, "cannon_muzzle_spark")

# a burst with a source speed scales the props' range so its fastest corner
# leaves at that speed, the shape stays: x along the normal, a little spread
func test_spark_burst_leaves_at_the_source_speed() -> void:
	var p: ParticleProps = effects.hit_spark
	for speed: float in [3.0, 11.5, 40.0]:
		particles.burst(p, Vector2(10, 10), 0.0, 300, Color(0, 0, 0, -1), speed)
		var velocities: PackedVector2Array = particles.last_burst_velocities
		assert_eq(velocities.size(), 300)
		var top := top_of(velocities)
		assert_almost_eq(top, speed, speed * 0.1, "fastest spark at the source speed %.1f" % speed)
		assert_lte(top, speed * 1.0001, "none past it")
		var ratio := speed / p.top_speed()
		for v in velocities:
			assert_true(v.x >= minf(p.velocity_min.x, p.velocity_max.x) * ratio - 0.001 and v.x <= maxf(p.velocity_min.x, p.velocity_max.x) * ratio + 0.001, "x in the scaled range")
			if not (v.x >= minf(p.velocity_min.x, p.velocity_max.x) * ratio - 0.001 and v.x <= maxf(p.velocity_min.x, p.velocity_max.x) * ratio + 0.001):
				break

	# through the spawner too, the burst turned to the normal
	effects.spark(Vector2(10, 10), PI * 0.5, 8.0)
	assert_lte(top_of(particles.last_burst_velocities), 8.0 * 1.0001)
	for v in particles.last_burst_velocities:
		assert_gte(v.y, -2.5 * 8.0 / p.top_speed() - 0.001, "turned to +y, the normal")

# without a source speed, or on props that do not opt in, the range is flown as is
func test_sparks_without_source_speed_keep_their_range() -> void:
	particles.burst(effects.hit_spark, Vector2(10, 10), 0.0, 300)
	assert_almost_eq(top_of(particles.last_burst_velocities), effects.hit_spark.top_speed(), effects.hit_spark.top_speed() * 0.1, "hit spark at its own 50 units/s")

	var p: ParticleProps = effects.explosion_spark
	particles.burst(p, Vector2(10, 10), 0.0, 300, Color(0, 0, 0, -1), 200.0)
	for v in particles.last_burst_velocities:
		assert_true(absf(v.x) <= 10.001 and absf(v.y) <= 10.001, "explosion spark stays in its -10..10 box")
		if not (absf(v.x) <= 10.001 and absf(v.y) <= 10.001):
			break
	assert_gt(top_of(particles.last_burst_velocities), 9.0)

# one straight bullet of the given speed into the rock, its hit spark bursts
# forced large so the fastest spark is near the top. the start velocities
# of the last hit spark burst
func bullet_spark_velocities(speed: float, front := CANNON_PROPS.color_front) -> PackedVector2Array:
	var big: ParticleProps = effects.hit_spark.duplicate()
	big.count_min = 300
	big.count_max = 300
	effects.hit_spark = big

	var weapon: Weapon = player.weapon
	var props: WeaponProps = CANNON_PROPS.duplicate()
	props.shots_per_ammo = 1
	props.inaccuracy_angle = 0.0
	props.inaccuracy_tangent = 0.0
	props.spit_odds = 0.0
	props.rotation_factor = 0.0
	props.speed = speed
	props.speed_random = 0.0
	props.speed_loss_per_cell = 0.0
	props.color_front = front
	weapon.props = props

	var to_rock := rock.get_center_of_mass() - player.global_position
	weapon.set_fire_state(true, to_rock)
	await wait_physics_frames(1)
	weapon.set_fire_state(false, to_rock)
	await wait_physics_frames(90)

	return particles.burst_velocities.get(big, PackedVector2Array())

func test_bullet_sparks_leave_at_the_bullet_speed() -> void:
	var sparks_before := effects.sparks
	var velocities: PackedVector2Array = await bullet_spark_velocities(11.5)
	assert_gt(effects.sparks, sparks_before, "the bullet sparked")
	assert_eq(velocities.size(), 300)
	assert_almost_eq(top_of(velocities), 11.5, 11.5 * 0.1, "fastest spark at the cannon bullet's 11.5 units/s")

func test_faster_bullet_gives_faster_sparks() -> void:
	var slow := top_of(await bullet_spark_velocities(6.0))
	await wait_physics_frames(10)
	var fast := top_of(await bullet_spark_velocities(23.0))
	assert_almost_eq(slow, 6.0, 0.6, "minigun speed sparks")
	assert_almost_eq(fast, 23.0, 2.3, "twice the cannon speed sparks")
	assert_gt(fast, slow * 2.0)

# the begin and end color the slot of the last burst flies in
func last_ramp() -> Array[Color]:
	var slot := particles.last_burst_slot
	var begin: Vector4 = particles.process_material.get_shader_parameter("color_begin")[slot]
	var end: Vector4 = particles.process_material.get_shader_parameter("color_end")[slot]
	return [Color(begin.x, begin.y, begin.z, begin.w), Color(end.x, end.y, end.z, end.w)]

func hue_gap(a: Color, b: Color) -> float:
	var gap := absf(a.h - b.h)
	return minf(gap, 1.0 - gap)

func test_shader_slot_count_matches_the_script() -> void:
	assert_string_contains(SHARED_MATERIAL.shader.code, "const int MAX_SLOTS = %d;" % ParticleEffect.MAX_SLOTS)

# the hit sparks opt in to the color of what caused them, the other sparks
# fly their own ramp
func test_only_hit_sparks_take_the_source_color() -> void:
	assert_true(effects.hit_spark.color_from_source, "hit_spark")
	assert_true(LIGHTNING_HIT_SPARK.color_from_source, "lightning_hit_spark")
	assert_false(effects.explosion_spark.color_from_source, "explosion_spark")
	assert_false(LIGHTNING_SPARK.color_from_source, "lightning_spark")
	assert_false(preload("res://game/config/effects/cannon_muzzle_spark.tres").color_from_source, "cannon_muzzle_spark")

# a red source: the begin is a hot pinkish white and the end a darker red,
# both in the source's hue, at the props' peaks and alphas. the emissive
# and color factor stay the props', so the overbright core still runs
# through the shader's tonemap the same way
func test_red_source_gives_red_sparks() -> void:
	var p: ParticleProps = effects.hit_spark
	var red := Color(1.0, 0.157, 0.157, 0.9)
	var base := particles.slot_for(p)
	particles.burst(p, Vector2(10, 10), 0.0, 5, Color(0, 0, 0, -1), -1.0, red)
	assert_ne(particles.last_burst_slot, base, "a color slot of its own")

	var ramp := last_ramp()
	var begin: Color = ramp[0]
	var end: Color = ramp[1]
	assert_lt(hue_gap(begin, red), 0.02, "begin in the red hue")
	assert_lt(hue_gap(end, red), 0.02, "end in the red hue")
	assert_gt(end.s, 0.7, "the end is a saturated red")
	assert_lt(begin.s, end.s * 0.5, "the begin is the hot white core")
	assert_almost_eq(ParticleEffect.peak_of(begin), ParticleEffect.peak_of(p.color_begin), 0.001, "begin as bright as the props' 1.1")
	assert_almost_eq(ParticleEffect.peak_of(end), ParticleEffect.peak_of(p.color_end), 0.001, "end as bright as the props' 0.95")
	assert_almost_eq(begin.a, p.color_begin.a, 0.0001)
	assert_almost_eq(end.a, p.color_end.a, 0.0001, "the props' end alpha")

	var frames: Vector4 = particles.process_material.get_shader_parameter("color_frames")[particles.last_burst_slot]
	assert_eq(frames, Vector4(p.color_factor, p.emissive, p.frame_min, p.frame_max), "emissive and color factor stay")
	var life: Vector4 = particles.process_material.get_shader_parameter("life_damping")[particles.last_burst_slot]
	assert_eq(life, Vector4(p.life_min, p.life_max, p.damping_min, p.damping_max), "the rest of the props as is")

# a white source keeps the original's hot core, (1.1, 1.1, 1.1) against the
# spark.json (1, 1.1, 0.85), and fades to a gray at its 0.95 peak and half
# alpha where spark.json went orange
func test_white_source_keeps_the_original_core() -> void:
	var p: ParticleProps = effects.hit_spark
	particles.burst(p, Vector2(10, 10), 0.0, 5, Color(0, 0, 0, -1), -1.0, Color.WHITE)
	var ramp := last_ramp()
	var begin: Color = ramp[0]
	var end: Color = ramp[1]
	assert_almost_eq(begin.r, p.color_begin.r, 0.16)
	assert_almost_eq(begin.g, p.color_begin.g, 0.16)
	assert_almost_eq(begin.b, p.color_begin.b, 0.26)
	assert_almost_eq(begin.a, p.color_begin.a, 0.0001)
	assert_almost_eq(ParticleEffect.peak_of(end), ParticleEffect.peak_of(p.color_end), 0.001)
	assert_almost_eq(end.a, p.color_end.a, 0.0001)

	# the original's own orange end as the source gives back its ramp
	var orange := ParticleEffect.source_ramp(p, p.color_end)
	assert_almost_eq(orange[1].r, p.color_end.r, 0.001)
	assert_almost_eq(orange[1].g, p.color_end.g, 0.001)
	assert_almost_eq(orange[1].b, p.color_end.b, 0.001)
	for i in 3:
		assert_almost_eq(orange[0][i], p.color_begin[i], 0.16, "begin channel %d near spark.json" % i)

# props without the flag, or a burst without a source, fly the props' own
# ramp in the props' own slot
func test_sparks_without_source_color_keep_their_ramp() -> void:
	var p: ParticleProps = effects.explosion_spark
	particles.burst(p, Vector2(10, 10), 0.0, 5, Color(0, 0, 0, -1), -1.0, Color.RED)
	assert_eq(particles.last_burst_slot, particles.slot_for(p), "no color slot without the flag")
	assert_eq(last_ramp()[0], p.color_begin)
	assert_eq(last_ramp()[1], p.color_end)

	var hit: ParticleProps = effects.hit_spark
	effects.spark(Vector2(10, 10), 0.0)
	assert_eq(particles.last_burst_slot, particles.slot_for(hit), "no source color, the props' slot")
	assert_eq(last_ramp()[0], hit.color_begin)
	assert_eq(last_ramp()[1], hit.color_end)
	assert_true(particles.color_slots.get(p, {}).is_empty())

# the color slots are cached by props and rounded color and never run past
# MAX_COLOR_SLOTS: past it a new color takes the nearest one its props has
func test_color_slots_are_cached_and_bounded() -> void:
	var p: ParticleProps = effects.hit_spark
	particles.slot_for(p)
	var used := particles.used_slots
	particles.burst(p, Vector2(10, 10), 0.0, 1, Color(0, 0, 0, -1), -1.0, Color(0.2, 0.9, 0.3))
	var green := particles.last_burst_slot
	particles.burst(p, Vector2(10, 10), 0.0, 1, Color(0, 0, 0, -1), -1.0, Color(0.201, 0.9, 0.3))
	assert_eq(particles.last_burst_slot, green, "the same rounded color, the same slot")
	assert_eq(particles.used_slots, used + 1)

	for i in 60:
		var color := Color.from_hsv(float(i) / 60.0, 0.9, 1.0)
		particles.burst(p, Vector2(10, 10), 0.0, 1, Color(0, 0, 0, -1), -1.0, color)
		assert_ne(particles.last_burst_slot, -1)

	assert_eq(particles.color_slot_sources.size(), ParticleEffect.MAX_COLOR_SLOTS, "capped")
	assert_lte(particles.used_slots, ParticleEffect.MAX_SLOTS)
	assert_eq(particles.color_slots[p].size(), ParticleEffect.MAX_COLOR_SLOTS)

	# past the cap: the nearest cached color of the props
	particles.burst(p, Vector2(10, 10), 0.0, 1, Color(0, 0, 0, -1), -1.0, Color(0.22, 0.88, 0.3))
	assert_eq(particles.last_burst_slot, green, "the nearest cached color")
	assert_eq(particles.color_slot_sources.size(), ParticleEffect.MAX_COLOR_SLOTS)

	# other props past the cap with no color of their own fall back to their
	# props slot
	var q: ParticleProps = LIGHTNING_HIT_SPARK
	particles.burst(q, Vector2(10, 10), 0.0, 1, Color(0, 0, 0, -1), -1.0, Color.RED)
	assert_eq(particles.last_burst_slot, particles.slot_for(q))

	# plain props still get their own slot
	var plain := ParticleProps.new()
	assert_gte(particles.slot_for(plain), 0)

# a bullet sparks in the hue of its trail head, props.color_front: a
# fighter cannon magenta bullet throws magenta sparks
func test_bullet_sparks_take_the_bullet_color() -> void:
	var magenta: Color = preload("res://game/config/enemies/fighter_cannon.tres").color_front
	var sparks_before := effects.sparks
	await bullet_spark_velocities(11.5, magenta)
	assert_gt(effects.sparks, sparks_before, "the bullet sparked")
	assert_eq(effects.last_spark_color, magenta, "the bullet passed its color_front")

	var big: ParticleProps = effects.hit_spark
	var cached: Dictionary = particles.color_slots.get(big, {})
	assert_eq(cached.size(), 1, "one color slot, the bullet's")
	for key: Vector4i in cached:
		var slot: int = cached[key]
		var begin: Vector4 = particles.color_begin[slot]
		var end: Vector4 = particles.color_end[slot]
		assert_lt(hue_gap(Color(begin.x, begin.y, begin.z), magenta), 0.02, "begin in the magenta hue")
		assert_lt(hue_gap(Color(end.x, end.y, end.z), magenta), 0.02, "end in the magenta hue")

# a lightning strike's hit sparks take the props' spark_color
func test_lightning_hit_sparks_take_the_spark_color() -> void:
	var p: LightningProps = BOLT_HIT_LIGHTNING
	Lightning.spawn_spark(world, Vector2(20, 20), p, RegolithWorld.pixels_per_unit())
	assert_eq(particles.color_slots.get(LIGHTNING_HIT_SPARK, {}).size(), 1, "a color slot for the spark color")
	var ramp := last_ramp()
	assert_lt(hue_gap(ramp[0], p.spark_color), 0.02)
	assert_lt(hue_gap(ramp[1], p.spark_color), 0.02)
	assert_almost_eq(ramp[1].a, LIGHTNING_HIT_SPARK.color_end.a, 0.0001)

	# the default spark has no flag, it keeps its own slot
	Lightning.spawn_spark(world, Vector2(20, 20), LightningProps.new(), RegolithWorld.pixels_per_unit())
	assert_eq(particles.last_burst_slot, particles.slot_for(LIGHTNING_SPARK))
