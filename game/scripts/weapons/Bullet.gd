extends Node2D
class_name Bullet

# a point that eats cells along its path. each physics step it walks the
# distance its speed allows, burning the nearest filled cell it reaches and
# carrying on from there with a slightly bent direction, until its cell life
# runs out or the step distance is spent. the walk from cell to cell is a
# grid line trace (the original GridLineIterator): the point where the line
# crosses into each cell is kept with its sub cell offset, so a shallow shot
# carves a true angled tunnel one cell wide instead of snapping to the axis.
# ending a step inside a sprite embeds it there, at that fractional grid
# point, so it rides along with that sprite until the next step. leaving a
# sprite throws the bullet with that sprite's velocity, kept apart from its
# own speed so lodging again does not stack it up. the hit impulse lands
# once at the impact point when the bullet enters a sprite, and again only
# if it truly leaves and comes back in. a step that ends inside an active
# cell of the lodged sprite keeps it embedded even if the leftover distance
# was too short to reach the next cell. a hit may also spit off a second
# bullet with half the remaining cell life, as the original bullets did

var props: WeaponProps
var velocity := Vector2.ZERO
var carry_velocity := Vector2.ZERO
var lifetime := 0.0
var cell_life := 0
var initial_cell_life := 0
var rotation_bias := 0.0
var spit_odds := 0.0
var shooter: RegolithSprite

var embedded_sprite: RegolithSprite
# fractional grid point inside the embedded sprite, the bore continues from
# here next step with its sub cell offset intact
var embedded_grid_point := Vector2.ZERO
var embedded_angle := 0.0

var dead := false
var pixels_per_unit := 0.0
var cell_px := 0.0
var trail_px := 0.0
var trail: Trail

var tip_from := Vector2.ZERO
var tip_to := Vector2.ZERO
var visual: Sprite2D

# how far around a hit cell the empty cells count toward its surface normal
const SURFACE_NORMAL_RADIUS := 2

# how far a hit's burn_fracture reaches, SpriteBurn.cpp's k_fracture_size 9
const FRACTURE_RADIUS := 4

# the cells that were filled around this frame's bullet hits before those
# hits landed, a set of Vector2i by sprite instance id. the original decided
# "surface" off the sprite's distance field, and that field was rebuilt only
# at the frame's SpriteCommit, so the cells a hit had just removed, the
# bored cell and what its fracture took around it, still read as filled for
# the rest of the frame: a bullet sparked where it entered a sprite, never
# down the length of its tunnel. every bullet and spit child of the frame
# shares this record the way they all read the same stale field
static var filled_frame := -1
static var filled_before := {}

signal hit_cell(sprite: RegolithSprite, cell: Vector2i, position: Vector2)
# a cell of a core was hit, the Items autoload knocks a core item loose off the player
signal core_hit(sprite: RegolithSprite, position: Vector2, direction: Vector2)

func setup(weapon_props: WeaponProps, start: Vector2, direction: Vector2, holder_velocity: Vector2, holder: RegolithSprite) -> void:
	props = weapon_props
	global_position = start
	velocity = direction.normalized() * (props.speed + props.speed_random * randf_range(-0.5, 0.5))
	lifetime = props.lifetime + props.lifetime_random * randf_range(-0.5, 0.5)
	cell_life = props.cell_life
	initial_cell_life = cell_life
	# the original RandomFloatCentered, a full -1..1 so half the shots hook hard
	rotation_bias = randf_range(-1.0, 1.0)
	spit_odds = props.spit_odds
	shooter = holder
	pixels_per_unit = RegolithWorld.pixels_per_unit()
	cell_px = RegolithWorld.pixels_per_cell()
	trail_px = props.trail_length * pixels_per_unit
	tip_from = start
	tip_to = start

func _ready() -> void:
	add_to_group("projectile")
	trail = Trail.new()
	trail.setup(props, cell_px, global_position)
	add_child(trail)

	if props.texture != null:
		visual = Sprite2D.new()
		visual.texture = props.texture
		visual.modulate = props.color_front
		visual.scale = Vector2.ONE * props.texture_scale
		visual.rotation = velocity.angle()
		add_child(visual)

func _process(delta: float) -> void:
	if dead:
		if visual != null:
			visual.visible = false
		if trail.fade(props.speed * pixels_per_unit * delta):
			queue_free()
		return

	trail.set_tip(tip_from.lerp(tip_to, Engine.get_physics_interpolation_fraction()))
	trail.trim(trail_px)

	if visual != null:
		visual.rotation = velocity.angle()

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
		position = embedded_sprite.grid_point_to_world(embedded_grid_point)
		velocity = velocity.rotated(embedded_sprite.global_rotation - embedded_angle)
		embedded_angle = embedded_sprite.global_rotation
	else:
		embedded_sprite = null

	var own_speed := velocity.length()
	var world_velocity := velocity + carry_velocity
	var direction := world_velocity.normalized()
	var remaining := world_velocity.length() * pixels_per_unit * delta
	var hit_any := false
	var ejected := false
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
			if embedded_sprite != null:
				# still lodged when the leftover distance ends in a filled cell
				# or in the hole this step just bored, past that it is out
				var end_cell := embedded_sprite.world_to_cell(end)
				if embedded_sprite.has_cell(end_cell) or (hit_any and end_cell == last_cell):
					embedded_grid_point = embedded_sprite.world_to_grid_point(end)
				else:
					ejected = true
			break

		var sprite: RegolithSprite = hit["sprite"]
		var hit_cell_index: Vector2i = hit["cell"]
		var hit_type := sprite.get_cell_type(hit_cell_index)

		# the hit spark of the original's SpriteEffectsEventHandler: a cell
		# hit at the surface of a sprite sparks out along the surface normal
		# there, cells bored deep inside are silent. read before the hit
		# lands, with what this frame's hits removed counted as filled, so
		# the cell behind the one just removed is not a surface cell and
		# the normal is the face the bullet came through, not the tunnel.
		# the sparks leave at the bullet's own speed into this cell, in the
		# hue of its trail head
		var filled: Dictionary = record_filled_around(sprite, hit_cell_index)
		var normal := surface_normal(sprite, hit_cell_index, -direction, filled)

		var cell_position := Explosion.hit_cell(world, props, sprite, hit_cell_index, direction * randf_range(1.0, 4.0) * pixels_per_unit)
		hit_cell.emit(sprite, hit_cell_index, cell_position)

		if hit_type == RegolithSprite.CELL_CORE:
			core_hit.emit(sprite, cell_position, direction)

		if normal != Vector2.ZERO:
			var effects := EffectSpawner.active()
			if effects:
				effects.spark(cell_position, normal.angle(), own_speed, props.color_front)

		if sprite != embedded_sprite:
			sprite.apply_impulse(velocity * props.mass, cell_position, props.max_hit_speed, props.max_hit_spin)

		cell_life -= 1
		hit_any = true
		last_sprite = sprite
		last_cell = hit_cell_index

		# carry on from where the line crosses into the cell, not its center,
		# the trace skips this cell next round so the walk keeps its true angle
		remaining -= hit["distance"]
		position = hit["entry"]
		trail.push(cell_position)

		embedded_sprite = sprite
		embedded_grid_point = sprite.world_to_grid_point(position)
		embedded_angle = sprite.global_rotation

		if cell_life <= 0:
			break

		if randf() < spit_odds:
			spit(cell_position, direction, own_speed)

		# the original per cell turn: rotation_factor * bias * frame delta,
		# fading with the cell life left so a tunnel starts hooked and straightens
		var bend := props.rotation_factor * rotation_bias * delta * float(cell_life) / float(initial_cell_life)
		direction = direction.rotated(bend)
		own_speed *= 1.0 - props.speed_loss_per_cell * randf_range(0.5, 1.5)

	if hit_any:
		carry_velocity = Vector2.ZERO

	velocity = direction * own_speed

	if ejected:
		velocity += embedded_sprite.get_velocity_at(position)
		embedded_sprite = null

	global_position = position
	lifetime -= delta

	tip_from = trail.tip()
	tip_to = position
	trail.push(tip_from)

	if lifetime <= 0.0 or cell_life <= 0:
		dead = true
		trail.set_tip(tip_to)

# the frame's record of what was filled around sprite's hits, a set of
# Vector2i. a new frame starts the records over
static func filled_this_frame(sprite: RegolithSprite) -> Dictionary:
	var frame := Engine.get_physics_frames()

	if frame != filled_frame:
		filled_frame = frame
		filled_before = {}

	var id := sprite.get_instance_id()

	if not filled_before.has(id):
		filled_before[id] = {}

	return filled_before[id]

# adds every filled cell within the fracture's reach of a hit to the frame's
# record, before the hit lands, and returns the record. covers the bored
# cell and whatever its fracture removes around it
static func record_filled_around(sprite: RegolithSprite, cell: Vector2i) -> Dictionary:
	var filled := filled_this_frame(sprite)

	for dy in range(-FRACTURE_RADIUS, FRACTURE_RADIUS + 1):
		for dx in range(-FRACTURE_RADIUS, FRACTURE_RADIUS + 1):
			var around := cell + Vector2i(dx, dy)
			if sprite.has_cell(around):
				filled[around] = true

	return filled

# the outward normal of the sprite surface at a cell in world space, the
# distance field gradient the original sampled at the hit cell: the mean
# direction to the empty cells within SURFACE_NORMAL_RADIUS of it. zero
# for a cell with no empty neighbor, which is not a surface cell (the
# original's sdf > -1 test: an edge cell reads -0.5, a cell touching an
# empty one only diagonally -0.91, the next layer in -1.5) and gets no
# spark. the keys of filled count as filled although they are gone, what
# this frame's hits removed that the original's field still held. fallback
# stands in when the empty cells around a surface cell cancel out, a one
# cell strut
static func surface_normal(sprite: RegolithSprite, cell: Vector2i, fallback := Vector2.ZERO, filled: Dictionary = {}) -> Vector2:
	var center := sprite.cell_to_world(cell)
	var step_x := sprite.cell_to_world(cell + Vector2i(1, 0)) - center
	var step_y := sprite.cell_to_world(cell + Vector2i(0, 1)) - center
	var sum := Vector2.ZERO
	var surface := false

	for dy in range(-SURFACE_NORMAL_RADIUS, SURFACE_NORMAL_RADIUS + 1):
		for dx in range(-SURFACE_NORMAL_RADIUS, SURFACE_NORMAL_RADIUS + 1):
			var neighbor := cell + Vector2i(dx, dy)
			if (dx == 0 and dy == 0) or sprite.has_cell(neighbor) or filled.has(neighbor):
				continue

			sum += step_x * dx + step_y * dy

			if absi(dx) <= 1 and absi(dy) <= 1:
				surface = true

	if not surface:
		return Vector2.ZERO

	var normal := sum.normalized()
	return normal if normal != Vector2.ZERO else fallback.normalized()

# the nearest filled cell any sprite has along the segment, with the distance
# to where the segment crosses into it and that crossing point
func find_first_cell(world: RegolithWorld, from: Vector2, to: Vector2, skip_sprite: RegolithSprite, skip_cell: Vector2i) -> Dictionary:
	var best := {}
	var best_distance := INF

	for sprite in world.query_segment(from, to):
		if sprite == shooter:
			continue

		var found := trace_first_cell(sprite, from, to, skip_sprite == sprite, skip_cell)

		if not found.is_empty() and found["distance"] < best_distance:
			best_distance = found["distance"]
			best = found

	return best

# walks the segment through one sprite's grid cell by cell along its exact
# line (the original GridLineIterator, a DDA) and returns the first filled
# cell that is not the skipped one, with the world distance to the point
# where the line enters it. a start sitting on a cell edge counts as inside
# the cell ahead of it
func trace_first_cell(sprite: RegolithSprite, from: Vector2, to: Vector2, skip: bool, skip_cell: Vector2i) -> Dictionary:
	var start := sprite.world_to_grid_point(from)
	var finish := sprite.world_to_grid_point(to)
	var length := start.distance_to(finish)

	if length <= 0.0:
		return {}

	var dir := (finish - start) / length
	var cell := Vector2i(floori(start.x + dir.x * 0.001), floori(start.y + dir.y * 0.001))
	var step_x := 0
	var step_y := 0
	var t_delta_x := INF
	var t_delta_y := INF
	var t_max_x := INF
	var t_max_y := INF

	if dir.x != 0.0:
		t_delta_x = 1.0 / absf(dir.x)
		step_x = 1 if dir.x > 0.0 else -1
		t_max_x = ((float(cell.x + 1) - start.x) if dir.x > 0.0 else (start.x - float(cell.x))) * t_delta_x

	if dir.y != 0.0:
		t_delta_y = 1.0 / absf(dir.y)
		step_y = 1 if dir.y > 0.0 else -1
		t_max_y = ((float(cell.y + 1) - start.y) if dir.y > 0.0 else (start.y - float(cell.y))) * t_delta_y

	var t := 0.0
	var world_per_grid := from.distance_to(to) / length

	while t <= length:
		if sprite.has_cell(cell) and not (skip and cell == skip_cell):
			var distance := t * world_per_grid
			return {"sprite": sprite, "cell": cell, "distance": distance, "entry": from + (to - from) * (t / length)}

		if t_max_x < t_max_y:
			cell.x += step_x
			t = t_max_x
			t_max_x += t_delta_x
		else:
			cell.y += step_y
			t = t_max_y
			t_max_y += t_delta_y

	return {}

# a second bullet thrown off a hit, kicked up to fifteen degrees off course
# with half the remaining cell life and half the odds of spitting again
func spit(from: Vector2, direction: Vector2, speed: float) -> void:
	var life := cell_life / 2
	var parent := get_parent()

	if life < 1 or parent == null or props.projectile_scene == null:
		return

	var kick := direction.rotated(randf_range(-0.5, 0.5) * PI / 6.0)
	var child := props.projectile_scene.instantiate() as Bullet

	if child == null:
		return

	child.setup(props, from + kick * cell_px * 0.51, kick, Vector2.ZERO, shooter)
	child.velocity = kick * speed
	child.lifetime = lifetime
	child.cell_life = life
	child.initial_cell_life = life
	child.spit_odds = spit_odds * 0.5
	parent.add_child(child)
