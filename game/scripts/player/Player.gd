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

var weapons: Array[Weapon] = []
var weapon: Weapon

var weapon_actions: Array[StringName] = []

signal dashed(direction: Vector2)
signal core_destroyed
signal weapon_changed(weapon: Weapon)

var core_lost := false

func _ready() -> void:
	for child in get_children():
		if child is Weapon:
			weapons.append(child)
			child.emptied.connect(on_weapon_emptied.bind(child))

	weapon = weapons[0] if not weapons.is_empty() else null

	for slot in weapons.size():
		var action := StringName("weapon_%d" % (slot + 1))
		weapon_actions.append(action if InputMap.has_action(action) else &"")

	var world := RegolithWorld.active()

	if world:
		world.cells_removed.connect(on_cells_removed)
		world.sprite_split.connect(on_sprite_split)

func on_cells_removed(sprite: RegolithSprite, _count: int) -> void:
	if sprite == self:
		check_core()

func on_sprite_split(source: RegolithSprite, _piece: RegolithSprite) -> void:
	if source == self:
		check_core()

func check_core() -> void:
	var lost := count_cells_of_type(RegolithSprite.CELL_CORE) == 0 and get_active_cell_count() > 0

	if lost and not core_lost:
		core_destroyed.emit()

	core_lost = lost

func on_weapon_emptied(emptied: Weapon) -> void:
	if emptied == weapon and emptied != weapons[0]:
		select_weapon(0)

func _process(_delta: float) -> void:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	desired_velocity = movement * speed

	if Input.is_action_just_pressed("dash") and movement.length_squared() > 0.0:
		dash_direction = movement.normalized()

	for slot in weapon_actions.size():
		var action := weapon_actions[slot]
		if not action.is_empty() and Input.is_action_just_pressed(action):
			select_weapon(slot)

	if Input.is_action_just_pressed("next_weapon"):
		select_weapon((weapons.find(weapon) + 1) % weapons.size())

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

func select_weapon(slot: int) -> void:
	if slot < 0 or slot >= weapons.size() or weapons[slot] == weapon:
		return

	if weapon:
		weapon.set_fire_state(false, weapon.aim_direction)

	weapon = weapons[slot]
	weapon_changed.emit(weapon)

func aim_direction() -> Vector2:
	return (get_global_mouse_position() - global_position).normalized()
