extends Node2D
class_name Weapon

# child of a RegolithSprite. the owner sets the fire state each frame, the
# weapon spawns projectiles on the physics step when the cooldown allows.
# beam props keep one beam alive while the trigger is held instead

@export var props: WeaponProps:
	set(value):
		props = value
		ammo = props.ammo if props else 0
		charge = props.charge if props is BeamWeaponProps else 0.0

@export var local_fire_origin := Vector2.ZERO

var triggered := false
var aim_direction := Vector2.RIGHT

var ammo := 0:
	set(value):
		var had := ammo != 0
		ammo = value

		if had and ammo == 0:
			emptied.emit()

var charge := 0.0
var cooldown := 0.0
var charge_time := 0.0
var beam: SuperLaser

signal fired(bullet: Node2D)
signal charging(position: Vector2, ratio: float)
signal cooling(position: Vector2, ratio: float)
signal emptied

func set_fire_state(is_triggered: bool, direction: Vector2) -> void:
	triggered = is_triggered

	if direction.length_squared() > 0.0:
		aim_direction = direction.normalized()

func holder() -> RegolithSprite:
	return get_parent() as RegolithSprite

func fire_origin() -> Vector2:
	var sprite := holder()
	if sprite == null:
		return global_position
	if local_fire_origin == Vector2.ZERO:
		return sprite.get_center_of_mass()
	return sprite.to_global(local_fire_origin * RegolithWorld.pixels_per_unit())

static func projectile_parent() -> Node:
	var world := RegolithWorld.active()
	return world.get_parent() if world else null

func _physics_process(delta: float) -> void:
	if cooldown > 0.0 and props != null and props.delay_cooldown > 0.0:
		cooling.emit(fire_origin(), cooldown / props.delay_cooldown)
	cooldown = maxf(cooldown - delta, 0.0)

	if props == null or props.projectile_scene == null:
		return

	if props is BeamWeaponProps:
		hold_beam(delta)
		return

	if not triggered or cooldown > 0.0 or ammo == 0:
		charge_time = 0.0
		return

	if props.delay_charge > 0.0:
		charge_time = minf(charge_time + delta, props.delay_charge)
		charging.emit(fire_origin(), charge_time / props.delay_charge)
		if charge_time < props.delay_charge:
			return
		charge_time = 0.0

	fire()
	cooldown = props.delay_cooldown

	if ammo > 0:
		ammo -= 1

func hold_beam(delta: float) -> void:
	var lit := is_instance_valid(beam) and not beam.dead

	if not triggered or charge <= 0.0 or ammo == 0:
		if lit:
			beam.release()
		return

	if lit:
		var beam_props: BeamWeaponProps = props
		charge = maxf(charge - beam_props.charge_drain * delta, 0.0)
		beam.aim(fire_origin(), aim_direction)
	elif not is_instance_valid(beam):
		beam = spawn_projectile(fire_origin(), aim_direction) as SuperLaser

func _exit_tree() -> void:
	if is_instance_valid(beam):
		beam.release()

func fire() -> void:
	var origin := fire_origin()

	for i in range(props.shots_per_ammo):
		var direction := aim_direction.rotated(props.inaccuracy_angle * randf_range(-0.5, 0.5))
		var tangent := Vector2(-aim_direction.y, aim_direction.x)
		var position := origin + tangent * props.inaccuracy_tangent * randf_range(-0.5, 0.5) * RegolithWorld.pixels_per_unit()
		spawn_projectile(position, direction)

func spawn_projectile(position: Vector2, direction: Vector2) -> Node2D:
	var parent := projectile_parent()
	if parent == null:
		return null

	var sprite := holder()
	var holder_velocity := sprite.linear_velocity if sprite else Vector2.ZERO

	var bullet: Node2D = props.projectile_scene.instantiate()
	bullet.setup(props, position, direction, holder_velocity, sprite)
	parent.add_child(bullet)
	fired.emit(bullet)
	return bullet
