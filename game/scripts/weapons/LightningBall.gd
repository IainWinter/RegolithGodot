extends Node2D
class_name LightningBall

# port of the engine's LightningBallEntity. a slow ball that drifts along its
# aim and, every delay_per_hit, throws a handful of rays in random directions
# and zaps the first cell each finds: scorched always, removed when the
# damage odds roll so destruction averages pixels_per_second. balls close to
# each other arc together, and projectiles and items in the radius get arced
# at with the zap gun's helpers. a spinning ring of small bolts is drawn
# around it in its own local space

var props: LightningWeaponProps
var velocity := Vector2.ZERO
var lifetime := 0.0
var spin := 0.0
var timer_hit := 0.0
var timer_ring := 0.0
var shooter: RegolithSprite

var lightning: Lightning
var dead := false

signal hit_cell(sprite: RegolithSprite, cell: Vector2i, position: Vector2)
signal arced(projectile: Node2D)

func setup(weapon_props: WeaponProps, start: Vector2, direction: Vector2, _holder_velocity: Vector2, holder: RegolithSprite) -> void:
	props = weapon_props as LightningWeaponProps
	global_position = start
	velocity = direction.normalized() * weapon_props.speed
	lifetime = weapon_props.lifetime
	shooter = holder
	spin = randf() * TAU

	if props == null:
		push_warning("LightningBall: props is not a LightningWeaponProps")

func _ready() -> void:
	if props == null:
		queue_free()
		return

	add_to_group("lightning_balls")
	lightning = Lightning.attach(self, props.lightning, props.lightning_material)
	lightning.finished.connect(_on_lightning_finished)

func _physics_process(delta: float) -> void:
	if dead:
		return

	if not is_instance_valid(shooter):
		shooter = null

	var world := RegolithWorld.active()

	if world == null:
		queue_free()
		return

	lifetime -= delta

	if lifetime < 0.0:
		dead = true
		return

	var pixels_per_unit := RegolithWorld.pixels_per_unit()
	global_position += velocity * pixels_per_unit * delta
	spin += delta

	timer_ring -= delta

	if timer_ring <= 0.0 and props.ball_center_lightning != null:
		timer_ring = props.ball_center_lightning.lifetime
		draw_ring(pixels_per_unit)

	timer_hit -= delta

	if timer_hit > 0.0:
		return

	timer_hit = props.ball_delay_per_hit

	var zaps_per_second := props.ball_zaps_per_hit / maxf(props.ball_delay_per_hit, delta)
	var damage_chance := LightningZap.damage_chance(props.ball_pixels_per_second, zaps_per_second)
	var radius_pixels := props.ball_radius * pixels_per_unit
	var zap_props := props.hit_props()

	for i in props.ball_zaps_per_hit:
		var zap_direction := Vector2.from_angle(randf() * TAU)
		var hit: Dictionary = world.ray_cast(global_position, global_position + zap_direction * radius_pixels, shooter)

		if LightningZap.zap_target(world, hit, damage_chance):
			var sprite: RegolithSprite = hit["sprite"]
			var cell: Vector2i = hit["cell"]
			lightning.strike(global_position, hit["position"], shooter, zap_props)
			hit_cell.emit(sprite, cell, sprite.cell_to_world(cell))

	for other in get_tree().get_nodes_in_group("lightning_balls"):
		if other == self or not other is LightningBall:
			continue

		var other_ball: LightningBall = other

		if global_position.distance_to(other_ball.global_position) < (props.ball_radius + other_ball.props.ball_radius) * pixels_per_unit:
			lightning.strike(global_position, other_ball.global_position, shooter)

	for projectile in LightningZap.arc_nearby(world, lightning, props.lightning, global_position, radius_pixels, shooter, delta):
		arced.emit(projectile)

func draw_ring(pixels_per_unit: float) -> void:
	var a_delta := TAU / props.ball_segments
	var emit_pixels := props.ball_emit_radius * pixels_per_unit

	for k in props.ball_segments:
		var a := k * a_delta + spin
		var end := Vector2.from_angle(a) * emit_pixels
		var next := Vector2.from_angle(a + a_delta) * emit_pixels

		lightning.strike(Vector2.ZERO, end, null, props.ball_center_lightning, self)
		lightning.strike(end, next, null, props.ball_outside_lightning, self)

func _on_lightning_finished() -> void:
	if dead:
		queue_free()
