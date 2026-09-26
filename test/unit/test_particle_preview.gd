extends GutTest

# the ParticlePreview node loops a ParticleProps at its origin through its
# own ParticleEffect at the game's scale, and re-reads edited props before
# every burst, so the editor viewport shows what the game will draw

const PREVIEW := preload("res://game/editors/ParticlePreview.tscn")
const SPARK := preload("res://game/config/effects/hit_spark.tres")
const SMOKE := preload("res://game/config/effects/explosion_smoke.tres")

var scene: Node2D
var preview: ParticlePreview

func before_each() -> void:
	scene = PREVIEW.instantiate()
	add_child_autofree(scene)
	preview = scene.get_node("Preview")
	await wait_process_frames(1)

# the demo scene is the user's scratch pad, whatever props and play state
# it was saved with, so the test drives its own
func test_preview_bursts_its_props_at_the_game_scale() -> void:
	assert_true(preview.effect is ParticleEffect, "its own particle node")
	assert_eq(preview.effect.pixels_per_unit, ParticlePreview.GAME_PIXELS_PER_UNIT, "the game's scale without a world")
	preview.props = SPARK
	preview.playing = true
	preview.interval = 0.05
	preview.timer = 0.0
	await wait_seconds(0.4)
	assert_gt(preview.bursts, 1, "bursts keep coming")
	assert_gt(preview.effect.count_of(SPARK), 0, "sparks were emitted")

func test_edits_to_the_props_reach_the_next_burst() -> void:
	var props: ParticleProps = SMOKE.duplicate()
	preview.props = props
	preview.burst()
	var slot: int = preview.effect.slot_for(props)
	assert_almost_eq(preview.effect.life_damping[slot].x, props.life_min, 0.0001)

	props.life_min = 7.5
	preview.burst()
	assert_almost_eq(preview.effect.life_damping[slot].x, 7.5, 0.0001, "the slot re-read the edited props")

func test_paused_preview_stays_quiet_and_burst_now_works() -> void:
	preview.playing = false
	var before := preview.bursts
	await wait_process_frames(6)
	assert_eq(preview.bursts, before, "no bursts while paused")
	preview.burst()
	assert_eq(preview.bursts, before + 1, "the button bursts once")
