extends GutTest

# lightning strikes span their endpoints, fade out and burn what they cross;
# the bolt and ball projectiles eat cells of a rock

const LIGHTNING_MATERIAL := preload("res://game/shaders/regolith_lightning_material.tres")
const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")
const DEFAULT_LIGHTNING := preload("res://game/config/effects/default_lightning.tres")
const BOLT_PROPS := preload("res://game/config/weapons/lightning_bolt.tres")
const BALL_PROPS := preload("res://game/config/weapons/lightning_ball.tres")
const BOLT_SCENE := preload("res://game/scenes/weapons/LightningBolt.tscn")
const BALL_SCENE := preload("res://game/scenes/weapons/LightningBall.tscn")

var world: RegolithWorld
var rock: RegolithSprite

func make_texture() -> ImageTexture:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.4, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

func before_each() -> void:
	world = RegolithWorld.new()
	world.gravity = Vector2.ZERO
	world.pixels_per_cell = 2
	add_child_autofree(world)
	world.sprite_split.connect(func(_source, piece): autofree(piece))

	rock = RegolithSprite.new()
	rock.texture = make_texture()
	rock.material = SPRITE_MATERIAL
	rock.position = Vector2(300, 200)
	add_child_autofree(rock)
	await wait_physics_frames(2)

func make_lightning(props: LightningProps) -> Lightning:
	var lightning := Lightning.new()
	lightning.props = props
	lightning.material = LIGHTNING_MATERIAL
	add_child_autofree(lightning)
	return lightning

func test_strike_spans_endpoints() -> void:
	var lightning := make_lightning(DEFAULT_LIGHTNING)
	var from := Vector2(40, 40)
	var to := Vector2(160, 120)

	lightning.strike(from, to)
	await wait_process_frames(2)

	assert_gt(lightning.get_strike_count(), 0, "strike is alive")
	assert_gt(lightning.get_segment_count(), 0, "segments drawn")

	var points: PackedVector2Array = lightning.strikes.back().bolts[0].path
	assert_gt(points.size(), 2, "channel has jagged points")
	assert_almost_eq(points[0], from, Vector2.ONE, "channel starts at from")
	assert_almost_eq(points[points.size() - 1], to, Vector2.ONE, "channel ends at to")

	var spread := 0.0
	for p in points:
		spread = maxf(spread, absf((p - from).cross((to - from).normalized())))
	assert_gt(spread, 0.0, "channel is jagged, not a straight line")

func test_strike_fades_and_frees() -> void:
	var props: LightningProps = DEFAULT_LIGHTNING.duplicate()
	props.lifetime = 0.1
	var lightning := make_lightning(props)

	lightning.strike(Vector2(40, 40), Vector2(100, 60))
	await wait_process_frames(2)
	assert_gt(lightning.get_segment_count(), 0, "drawn while alive")

	await wait_seconds(0.6)
	assert_false(is_instance_valid(lightning), "freed after fading out")

func test_strike_without_material_draws_nothing() -> void:
	var lightning := Lightning.new()
	lightning.props = DEFAULT_LIGHTNING
	add_child_autofree(lightning)

	lightning.strike(Vector2(40, 40), Vector2(100, 60))
	await wait_process_frames(2)
	assert_eq(lightning.get_segment_count(), 0)
	assert_gt(lightning.get_strike_count(), 0, "the strike still runs")

func test_strike_burns_rock_it_crosses() -> void:
	var props: LightningProps = DEFAULT_LIGHTNING.duplicate()
	props.burn_strength = 255
	props.burn_damage = 1
	var lightning := make_lightning(props)

	var hits := {"count": 0, "rock": 0}
	lightning.hit.connect(func(sprite, _cell, _position):
		hits["count"] += 1
		if sprite == rock:
			hits["rock"] += 1)

	var before := rock.get_active_cell_count()
	lightning.strike(rock.global_position + Vector2(-120, 0), rock.global_position + Vector2(120, 0))
	await wait_physics_frames(3)

	assert_gt(hits["count"], 0, "cells were hit")
	assert_eq(hits["count"], hits["rock"], "all hits on the rock")
	assert_lt(rock.get_active_cell_count(), before, "burned cells were removed")

func test_strike_exclude_skips_sprite() -> void:
	var props: LightningProps = DEFAULT_LIGHTNING.duplicate()
	props.burn_damage = 1
	var lightning := make_lightning(props)
	watch_signals(lightning)

	var before := rock.get_active_cell_count()
	lightning.strike(rock.global_position + Vector2(-120, 0), rock.global_position + Vector2(120, 0), rock)
	await wait_physics_frames(3)

	assert_signal_not_emitted(lightning, "hit")
	assert_eq(rock.get_active_cell_count(), before)

func test_bolt_removes_cells_in_front() -> void:
	var bolt: LightningBolt = BOLT_SCENE.instantiate()
	var start := rock.global_position + Vector2(-80, 0)
	bolt.setup(BOLT_PROPS, start, Vector2.RIGHT, Vector2.ZERO, null)
	add_child_autofree(bolt)

	var hits := {"count": 0}
	bolt.hit_cell.connect(func(_sprite, _cell, _position): hits["count"] += 1)

	var before := rock.get_active_cell_count()
	await wait_physics_frames(1)
	assert_eq(bolt.target, rock, "the muzzle ray found the rock")

	var peak_strikes := 0
	for i in 60:
		if is_instance_valid(bolt) and bolt.lightning != null:
			peak_strikes = maxi(peak_strikes, bolt.lightning.get_strike_count())
		await wait_physics_frames(1)

	assert_gt(hits["count"], 0, "cells hit")
	assert_lt(rock.get_active_cell_count(), before, "rock lost cells")
	assert_gt(peak_strikes, 0, "bolts were painted")

func test_ball_drifts_and_removes_cells() -> void:
	var props: LightningWeaponProps = BALL_PROPS.duplicate()
	props.ball_pixels_per_second = 800.0

	var ball: LightningBall = BALL_SCENE.instantiate()
	var start := rock.global_position + Vector2(-70, 0)
	ball.setup(props, start, Vector2.RIGHT, Vector2.ZERO, null)
	add_child_autofree(ball)

	var hits := {"count": 0}
	ball.hit_cell.connect(func(_sprite, _cell, _position): hits["count"] += 1)

	var before := rock.get_active_cell_count()
	await wait_physics_frames(120)

	assert_gt(ball.global_position.x, start.x + 20.0, "ball drifted along its aim")
	assert_gt(hits["count"], 0, "cells zapped")
	assert_lt(rock.get_active_cell_count(), before, "rock lost cells")
	assert_gt(ball.lightning.get_strike_count(), 0, "ring and zap bolts alive")
