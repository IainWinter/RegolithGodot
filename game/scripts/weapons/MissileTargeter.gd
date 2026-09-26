extends Node2D
class_name MissileTargeter

# port of HomingMissileTargetingSystem: while the trigger is held with the
# missile weapon selected, a ray from the player to the cursor paints a
# lock on the first cell it finds every acquire_interval, up to max_targets
# and never two within min_spacing of each other. letting go ripples one
# missile per fire_interval at the locks in order, each launched slowly
# along the cursor with a little spread, spending one ammo each. a
# spinning reticle marks every lock and rides along with its sprite. child
# of the player sprite, next to the missile weapon it drives. it takes the
# trigger away from the weapon so the weapon never fires by itself

const ACQUIRE_INTERVAL := 0.05
const FIRE_INTERVAL := 0.05
const MAX_TARGETS := 12
const TARGETER_SPIN_SPEED := 3.0
const MIN_TARGET_SPACING_FACTOR := 0.8
const LAUNCH_SPEED := 3.0
const LAUNCH_SPREAD := 0.4

@export var weapon: Weapon
# reticle size in units
@export var targeter_size := 0.5
@export var reticle_color := Color(1.0, 0.3, 0.2, 0.9)
# aim at the mouse when set, else at aim_point
@export var use_input := true

var aim_point := Vector2.ZERO
var player: RegolithSprite
var targets: Array = []
var held := false
var was_held := false
var firing := false
var acquire_timer := 0.0
var fire_timer := 0.0

signal locked(sprite: RegolithSprite, position: Vector2)
signal launched(missile: Node2D)

func _ready() -> void:
	player = get_parent() as RegolithSprite

	if weapon == null and player != null:
		for child in player.get_children():
			if child is Weapon and child.props is HomingWeaponProps and child.name == "Missiles":
				weapon = child
				break

func selected() -> bool:
	return weapon != null and player != null and player.get("weapon") == weapon

func set_fire_state(pull_trigger: bool, at: Vector2) -> void:
	held = pull_trigger
	aim_point = at

func _process(delta: float) -> void:
	if selected():
		# the player pulled the weapon's trigger this frame, it is ours now
		if use_input:
			held = weapon.triggered
			aim_point = get_global_mouse_position()

		weapon.triggered = false
	else:
		held = false

	for target in targets:
		target["angle"] += delta * TARGETER_SPIN_SPEED

	queue_redraw()

func target_world(target: Dictionary) -> Vector2:
	var sprite: RegolithSprite = target["sprite"]

	if sprite != null and is_instance_valid(sprite) and sprite.is_inside_tree():
		return sprite.to_global(target["local"])

	return target["world"]

func origin() -> Vector2:
	return weapon.fire_origin() if weapon != null else global_position

func _physics_process(delta: float) -> void:
	if weapon == null or player == null:
		return

	if held:
		if not was_held:
			targets.clear()
			acquire_timer = 0.0
			firing = false

		acquire_timer += delta

		while acquire_timer >= ACQUIRE_INTERVAL:
			acquire_timer -= ACQUIRE_INTERVAL

			if targets.size() >= MAX_TARGETS:
				acquire_timer = 0.0
				break

			acquire()
	else:
		if was_held:
			firing = not targets.is_empty()
			fire_timer = 0.0

		if firing:
			fire_timer += delta

			while fire_timer >= FIRE_INTERVAL and not targets.is_empty():
				fire_timer -= FIRE_INTERVAL
				fire_one(targets.pop_front())

				if weapon.ammo == 0:
					targets.clear()

			if targets.is_empty():
				firing = false

	was_held = held

func acquire() -> void:
	var world := RegolithWorld.active()

	if world == null:
		return

	var from := origin()

	if from.distance_to(aim_point) <= 0.0:
		return

	var hit: Dictionary = world.ray_cast(from, aim_point, player)

	if hit.is_empty():
		return

	var ppu := RegolithWorld.pixels_per_unit()
	var spacing := targeter_size * ppu * MIN_TARGET_SPACING_FACTOR
	var world_point: Vector2 = hit["position"]

	for other in targets:
		if target_world(other).distance_squared_to(world_point) < spacing * spacing:
			return

	var sprite: RegolithSprite = hit["sprite"]
	var target := {"sprite": sprite, "local": sprite.to_local(world_point), "world": world_point, "angle": 0.0}
	targets.append(target)
	locked.emit(sprite, world_point)

func fire_one(target: Dictionary) -> void:
	var parent := Weapon.projectile_parent()

	if parent == null or weapon.props == null or weapon.props.projectile_scene == null:
		return

	var from := origin()
	var cursor_angle := (aim_point - from).angle()
	var launch_dir := Vector2.from_angle(cursor_angle + randf_range(-LAUNCH_SPREAD * 0.5, LAUNCH_SPREAD * 0.5))

	if weapon.ammo > 0:
		weapon.ammo -= 1

	var missile: Node2D = weapon.props.projectile_scene.instantiate()
	missile.setup(weapon.props, from, launch_dir, player.linear_velocity, player)

	if "speed" in missile:
		missile.speed = LAUNCH_SPEED

	if "velocity" in missile:
		missile.velocity = launch_dir * LAUNCH_SPEED

	if missile.has_method("set_target"):
		var sprite: RegolithSprite = target["sprite"]

		if sprite != null and is_instance_valid(sprite):
			missile.set_target(sprite, target["local"])
		else:
			missile.set_target(null, Vector2.ZERO)
			missile.target_world = target["world"]

	parent.add_child(missile)
	weapon.fired.emit(missile)
	launched.emit(missile)

func _draw() -> void:
	if targets.is_empty():
		return

	var half := targeter_size * RegolithWorld.pixels_per_unit() * 0.5

	for target in targets:
		var center := to_local(target_world(target))
		var angle: float = target["angle"]
		var points := PackedVector2Array()

		for i in 4:
			points.append(center + Vector2(half, half).rotated(angle + i * PI * 0.5))

		points.append(points[0])
		draw_polyline(points, reticle_color, 1.0)
