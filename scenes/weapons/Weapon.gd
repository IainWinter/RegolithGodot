extends Node2D
class_name Weapon

# child of a RegolithSprite. the owner sets the fire state each frame, the
# weapon spawns bullets on the physics step when the cooldown allows

@export var props: WeaponProps
@export var bullet_scene: PackedScene

# where bullets leave the holder, sim units from its origin, rotates with it
@export var local_fire_origin := Vector2.ZERO

var triggered := false
var aim_direction := Vector2.RIGHT
var ammo := 0
var cooldown := 0.0

signal fired(bullet: Node2D)

func _ready() -> void:
	if props:
		ammo = props.ammo

func set_fire_state(is_triggered: bool, direction: Vector2) -> void:
	triggered = is_triggered

	if direction.length_squared() > 0.0:
		aim_direction = direction.normalized()

func _physics_process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)

	if not triggered or cooldown > 0.0 or props == null or bullet_scene == null:
		return

	if ammo == 0:
		return

	fire()
	cooldown = props.delay_cooldown

	if ammo > 0:
		ammo -= 1

func fire() -> void:
	var holder := get_parent() as RegolithSprite
	var holder_velocity := holder.linear_velocity if holder else Vector2.ZERO
	var origin := holder.to_global(local_fire_origin * RegolithWorld.pixels_per_unit()) if holder else global_position

	for i in range(props.shots_per_ammo):
		var direction := aim_direction.rotated(props.inaccuracy_angle * randf_range(-0.5, 0.5))
		var tangent := Vector2(-aim_direction.y, aim_direction.x)
		var position := origin + tangent * props.inaccuracy_tangent * randf_range(-0.5, 0.5) * RegolithWorld.pixels_per_unit()

		var bullet: Node2D = bullet_scene.instantiate()
		bullet.setup(props, position, direction, holder_velocity, holder)
		get_tree().current_scene.add_child(bullet)
		fired.emit(bullet)
