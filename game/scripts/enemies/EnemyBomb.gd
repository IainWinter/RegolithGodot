extends Enemy
class_name EnemyBomb

# AiBomb + AiThrowable: drifts toward a thrower that has room, else at the
# player, turning at a bounded rate. near the player it lights its fuse and
# bursts: a blast of burns through everything close, a shove, and a ring of
# shrapnel bullets flying out. a thrower that holds it moves it instead;
# hold/thrown state lives on the Throwable child

@export var speed := 3.0
@export var turn_strength := 4.0
@export var turn_commit_angle := 0.6
@export var start_exploding_radius := 3.0
@export var fuse_time := 2.0
@export var blast_radius := 1.5
@export var blast_rays := 16
@export var blast_cells_per_ray := 3
@export var blast_impulse := 4.0
@export var shrapnel_props: WeaponProps
@export var shrapnel_count := 24
@export var seek_thrower := true

signal exploded(position: Vector2)

var exploding := false
var fuse := 0.0
var turn_bias := 0

@onready var throwable: Throwable = Throwable.of(self)

func update_ai(delta: float) -> void:
	if throwable.held_by != null:
		if is_instance_valid(throwable.held_by) and not (throwable.held_by as Enemy).dead:
			return

		throwable.held_by = null

	if exploding:
		fuse -= delta

		if fuse <= 0.0:
			explode()

		return

	if player == null:
		return

	var target := player_pos
	var set_fuse := true

	if seek_thrower and not throwable.thrown:
		var thrower := nearest_thrower(pos, pos.distance_squared_to(player_pos))

		if thrower:
			target = thrower.ring_goal(player_pos)
			set_fuse = false

	var to_goal := target - pos

	if set_fuse and to_goal.length() < start_exploding_radius and has_line_of_sight(pos, target):
		start_fuse(fuse_time)
		return

	steer(to_goal, delta)

func start_fuse(time: float) -> void:
	exploding = true
	fuse = time

func steer(to_goal: Vector2, delta: float) -> void:
	var velocity := linear_velocity
	var current_speed := velocity.length()

	if current_speed > 0.0001:
		var diff := velocity.angle_to(to_goal)
		var max_turn := turn_strength * delta
		var step: float

		if absf(diff) < turn_commit_angle:
			turn_bias = 0
			step = clampf(diff, -max_turn, max_turn)
		else:
			if turn_bias == 0:
				turn_bias = 1 if diff > 0.0 else -1

			var agree := (diff > 0.0) == (turn_bias > 0)
			step = turn_bias * (minf(absf(diff), max_turn) if agree else max_turn)

		velocity = velocity.rotated(step)

	if current_speed > 25.0 or current_speed < speed:
		if current_speed == 0.0:
			velocity = Vector2.RIGHT

		velocity = velocity.lerp(velocity.normalized() * speed, turn_strength * delta)

	linear_velocity = velocity

func explode() -> void:
	var world := RegolithWorld.active()
	var center := global_position

	if world:
		var r := blast_radius * Steering.ppu()

		for sprite in Steering.sprites_near(world, pos, blast_radius):
			if sprite == self:
				continue

			if Explosion.blast_rays(sprite, center, r, blast_rays, blast_cells_per_ray, true) and sprite.is_dynamic():
				var away: Vector2 = (sprite.global_position - center).normalized()
				sprite.apply_impulse(away * blast_impulse * sprite.get_mass(), sprite.global_position)

		Explosion.spawn_shrapnel(shrapnel_props, shrapnel_count, center, self)

	exploded.emit(center)
	die()
