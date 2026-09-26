extends Node2D
class_name Weapon

# child of a RegolithSprite. the owner sets the fire state each frame, the
# weapon spawns projectiles on the physics step when the cooldown allows.
# beam props drain their charge while the trigger is held instead of ammo

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

# the effect spawner hears every shot once per weapon, for the muzzle
# flash and the burst of anything the shot later explodes into
func _ready() -> void:
	var effects := EffectSpawner.active()

	if effects:
		fired.connect(effects.on_fired)

func _physics_process(delta: float) -> void:
	if cooldown > 0.0 and props != null and props.delay_cooldown > 0.0:
		cooling.emit(fire_origin(), cooldown / props.delay_cooldown)
	cooldown = maxf(cooldown - delta, 0.0)

	if props == null or props.projectile_scene == null:
		return

	if not triggered or ammo == 0 or (props is BeamWeaponProps and charge <= 0.0):
		charge_time = 0.0
		return

	if props is BeamWeaponProps:
		var beam_props: BeamWeaponProps = props
		charge = maxf(charge - beam_props.charge_drain * delta, 0.0)

	if cooldown > 0.0:
		charge_time = 0.0
		return

	if props.delay_charge > 0.0:
		charge_time = minf(charge_time + delta, props.delay_charge)
		charging.emit(fire_origin(), charge_time / props.delay_charge)
		if charge_time < props.delay_charge:
			return
		charge_time = 0.0

	fire(0, props.spread_angle)
	cooldown = props.delay_cooldown

	if ammo > 0:
		ammo -= 1

# count zero fires the props' shots_per_ammo. a spread of TAU or more
# spaces the shots around a full ring, a smaller spread fans them evenly
# across it, as the original weapon system did for burst requests
func fire(count := 0, spread := 0.0) -> void:
	var origin := fire_origin()
	var shots := count if count > 0 else props.shots_per_ammo

	for i in range(shots):
		var angle := 0.0

		if spread >= TAU:
			angle = float(i) / float(shots) * TAU
		elif spread > 0.0 and shots > 1:
			angle = (float(i) / float(shots - 1) - 0.5) * spread

		var direction := aim_direction.rotated(angle + props.inaccuracy_angle * randf_range(-0.5, 0.5))
		var tangent := Vector2(-aim_direction.y, aim_direction.x)
		var position := origin + tangent * props.inaccuracy_tangent * randf_range(-0.5, 0.5) * RegolithWorld.pixels_per_unit()
		spawn_projectile(position, direction)

# a launch_speed of zero or more overrides the props' speed on projectiles
# that carry one, the way the missile targeter lobs its missiles slowly
func spawn_projectile(position: Vector2, direction: Vector2, launch_speed := -1.0) -> Node2D:
	var parent := projectile_parent()
	if parent == null:
		return null

	var sprite := holder()
	var holder_velocity := sprite.linear_velocity if sprite else Vector2.ZERO

	var bullet: Node2D = props.projectile_scene.instantiate()
	bullet.setup(props, position, direction, holder_velocity, sprite)

	if launch_speed >= 0.0:
		if "speed" in bullet:
			bullet.speed = launch_speed

		if "velocity" in bullet:
			bullet.velocity = direction * launch_speed

	parent.add_child(bullet)
	fired.emit(bullet)
	return bullet
