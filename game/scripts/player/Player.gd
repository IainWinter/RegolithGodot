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
signal item_collected(props: ItemProps)

var core_lost := false

var cloud: PlayerCloud

func _ready() -> void:
	for child in get_children():
		if child is Weapon:
			weapons.append(child)
			child.emptied.connect(on_weapon_emptied.bind(child))
		elif child is PlayerCloud:
			cloud = child

	weapon = weapons[0] if not weapons.is_empty() else null

	for slot in weapons.size():
		var action: StringName = Controls.WEAPONS[slot] if slot < Controls.WEAPONS.size() else &""
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
	var movement := Input.get_vector(Controls.MOVE_LEFT, Controls.MOVE_RIGHT, Controls.MOVE_UP, Controls.MOVE_DOWN)
	desired_velocity = movement * move_speed()

	if Input.is_action_just_pressed(Controls.DASH) and movement.length_squared() > 0.0:
		dash_direction = movement.normalized()

	for slot in weapon_actions.size():
		var action := weapon_actions[slot]
		if not action.is_empty() and Input.is_action_just_pressed(action):
			select_weapon(slot)

	if Input.is_action_just_pressed(Controls.NEXT_WEAPON):
		select_weapon((weapons.find(weapon) + 1) % weapons.size())

	if weapon:
		weapon.set_fire_state(Input.is_action_pressed(Controls.SHOOT) and not is_cloud(), assisted_aim())

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

# where the shot leaves, PlayerShoot aimed from the center of mass and so
# does the weapon
var last_aim := Vector2.RIGHT

func aim_origin() -> Vector2:
	return weapon.fire_origin() if weapon else get_center_of_mass()

func aim_direction() -> Vector2:
	var to_mouse := get_global_mouse_position() - aim_origin()

	if not to_mouse.is_finite() or to_mouse.is_zero_approx():
		return last_aim

	last_aim = to_mouse.normalized()
	return last_aim

# the aim bent onto what the shot would meet, PlayerShoot's aim assist,
# when the settings allow it and the weapon asks for it
func assisted_aim() -> Vector2:
	var direction := aim_direction()

	if weapon == null or weapon.props == null or weapon.props.aim_assist_degrees <= 0.0 or not GameSettings.aim_assist:
		return direction

	var world := RegolithWorld.active()

	if world == null:
		return direction

	return AimAssist.apply(world, self, weapon.props, aim_origin(), direction)

func is_cloud() -> bool:
	return cloud != null and cloud.is_cloud

# the cloud moves faster than the ship
func move_speed() -> float:
	return cloud.cloud_speed if is_cloud() else speed

# an item landed on the ship, the PlayerCollectHealthEvent and
# PlayerCollectEnergyEvent: health puts hull cells back one at a time, the
# cell with the most live neighbours nearest the hull's root first, a core
# puts core cells back and feeds the cloud, which rebuilds the whole ship
# when it is one, and an energy item pours sand into the power tank
func collect_item(props: ItemProps) -> void:
	if props.is_core():
		if cloud:
			cloud.collect_core()

		for i in props.heal_cells:
			repair_cells_of_type(RegolithSprite.CELL_CORE)
	elif props.is_energy():
		var tank := power_tank()

		if tank and props.power_cells > 0:
			tank.queue_cells(props.power_cells, props.power_color)
	else:
		for i in props.heal_cells:
			repair_cells_of_type(RegolithSprite.CELL_FILLED)

	item_collected.emit(props)

# the PowerTank the ship feeds: a child of the ship, else the one on the hud
func power_tank() -> PowerTank:
	for child in get_children():
		if child is PowerTank:
			return child

	if not is_inside_tree():
		return null

	return get_tree().get_first_node_in_group("power_tank") as PowerTank
