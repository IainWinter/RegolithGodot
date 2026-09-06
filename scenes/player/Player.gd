extends RegolithSprite
class_name Player

# sim units, one unit is one chunk of cells

@export var speed := 5.0
@export var acceleration_factor := 15.0
@export var dash_impulse := 20.0
@export var dash_cooldown := 3.0

var dash_timer := 0.0

var desired_velocity := Vector2.ZERO
var dash_direction := Vector2.ZERO

signal dashed(direction: Vector2)
signal core_destroyed

@onready var weapon: Weapon = $Weapon

func _process(_delta: float) -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	desired_velocity = movement * speed

	if Input.is_action_just_pressed("dash") and movement.length_squared() > 0.0:
		dash_direction = movement.normalized()

	if weapon:
		weapon.set_fire_state(Input.is_action_pressed("shoot"), aim_direction())

func _physics_process(delta: float) -> void:
	dash_timer = maxf(dash_timer - delta, 0.0)

	if dash_direction != Vector2.ZERO and dash_timer <= 0.0:
		linear_velocity += dash_direction * dash_impulse
		dash_timer = dash_cooldown
		dashed.emit(dash_direction)

	dash_direction = Vector2.ZERO

	linear_velocity = linear_velocity.lerp(desired_velocity, delta * acceleration_factor)

	if count_cells_of_type(RegolithSprite.CELL_CORE) == 0 and get_active_cell_count() > 0:
		core_destroyed.emit()

func aim_direction() -> Vector2:
	return (get_global_mouse_position() - global_position).normalized()
