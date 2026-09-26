extends Node2D
class_name LightningZap

# port of WeaponSystem::fire_bolt, the player's lightning gun. one shot is
# one instant bolt: the muzzle ray finds the first cell within bolt_range,
# that cell and its neighbours are scorched, and removed when the damage
# odds roll, so a held trigger eats bolt_pixels_per_second on average. the
# bolt is drawn from the muzzle to the hit, or to the end of its range when
# nothing is there, and projectiles near the muzzle get arced at and shoved
# off their heading. the node does its work on its first physics step and
# frees itself. the bolts live on one Lightning shared by every zap under
# the projectile parent, a trigger held at fifty shots a second must not
# make a multimesh per shot. the damage helpers are the bolt_* functions of
# the original DamageEffects, the ball uses them too

const SHARED_LIGHTNING_NAME := &"LightningZapEffect"
# a damage zap takes about this many cells with it, the odds are set from it
const ZAP_EXPECTED_PIXELS := 5.0
const BOLT_BULLET_PUSH := 120.0
const BOLT_BULLET_TURN := 6.0
const BOLT_ITEM_ZAP_ODDS := 0.1

var props: LightningWeaponProps
var direction := Vector2.RIGHT
var shooter: RegolithSprite
var lightning: Lightning
var dead := false

signal hit_cell(sprite: RegolithSprite, cell: Vector2i, position: Vector2)
signal arced(projectile: Node2D)

func setup(weapon_props: WeaponProps, start: Vector2, aim: Vector2, _holder_velocity: Vector2, holder: RegolithSprite) -> void:
	props = weapon_props as LightningWeaponProps
	global_position = start
	direction = aim.normalized() if aim.length_squared() > 0.0 else Vector2.RIGHT
	shooter = holder

	if props == null:
		push_warning("LightningZap: props is not a LightningWeaponProps")

func _ready() -> void:
	if props == null:
		queue_free()
		return

	lightning = shared_lightning(get_parent(), props)

# the one Lightning every zap under this parent strikes on, made on the
# first shot
static func shared_lightning(parent: Node, zap_props: LightningWeaponProps) -> Lightning:
	var existing := parent.get_node_or_null(NodePath(SHARED_LIGHTNING_NAME)) as Lightning

	if existing != null:
		return existing

	var made := Lightning.attach(parent, zap_props.lightning, zap_props.lightning_material)
	made.name = SHARED_LIGHTNING_NAME
	return made

func _physics_process(delta: float) -> void:
	if dead:
		return

	dead = true

	var world := RegolithWorld.active()

	if world == null or not is_instance_valid(lightning):
		queue_free()
		return

	if not is_instance_valid(shooter):
		shooter = null

	var pixels_per_unit := RegolithWorld.pixels_per_unit()
	var start := global_position
	var end := start + direction * props.bolt_range * pixels_per_unit
	var hit: Dictionary = world.ray_cast(start, end, shooter)

	# the odds are set so a held trigger averages bolt_pixels_per_second at
	# the nominal fire rate, as the original did
	var fire_period := maxf(props.delay_charge + props.delay_cooldown, delta)
	var chance := damage_chance(props.bolt_pixels_per_second, 1.0 / fire_period)
	var zapped := zap_target(world, hit, chance)

	if not hit.is_empty():
		end = hit["position"]

	if zapped:
		var sprite: RegolithSprite = hit["sprite"]
		var cell: Vector2i = hit["cell"]
		hit_cell.emit(sprite, cell, sprite.cell_to_world(cell))

	lightning.strike(start, end, shooter, props.hit_props() if zapped else props.lightning)

	for projectile in arc_nearby(world, lightning, props.lightning, start, props.bolt_arc_radius * pixels_per_unit, shooter, delta):
		arced.emit(projectile)

	queue_free()

# bolt_damage_chance: the odds a zap removes cells, so destruction averages
# pixels_per_second at the given zap rate
static func damage_chance(pixels_per_second: float, zaps_per_second: float) -> float:
	if zaps_per_second <= 0.0:
		return 0.0

	return clampf(pixels_per_second / (zaps_per_second * ZAP_EXPECTED_PIXELS), 0.0, 1.0)

# bolt_zap_target: scorch the cells around a ray hit, remove them when the
# odds roll, throw a cell particle. true when a cell was zapped
static func zap_target(world: RegolithWorld, hit: Dictionary, chance: float) -> bool:
	if hit.is_empty():
		return false

	var sprite: RegolithSprite = hit["sprite"]
	var cell: Vector2i = hit["cell"]

	if sprite == null or not is_instance_valid(sprite) or not sprite.has_cell(cell):
		return false

	var cell_position: Vector2 = sprite.cell_to_world(cell)
	var color: Color = sprite.get_cell_color(cell)

	if randf() < chance:
		burn_radius(sprite, cell, 1, 255, 160, 1.0, randi_range(1, 2), 0.5, true)
	else:
		burn_radius(sprite, cell, 1, 110, 90, 0.0, 0, 0.5, false)

	world.spawn_cell_particle(cell_position, Vector2.from_angle(randf() * TAU) * RegolithWorld.pixels_per_unit(), color, sprite.global_rotation)
	return true

# sprite_burn_radius: the center burns whole, each neighbour within radius
# burns with spread_odds, weaker with distance, and is removed when the
# damage ratio rolls. a class zero cell only goes when spread_removes
static func burn_radius(sprite: RegolithSprite, center: Vector2i, radius: int, strength: int, scorch_strength: int, damage_ratio: float, damage: int, spread_odds: float, spread_removes: bool) -> void:
	sprite.burn_cell(center, strength, damage)

	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if (x == 0 and y == 0) or randf() >= spread_odds:
				continue

			var cell := center + Vector2i(x, y)

			if not sprite.has_cell(cell):
				continue

			var distance := maxi(absi(x), absi(y))
			var falloff := 1.0 - float(distance) / float(radius + 1)
			var damaged := randf() < damage_ratio * falloff

			if damaged and not spread_removes and sprite.get_cell_class(cell) == 0:
				damaged = false

			var cell_strength := int((strength if damaged else scorch_strength) * falloff)
			sprite.burn_cell(cell, cell_strength, damage if damaged else 0)

# bolt_arc_nearby: every projectile of someone else within the radius with
# a clear line gets a bolt and is shoved off its heading, losing whatever
# it was homing on. items in the radius get a bolt one time in ten. returns
# the projectiles arced at
static func arc_nearby(world: RegolithWorld, effect: Lightning, arc_props: LightningProps, origin: Vector2, radius_pixels: float, exclude: RegolithSprite, delta: float) -> Array[Node2D]:
	var out: Array[Node2D] = []

	for projectile in Targeting.projectiles_near(origin, radius_pixels, exclude):
		var offset := projectile.global_position - origin
		var length := offset.length()

		if length < 0.001 or not world.has_line_of_sight(origin, projectile.global_position, exclude):
			continue

		effect.strike(origin, projectile.global_position, exclude, arc_props)

		var away := offset / length
		var velocity_var: Variant = projectile.get("velocity")

		if velocity_var is Vector2:
			var velocity: Vector2 = velocity_var
			var speed := velocity.length()
			var heading := (velocity + away * BOLT_BULLET_TURN * delta).normalized()
			var pushed := heading * speed + away * BOLT_BULLET_PUSH * delta
			projectile.set("velocity", pushed)

			if "angle" in projectile:
				projectile.set("angle", pushed.angle())

		if "target_sprite" in projectile:
			projectile.set("target_sprite", null)

		if "target" in projectile:
			projectile.set("target", null)

		out.append(projectile)

	for item in effect.get_tree().get_nodes_in_group("item"):
		var node := item as Node2D

		if node == null or node.global_position.distance_to(origin) > radius_pixels or randf() >= BOLT_ITEM_ZAP_ODDS:
			continue

		if not world.has_line_of_sight(origin, node.global_position, exclude):
			continue

		effect.strike(origin, node.global_position, exclude, arc_props)

	return out
