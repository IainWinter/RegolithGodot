extends Node2D
class_name Missile

# launched slowly along the aim, coasts, then lights its motor and steers
# at its target: a point in a sprite's local space so it follows the sprite,
# picked at launch from what lies along the aim. the turn rate drops to a
# fifth after the first second so a missile that overshoots swings wide
# instead of circling forever. explodes on the first cell it crosses or
# when its lifetime runs out

var props: HomingWeaponProps
var shooter: RegolithSprite

var angle := 0.0
var speed := 0.0
var velocity := Vector2.ZERO
var coast_remaining := 0.0
var turn_time := 0.0
var lifetime := 0.0

var target_sprite: RegolithSprite
var target_local := Vector2.ZERO
var target_world := Vector2.ZERO

var dead := false
var pixels_per_unit := 0.0
var cell_px := 0.0
var body_px := 0.0
var trail_px := 0.0
var trail: Trail

signal hit_cell(sprite: RegolithSprite, cell: Vector2i, position: Vector2)
signal exploded(position: Vector2)

func setup(weapon_props: WeaponProps, start: Vector2, direction: Vector2, _holder_velocity: Vector2, holder: RegolithSprite) -> void:
	props = weapon_props
	shooter = holder
	global_position = start
	angle = direction.angle()
	speed = props.speed
	velocity = Vector2.from_angle(angle) * speed
	coast_remaining = props.coast_time
	lifetime = props.lifetime
	pixels_per_unit = RegolithWorld.pixels_per_unit()
	cell_px = RegolithWorld.pixels_per_cell()
	body_px = 0.25 * pixels_per_unit
	trail_px = props.trail_length * pixels_per_unit
	target_world = start + direction * props.target_range * pixels_per_unit
	rotation = angle

	var world := RegolithWorld.active()
	if world:
		var target := Targeting.find(world, start, target_world, props.target_search_radius * pixels_per_unit, holder)
		if not target.is_empty():
			set_target(target["sprite"], target["local_position"])

func set_target(sprite: RegolithSprite, local_position: Vector2) -> void:
	target_sprite = sprite
	target_local = local_position

	if sprite:
		target_world = sprite.to_global(local_position)

func _ready() -> void:
	trail = Trail.new()
	trail.setup(props, cell_px * 2.0, global_position)
	add_child(trail)

func _draw() -> void:
	if dead:
		return

	draw_line(Vector2(-body_px * 0.5, 0.0), Vector2(body_px * 0.5, 0.0), props.color_front, cell_px * 2.0)

	if coast_remaining <= 0.0:
		draw_line(Vector2(-body_px * 0.5, 0.0), Vector2(-body_px * 0.9, 0.0), Color(1.0, 0.7, 0.2, 0.9), cell_px * 1.5)

func target_position() -> Vector2:
	if target_sprite and is_instance_valid(target_sprite) and target_sprite.is_inside_tree():
		target_world = target_sprite.to_global(target_local)
	else:
		target_sprite = null

	return target_world

func _process(delta: float) -> void:
	if dead:
		if trail.fade(maxf(speed, 4.0) * pixels_per_unit * delta):
			queue_free()
		return

	queue_redraw()
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

	lifetime -= delta
	if lifetime <= 0.0:
		explode(global_position)
		return

	if coast_remaining > 0.0:
		coast_remaining -= delta
	else:
		speed = minf(speed + props.acceleration * delta, props.max_speed)
		turn_time += delta

		var to_target := target_position() - global_position
		var turn_rate := props.turn_speed if turn_time < 1.0 else props.turn_speed * 0.2
		angle = Steering.turn_toward(angle, to_target.angle(), turn_rate * delta)

	velocity = Vector2.from_angle(angle) * speed
	rotation = angle

	var position := global_position
	var next := position + velocity * pixels_per_unit * delta
	var hit: Dictionary = world.ray_cast(position, next, shooter)

	if not hit.is_empty():
		var cell_position: Vector2 = hit["position"]
		hit_cell.emit(hit["sprite"], hit["cell"], cell_position)
		global_position = cell_position
		trail.push(cell_position)
		explode(cell_position, hit["sprite"], hit["cell"])
		return

	global_position = next
	trail.push(next)

func explode(position: Vector2, sprite: RegolithSprite = null, cell := Vector2i(-1, -1)) -> void:
	dead = true
	Explosion.burst(props, position, shooter, sprite, cell)
	exploded.emit(position)
	queue_redraw()
