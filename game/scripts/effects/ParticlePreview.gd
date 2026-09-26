@tool
extends Node2D
class_name ParticlePreview

# an editor preview for a ParticleProps: drop this node in a scene (or open
# game/editors/ParticlePreview.tscn), pick the props in the
# inspector and it bursts them at its origin every interval, right in the
# 2D viewport. edits to the props resource show on the next burst. it runs
# the same way in game, so a test or a scene can loop an effect too

const PARTICLE_EFFECT := preload("res://game/scenes/effects/ParticleEffect.tscn")
const GAME_PIXELS_PER_UNIT := 64.0

@export var props: ParticleProps:
	set(value):
		props = value
		timer = 0.0
@export var playing := true
# seconds between bursts
@export_range(0.05, 5.0, 0.05) var interval := 0.5
# the emit direction, degrees, x of the spawn frame points along it
@export_range(-180.0, 180.0, 1.0) var angle_degrees := 0.0
# particles per burst, -1 takes the props' count range
@export var count := -1
# the game runs at 64 px per unit (2 px per cell), so the preview does too
@export var pixels_per_unit := GAME_PIXELS_PER_UNIT
@export_tool_button("Burst now") var burst_button := burst

var effect: ParticleEffect
var timer := 0.0
var bursts := 0

func _ready() -> void:
	make_effect()
	queue_redraw()

func _process(delta: float) -> void:
	if not playing or props == null:
		return

	timer -= delta

	if timer <= 0.0:
		timer = interval
		burst()

func make_effect() -> void:
	if is_instance_valid(effect):
		return

	effect = PARTICLE_EFFECT.instantiate() as ParticleEffect
	effect.name = "Preview"
	add_child(effect)
	effect.set_pixels_per_unit(pixels_per_unit)

func burst() -> void:
	if props == null:
		return

	make_effect()

	if not effect.ready_to_emit:
		return

	if effect.pixels_per_unit != pixels_per_unit:
		effect.set_pixels_per_unit(pixels_per_unit)

	# the props may have been edited since the last burst
	effect.refresh(props)
	effect.burst(props, global_position, deg_to_rad(angle_degrees), count)
	bursts += 1

# a small cross at the emit origin, the arrow points along the emit direction
func _draw() -> void:
	var color := Color(1.0, 1.0, 1.0, 0.35)
	draw_line(Vector2(-6, 0), Vector2(6, 0), color)
	draw_line(Vector2(0, -6), Vector2(0, 6), color)
	var direction := Vector2.from_angle(deg_to_rad(angle_degrees))
	draw_line(Vector2.ZERO, direction * 24.0, Color(1.0, 0.8, 0.3, 0.6))
