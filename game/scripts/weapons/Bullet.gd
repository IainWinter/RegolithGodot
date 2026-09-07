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
var trail_length := 0.0
var line: Line2D

# the last segment the physics step moved along. the drawn tip slides from
# tip_from to tip_to over the render frames between physics steps
var tip_from := Vector2.ZERO
var tip_to := Vector2.ZERO

signal hit_cell(sprite: RegolithSprite, cell: Vector2i, position: Vector2)

func setup(weapon_props: WeaponProps, start: Vector2, direction: Vector2, holder_velocity: Vector2, holder: RegolithSprite) -> void:
	props = weapon_props
	global_position = start
	velocity = direction.normalized() * props.speed
	lifetime = props.lifetime
	cell_life = props.cell_life
	initial_cell_life = cell_life
	rotation_bias = randf_range(-0.5, 0.5)
	shooter = holder
	trail_length = props.trail_length * RegolithWorld.pixels_per_unit()
	tip_from = start
	tip_to = start

func _ready() -> void:
	line = Line2D.new()
	line.top_level = true
	line.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	line.width = cell_pixels()
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = false

	var gradient := Gradient.new()
	gradient.set_color(0, props.color_back)
	gradient.set_color(1, props.color_front)
	line.gradient = gradient

	add_child(line)
	line.add_point(global_position)

func cell_pixels() -> float:
	return RegolithWorld.pixels_per_unit() / RegolithWorld.CELLS_PER_CHUNK

# the trail is visual, it runs on the drawn frame. the tip is lerped along the
# last physics segment so it moves smoothly when the render rate is higher
# than the physics rate
func _process(delta: float) -> void:
	if dead:
		fade_trail(delta)
		return

	var fraction := Engine.get_physics_interpolation_fraction()
	line.set_point_position(line.get_point_count() - 1, tip_from.lerp(tip_to, fraction))
	trim_trail()

func _physics_process(delta: float) -> void:
	if dead:
		return

	var world := RegolithWorld.active()

	if world == null:
		queue_free()
		return

	var was_embedded := false
	var position := global_position

	# the drawn tip may still lag behind where the last step really ended
	line.set_point_position(line.get_point_count() - 1, position)

	if embedded_sprite != null and is_instance_valid(embedded_sprite) and embedded_sprite.is_inside_tree():
		was_embedded = true
		position = embedded_sprite.cell_to_world(embedded_cell)
		velocity = velocity.rotated(embedded_sprite.global_rotation - embedded_angle)
		embedded_angle = embedded_sprite.global_rotation
	else:
		embedded_sprite = null

	var pixels_per_unit := RegolithWorld.pixels_per_unit()
	var cell := cell_pixels()
	var own_speed := velocity.length()
	var world_velocity := velocity + carry_velocity
	var direction := world_velocity.normalized()
	var remaining := world_velocity.length() * pixels_per_unit * delta
	var hit_any := false
	var last_sprite: RegolithSprite = null
	var last_cell := Vector2i(-1, -1)

	# ropes in the way each take a hit and cost a cell of life, the bullet
	# carries on through them
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
		var cell_position: Vector2 = hit["position"]

		var damage_ratio: float = props.damage_ratio if sprite.get_cell_class(hit_cell_index) > 0 else 0.0

		# the struck cell sprays off along the bullet, the rest of the
		# damage flies off with the sprite when the world commits it
		world.spawn_cell_particle(cell_position, direction * randf_range(1.0, 4.0) * pixels_per_unit, sprite.get_cell_color(hit_cell_index), sprite.global_rotation)

		sprite.burn_fracture(hit_cell_index, props.burn_strength, props.scorch_strength, damage_ratio, props.damage)
		hit_cell.emit(sprite, hit_cell_index, cell_position)

		cell_life -= 1
		hit_any = true
		last_sprite = sprite
		last_cell = hit_cell_index

		remaining -= maxf(hit["distance"], cell * 0.5)
		position = cell_position
		line.add_point(position)

		embedded_sprite = sprite
		embedded_cell = hit_cell_index
		embedded_angle = sprite.global_rotation

		if cell_life <= 0:
			break

		var bend := props.rotation_factor * rotation_bias * delta * float(cell_life) / float(initial_cell_life)
		direction = direction.rotated(bend)
		own_speed *= 1.0 - props.speed_loss_per_cell

		# start the next trace just past this cell so it is not hit twice
		position += direction * cell * 0.51

	if hit_any:
		# lodged, the sprite carries it from here
		carry_velocity = Vector2.ZERO
	elif was_embedded:
		carry_velocity = embedded_sprite.get_velocity_at(position)
		embedded_sprite = null

	velocity = direction * own_speed

	global_position = position
	lifetime -= delta

	tip_from = line.get_point_position(line.get_point_count() - 1)
	tip_to = position
	line.add_point(tip_from)

	if lifetime <= 0.0 or cell_life <= 0:
		dead = true
		line.set_point_position(line.get_point_count() - 1, tip_to)

# nearest filled cell along the segment across every sprite the tree returns
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

# keep only the last trail_length pixels of the line
func trim_trail() -> void:
	var length := 0.0

	for i in range(line.get_point_count() - 1, 0, -1):
		var a := line.get_point_position(i)
		var b := line.get_point_position(i - 1)
		var segment := a.distance_to(b)

		if length + segment > trail_length:
			line.set_point_position(i - 1, a.move_toward(b, trail_length - length))

			for j in range(i - 1):
				line.remove_point(0)

			return

		length += segment

# the bullet is gone, the trail keeps flowing into where it stopped
func fade_trail(delta: float) -> void:
	var travel := props.speed * RegolithWorld.pixels_per_unit() * delta

	while line.get_point_count() > 1 and travel > 0.0:
		var a := line.get_point_position(0)
		var b := line.get_point_position(1)
		var segment := a.distance_to(b)

		if segment <= travel:
			travel -= segment
			line.remove_point(0)
		else:
			line.set_point_position(0, a.move_toward(b, travel))
			travel = 0.0

	if line.get_point_count() <= 1:
		queue_free()
