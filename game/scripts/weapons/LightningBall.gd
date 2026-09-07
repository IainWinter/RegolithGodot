extends Node2D
class_name LightningBall

# port of the engine's LightningBallEntity. a slow ball that drifts along its
# aim and, every delay_per_hit, throws a handful of rays in random directions
# and zaps the first cell each finds: scorched always, removed when the
# damage odds roll so destruction averages pixels_per_second. balls close to
# each other arc together. a spinning ring of small bolts is drawn around it
# in its own local space

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
	var damage_chance := damage_chance_for(props.ball_pixels_per_second, zaps_per_second)
	var radius_pixels := props.ball_radius * pixels_per_unit
	var zap_props := props.hit_props()

	for i in props.ball_zaps_per_hit:
		var zap_direction := Vector2.from_angle(randf() * TAU)
		var hit: Dictionary = world.ray_cast(global_position, global_position + zap_direction * radius_pixels, shooter)

		if zap_target(world, hit, damage_chance):
			lightning.strike(global_position, hit["position"], shooter, zap_props)

	for other in get_tree().get_nodes_in_group("lightning_balls"):
		if other == self or not other is LightningBall:
			continue

		var other_ball: LightningBall = other

		if global_position.distance_to(other_ball.global_position) < (props.ball_radius + other_ball.props.ball_radius) * pixels_per_unit:
			lightning.strike(global_position, other_ball.global_position, shooter)

func draw_ring(pixels_per_unit: float) -> void:
	var a_delta := TAU / props.ball_segments
	var emit_pixels := props.ball_emit_radius * pixels_per_unit

	for k in props.ball_segments:
		var a := k * a_delta + spin
		var end := Vector2.from_angle(a) * emit_pixels
		var next := Vector2.from_angle(a + a_delta) * emit_pixels

		lightning.strike(Vector2.ZERO, end, null, props.ball_center_lightning, self)
		lightning.strike(end, next, null, props.ball_outside_lightning, self)

static func damage_chance_for(pixels_per_second: float, zaps_per_second: float) -> float:
	if zaps_per_second <= 0.0:
		return 0.0

	return clampf(pixels_per_second / (zaps_per_second * 5.0), 0.0, 1.0)

func zap_target(world: RegolithWorld, hit: Dictionary, damage_chance: float) -> bool:
	if hit.is_empty():
		return false

	var sprite: RegolithSprite = hit["sprite"]
	var cell: Vector2i = hit["cell"]

	if sprite == null or not is_instance_valid(sprite) or not sprite.has_cell(cell):
		return false

	if randf() < damage_chance:
		burn_radius(sprite, cell, 1, 255, 160, 1.0, randi_range(1, 2), 0.5, true)
	else:
		burn_radius(sprite, cell, 1, 110, 90, 0.0, 0, 0.5, false)

	var cell_position: Vector2 = sprite.cell_to_world(cell)
	world.spawn_cell_particle(cell_position, Vector2.from_angle(randf() * TAU) * RegolithWorld.pixels_per_unit(), sprite.get_cell_color(cell), sprite.global_rotation)
	hit_cell.emit(sprite, cell, cell_position)

	return true

static func burn_radius(sprite: RegolithSprite, center: Vector2i, radius: int, strength: int, scorch_strength: int, damage_ratio: float, damage: int, spread_odds: float, spread_removes: bool) -> void:
	sprite.burn_cell(center, strength, damage)

	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if (x == 0 and y == 0) or randf() >= spread_odds:
				continue

			var cell := center + Vector2i(x, y)

			if not sprite.has_cell(cell):
				continue

			var distance := maxi(absi(x), absi(y))
			var falloff := 1.0 - float(distance) / float(radius + 1)
			var damaged := randf() < damage_ratio * falloff

			if damaged and not spread_removes and sprite.get_cell_class(cell) == 0:
				damaged = false

			var cell_strength := int((strength if damaged else scorch_strength) * falloff)
			sprite.burn_cell(cell, cell_strength, damage if damaged else 0)

func _on_lightning_finished() -> void:
	if dead:
		queue_free()
