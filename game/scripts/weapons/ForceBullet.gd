extends Node2D
class_name ForceBullet

# leaves the gun as a slow orb sprayed in a wide arc, then accelerates and
# curves toward its target, a point in a sprite's local space picked at
# launch from what lies along the aim. the orb shrinks into a streak as it
# gains speed. it locks on once the target is ahead of it, and a locked
# bullet that ends up facing away has overshot and flies straight from
# there. explodes on the first cell it crosses or when its lifetime runs out

var props: HomingWeaponProps
var shooter: RegolithSprite

var velocity := Vector2.ZERO
var speed := 0.0
var lifetime := 0.0
var spawn_grace := 0.0

var target_sprite: RegolithSprite
var target_local := Vector2.ZERO
var homing_locked := false

var dead := false
var pixels_per_unit := 0.0
var width_px := 0.0
var trail_px := 0.0
var trail: Trail

signal hit_cell(sprite: RegolithSprite, cell: Vector2i, position: Vector2)
signal exploded(position: Vector2)

func setup(weapon_props: WeaponProps, start: Vector2, direction: Vector2, _holder_velocity: Vector2, holder: RegolithSprite) -> void:
	props = weapon_props
	shooter = holder
	global_position = start
	speed = props.speed
	velocity = direction.normalized() * speed
	lifetime = props.lifetime
	spawn_grace = props.spawn_grace
	pixels_per_unit = RegolithWorld.pixels_per_unit()
	width_px = props.width * pixels_per_unit
	trail_px = props.trail_length * pixels_per_unit

	var world := RegolithWorld.active()
	if world:
		var aim_point := start + velocity.normalized() * props.target_range * pixels_per_unit
		var target := Targeting.find(world, start, aim_point, props.target_search_radius * pixels_per_unit, holder)
		if not target.is_empty():
			set_target(target["sprite"], target["local_position"])

func set_target(sprite: RegolithSprite, local_position: Vector2) -> void:
	target_sprite = sprite
	target_local = local_position
	homing_locked = false

func _ready() -> void:
	trail = Trail.new()
	trail.setup(props, width_px, global_position)
	add_child(trail)

func orb_radius() -> float:
	var top := maxf(props.max_speed, props.speed)
	var slow := 1.0 - clampf(speed / top, 0.0, 1.0)
	return width_px * (0.5 + 1.5 * slow)

func _draw() -> void:
	if dead:
		return

	var radius := orb_radius()
	draw_circle(Vector2.ZERO, radius, props.color_front)
	draw_circle(Vector2.ZERO, radius * 0.5, Color(1.0, 1.0, 1.0, 0.8))

func target_position() -> Vector2:
	if target_sprite and is_instance_valid(target_sprite) and target_sprite.is_inside_tree():
		return target_sprite.to_global(target_local)

	target_sprite = null
	return global_position

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

	if props.acceleration > 0.0 and speed < props.max_speed:
		speed = minf(speed + props.acceleration * delta, props.max_speed)

	velocity = velocity.normalized() * speed

	if target_sprite:
		var to_target := target_position() - global_position

		if target_sprite:
			if velocity.dot(to_target) >= 0.0:
				homing_locked = true
			elif homing_locked:
				target_sprite = null

			var heading := Steering.turn_toward(velocity.angle(), to_target.angle(), props.turn_speed * delta)
			velocity = Vector2.from_angle(heading) * speed

	var position := global_position
	var next := position + velocity * pixels_per_unit * delta
	trail.push(position)

	if spawn_grace > 0.0:
		spawn_grace -= delta
	else:
		var hit: Dictionary = world.ray_cast(position, next, shooter)

		if not hit.is_empty():
			var cell_position: Vector2 = hit["position"]
			hit_cell.emit(hit["sprite"], hit["cell"], cell_position)
			global_position = cell_position
			trail.push(cell_position)
			explode(cell_position, hit["sprite"], hit["cell"])
			return

	lifetime -= delta
	if lifetime <= 0.0:
		explode(position)
		return

	global_position = next

func explode(position: Vector2, sprite: RegolithSprite = null, cell := Vector2i(-1, -1)) -> void:
	dead = true
	Explosion.burst(props, position, shooter, sprite, cell)
	exploded.emit(position)
	queue_redraw()
