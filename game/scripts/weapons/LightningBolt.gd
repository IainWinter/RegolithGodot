extends Node2D
class_name LightningBolt

# port of the engine's LightningBullet. a point that flies from the muzzle,
# homes on the first cell the muzzle ray found in range, eats the cells it
# crosses like a bullet and keeps painting bolts from its tail to its head.
# when it dies a wider burst bolt with sparks is left behind and the node
# waits for its lightning to fade before freeing

var props: LightningWeaponProps
var angle := 0.0
var lifetime := 0.0
var cell_life := 0
var distance_traveled := 0.0
var strike_accumulator := 0.0
var shooter: RegolithSprite

var target: RegolithSprite
var target_cell := Vector2i.ZERO

var lightning: Lightning
var dead := false

signal hit_cell(sprite: RegolithSprite, cell: Vector2i, position: Vector2)

func setup(weapon_props: WeaponProps, start: Vector2, direction: Vector2, _holder_velocity: Vector2, holder: RegolithSprite) -> void:
	props = weapon_props as LightningWeaponProps
	global_position = start
	angle = direction.angle()
	lifetime = weapon_props.lifetime
	cell_life = weapon_props.cell_life
	shooter = holder

	if props == null:
		push_warning("LightningBolt: props is not a LightningWeaponProps")

func _ready() -> void:
	if props == null:
		queue_free()
		return

	lightning = Lightning.attach(self, props.lightning, props.lightning_material)
	lightning.finished.connect(_on_lightning_finished)
	acquire_target()

func acquire_target() -> void:
	var world := RegolithWorld.active()

	if world == null:
		return

	var to := global_position + Vector2.from_angle(angle) * props.target_range * RegolithWorld.pixels_per_unit()
	var hit: Dictionary = world.ray_cast(global_position, to, shooter)

	if not hit.is_empty():
		target = hit["sprite"]
		target_cell = hit["cell"]

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

	if target != null and is_instance_valid(target) and target.is_inside_tree():
		var to_target: Vector2 = target.cell_to_world(target_cell) - global_position

		if Vector2.from_angle(angle).dot(to_target) > 0.0:
			angle = Steering.turn_toward(angle, to_target.angle(), props.turn_speed * delta)
	else:
		target = null

	var pixels_per_unit := RegolithWorld.pixels_per_unit()
	var direction := Vector2.from_angle(angle)
	var position := global_position
	var next_position := position + direction * props.speed * pixels_per_unit * delta
	var dying := lifetime < 0.0

	cell_life -= world.hit_ropes(position, next_position, shooter)

	if cell_life <= 0:
		dying = true

	for found in world.query_segment(position, next_position):
		if dying:
			break

		var sprite: RegolithSprite = found

		if sprite == shooter:
			continue

		for c in sprite.trace_cells(position, next_position, cell_life):
			var cell: Vector2i = c
			var cell_position := Explosion.hit_cell(world, props, sprite, cell, direction * randf_range(1.0, 4.0) * pixels_per_unit)
			hit_cell.emit(sprite, cell, cell_position)

			cell_life -= 1

			if cell_life <= 0:
				next_position = cell_position
				dying = true
				break

	distance_traveled += position.distance_to(next_position)
	global_position = next_position

	var tail := next_position - direction * minf(props.segment_length * pixels_per_unit, distance_traveled)

	strike_accumulator += props.strikes_per_second * delta

	while strike_accumulator >= 1.0:
		strike_accumulator -= 1.0
		lightning.strike(tail, next_position, shooter)

	if dying:
		dead = true
		lightning.strike(tail, next_position, shooter, props.hit_props())

func _on_lightning_finished() -> void:
	if dead:
		queue_free()
