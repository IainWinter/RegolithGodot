extends Node
class_name SnakeHead

# port of SnakeHeadMove: sits under the head RegolithSprite of a MultiSprite.
# the head idles, then circles the target at a distance while the circle
# angle drifts, then dives past it and goes back to circling. every physics
# frame it steers the body's velocity toward the goal, the joints drag the
# rest of the snake behind

enum Mode { FRAZZLED, CIRCLE, DIVE }

@export var target: Node2D

@export var speed := 5.0
@export var orbit_radius := 20.0
@export var dive_reach := 2.0

@export var frazzled_time := 5.0
@export var circle_time := 20.0
@export var dive_time := 8.0

var mode := Mode.FRAZZLED
var timer := 0.0
var time := 0.0
var offset := randf()
var goal := Vector2.ZERO
var dive_target := Vector2.ZERO
var sprite: RegolithSprite

func _ready() -> void:
	sprite = get_parent() as RegolithSprite
	timer = frazzled_time

func find_target() -> Node2D:
	return target if target else Steering.find_player(get_tree())

func tick_timer(delta: float) -> bool:
	timer -= delta
	return timer <= 0.0

func _physics_process(delta: float) -> void:
	if sprite == null or not sprite.is_loaded():
		return

	var focus := find_target()
	if focus == null:
		return

	var ppu := RegolithWorld.pixels_per_unit()
	time += delta
	var angle := time / 5.0 + offset * 6.0

	match mode:
		Mode.FRAZZLED:
			if tick_timer(delta):
				mode = Mode.CIRCLE
				timer = circle_time
			return

		Mode.CIRCLE:
			goal = focus.global_position + Vector2.from_angle(angle) * orbit_radius * ppu

			if tick_timer(delta):
				var dive_angle := angle + PI + randf_range(-1.0, 1.0) * PI / 6.0
				mode = Mode.DIVE
				timer = dive_time
				dive_target = focus.global_position + Vector2.from_angle(dive_angle) * orbit_radius * ppu

		Mode.DIVE:
			goal = dive_target

			if tick_timer(delta) or sprite.global_position.distance_to(dive_target) < dive_reach * ppu:
				mode = Mode.CIRCLE
				timer = circle_time

	var desired := (goal - sprite.global_position).normalized() * speed
	var steering := desired - sprite.linear_velocity
	sprite.linear_velocity += steering * delta
