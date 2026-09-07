extends Node2D
class_name Bullet

# a point that eats cells along its path. each physics step it walks the
# distance its speed allows, burning the nearest filled cell it reaches and
# carrying on from there with a slightly bent direction, until its cell life
# runs out or the step distance is spent. ending a step inside a sprite embeds
# it there so it rides along with that sprite until the next step. leaving a
# sprite throws the bullet with that sprite's velocity, kept apart from its
# own speed so lodging again does not stack it up

var props: WeaponProps
var velocity := Vector2.ZERO
var carry_velocity := Vector2.ZERO
var lifetime := 0.0
var cell_life := 0
var initial_cell_life := 0
var rotation_bias := 0.0
var shooter: RegolithSprite

var embedded_sprite: RegolithSprite
var embedded_cell := Vector2i.ZERO
var embedded_angle := 0.0

var dead := false
var pixels_per_unit := 0.0
var cell_px := 0.0
var trail_px := 0.0
var trail: Trail

var tip_from := Vector2.ZERO
var tip_to := Vector2.ZERO

signal hit_cell(sprite: RegolithSprite, cell: Vector2i, position: Vector2)

func setup(weapon_props: WeaponProps, start: Vector2, direction: Vector2, holder_velocity: Vector2, holder: RegolithSprite) -> void:
	props = weapon_props
	global_position = start
	velocity = direction.normalized() * (props.speed + props.speed_random * randf_range(-0.5, 0.5))
	lifetime = props.lifetime
	cell_life = props.cell_life
	initial_cell_life = cell_life
	rotation_bias = randf_range(-0.5, 0.5)
	shooter = holder
	pixels_per_unit = RegolithWorld.pixels_per_unit()
	cell_px = RegolithWorld.pixels_per_cell()
	trail_px = props.trail_length * pixels_per_unit
	tip_from = start
	tip_to = start

func _ready() -> void:
	trail = Trail.new()
	trail.setup(props, cell_px, global_position)
	add_child(trail)

func _process(delta: float) -> void:
	if dead:
		if trail.fade(props.speed * pixels_per_unit * delta):
			queue_free()
		return

	trail.set_tip(tip_from.lerp(tip_to, Engine.get_physics_interpolation_fraction()))
	trail.trim(trail_px)

func _physics_process(delta: float) -> void:
	if dead:
		return

	if not is_instance_valid(shooter):
		shooter = null

	var world := RegolithWorld.active()

	if world == null:
		queue_free()
		return

	var was_embedded := false
	var position := global_position

	trail.set_tip(position)

	if embedded_sprite != null and is_instance_valid(embedded_sprite) and embedded_sprite.is_inside_tree():
		was_embedded = true
		position = embedded_sprite.cell_to_world(embedded_cell)
		velocity = velocity.rotated(embedded_sprite.global_rotation - embedded_angle)
		embedded_angle = embedded_sprite.global_rotation
	else:
		embedded_sprite = null

	var own_speed := velocity.length()
	var world_velocity := velocity + carry_velocity
	var direction := world_velocity.normalized()
	var remaining := world_velocity.length() * pixels_per_unit * delta
	var hit_any := false
	var last_sprite: RegolithSprite = null
	var last_cell := Vector2i(-1, -1)

	cell_life -= world.hit_ropes(position, position + direction * remaining, shooter)

	for step in range(initial_cell_life + 1):
		if remaining <= 0.0 or cell_life <= 0:
			break

		var end := position + direction * remaining
		var hit := find_first_cell(world, position, end, last_sprite, last_cell)

		if hit.is_empty():
			position = end
			remaining = 0.0
			break

		var sprite: RegolithSprite = hit["sprite"]
		var hit_cell_index: Vector2i = hit["cell"]

		var cell_position := Explosion.hit_cell(world, props, sprite, hit_cell_index, direction * randf_range(1.0, 4.0) * pixels_per_unit)
		hit_cell.emit(sprite, hit_cell_index, cell_position)

		cell_life -= 1
		hit_any = true
		last_sprite = sprite
		last_cell = hit_cell_index

		remaining -= maxf(hit["distance"], cell_px * 0.5)
		position = cell_position
		trail.push(position)

		embedded_sprite = sprite
		embedded_cell = hit_cell_index
		embedded_angle = sprite.global_rotation

		if cell_life <= 0:
			break

		var bend := props.rotation_factor * rotation_bias * delta * float(cell_life) / float(initial_cell_life)
		direction = direction.rotated(bend)
		own_speed *= 1.0 - props.speed_loss_per_cell

		position += direction * cell_px * 0.51

	if hit_any:
		carry_velocity = Vector2.ZERO
	elif was_embedded:
		carry_velocity = embedded_sprite.get_velocity_at(position)
		embedded_sprite = null

	velocity = direction * own_speed

	global_position = position
	lifetime -= delta

	tip_from = trail.tip()
	tip_to = position
	trail.push(tip_from)

	if lifetime <= 0.0 or cell_life <= 0:
		dead = true
		trail.set_tip(tip_to)

func find_first_cell(world: RegolithWorld, from: Vector2, to: Vector2, skip_sprite: RegolithSprite, skip_cell: Vector2i) -> Dictionary:
	var best := {}
	var best_distance := INF

	for sprite in world.query_segment(from, to):
		if sprite == shooter:
			continue

		for c in sprite.trace_cells(from, to, 2):
			if sprite == skip_sprite and c == skip_cell:
				continue

			var cell_position: Vector2 = sprite.cell_to_world(c)
			var distance := from.distance_to(cell_position)

			if distance < best_distance:
				best_distance = distance
				best = {"sprite": sprite, "cell": c, "position": cell_position, "distance": distance}

			break

	return best
