extends Node2D
class_name PlayerShield

# port of ShieldSystem and the shield half of SpecialAbilitySystem: while
# the special action is held an arc of radius units around the player's
# center of mass shoves every sprite inside it back out along the arc,
# harder the deeper and the longer it sits there, and bends enemy bullets
# away with the acceleration that would stop them within max_penetration.
# strikes_per_second bolts play along the shell and out to what is caught.
# child of the player sprite, positions in world pixels, forces in units

@export var props: ShieldProps
# held by the player each frame, or driven by hand
@export var active := false
# read the special input action when the player owns this node
@export var use_input := true

var player: RegolithSprite
var lightning: Lightning
var strike_accumulator := 0.0
# instance id -> {"time": seconds inside, "accel": bullet capture}
var pushes := {}

signal pushed(sprite: RegolithSprite)
signal deflected(bullet: Node2D)

func _ready() -> void:
	player = get_parent() as RegolithSprite

	if props == null:
		props = ShieldProps.new()

	if props.lightning != null:
		lightning = Lightning.attach(self, props.lightning, props.lightning_material)

	add_to_group("player_shield")

func _process(_delta: float) -> void:
	if use_input and player != null and InputMap.has_action(Controls.SPECIAL):
		var cloud = player.get("cloud")
		var is_cloud: bool = cloud != null and cloud.is_cloud
		active = Input.is_action_pressed(Controls.SPECIAL) and not is_cloud

func center() -> Vector2:
	if player != null and player.is_loaded():
		return player.get_center_of_mass() + props.local_center.rotated(player.global_rotation) * RegolithWorld.pixels_per_unit()

	return global_position

static func wrap_positive(a: float) -> float:
	return fposmod(a, TAU)

static func angle_in_arc(local_angle: float, arc_min: float, arc_max: float) -> bool:
	return wrap_positive(local_angle - arc_min) <= arc_max - arc_min

static func clamp_to_arc(local_angle: float, arc_min: float, arc_max: float) -> float:
	var span := arc_max - arc_min
	var a := wrap_positive(local_angle - arc_min)

	if a <= span:
		return arc_min + a

	var over := a - span
	var under := TAU - a
	return arc_max if over < under else arc_min

static func capture_accel(velocity: Vector2, normal: Vector2, max_penetration: float) -> float:
	var v_in := maxf(-velocity.dot(normal), 0.0)
	return v_in * v_in / (2.0 * max_penetration)

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return

	if not active:
		strike_accumulator = 0.0
		pushes.clear()
		return

	var world := RegolithWorld.active()

	if world == null:
		return

	var ppu := RegolithWorld.pixels_per_unit()
	var center_px := center()
	var owner_angle := player.global_rotation
	var reach := (props.radius + props.buffer_distance) * ppu
	var inside := {}
	var targets: Array = []

	for other in world.query_rect(Rect2(center_px - Vector2.ONE * reach, Vector2.ONE * 2.0 * reach)):
		if other == player or not other is RegolithSprite:
			continue

		var sprite: RegolithSprite = other
		var com: Vector2 = sprite.get_center_of_mass()
		var to_other := (com - center_px) / ppu
		var d := to_other.length()

		if d > props.radius + props.buffer_distance or d < 0.001:
			continue

		var normal := to_other / d
		var local_angle := to_other.angle() - owner_angle
		var in_arc := angle_in_arc(local_angle, props.arc_min, props.arc_max)
		var id := sprite.get_instance_id()

		if not pushes.has(id):
			if not in_arc or d > props.radius:
				continue

			pushes[id] = {"time": 0.0}

		if d <= props.radius and sprite.is_dynamic():
			var arc_angle := clamp_to_arc(local_angle, props.arc_min, props.arc_max)
			var push_dir := Vector2.from_angle(owner_angle + arc_angle)
			var depth := props.radius - d
			var depth_t := minf(depth / props.max_rock_penetration, 1.0)
			var force: float = props.rock_force * depth_t * (1.0 + pushes[id]["time"])
			sprite.apply_impulse(push_dir * force * delta, com)
			pushes[id]["time"] += delta

			var core := maxf(props.radius - props.max_rock_penetration, 0.0)

			if d < core:
				# the original moved the body out of the core, a dynamic sprite
				# here only takes velocity, so it gets the way out over one step
				var velocity: Vector2 = sprite.linear_velocity
				var v_dot_n := velocity.dot(normal)

				if v_dot_n < 0.0:
					velocity -= normal * v_dot_n

				sprite.linear_velocity = velocity + normal * (core - d) / delta
			pushed.emit(sprite)

		inside[id] = true
		targets.append({"sprite": sprite, "cell": sprite.world_to_cell(com)})

	for node in get_tree().get_nodes_in_group("projectile"):
		var bullet := node as Node2D

		if bullet == null or bullet.get("shooter") == player or bullet.get("dead") == true:
			continue

		# lightning bolts fly by angle, not velocity: nothing to deflect
		var velocity_var: Variant = bullet.get("velocity")

		if not velocity_var is Vector2:
			continue

		var velocity: Vector2 = velocity_var
		var to_bullet := (bullet.global_position - center_px) / ppu
		var d := to_bullet.length()

		if d > props.radius + props.buffer_distance or d < 0.001:
			continue

		var normal := to_bullet / d
		var id := bullet.get_instance_id()

		if not pushes.has(id):
			if d > props.radius:
				continue

			pushes[id] = {"accel": capture_accel(velocity, normal, props.max_penetration)}

		if d <= props.radius:
			bullet.set("velocity", velocity + normal * pushes[id]["accel"] * delta)
			deflected.emit(bullet)

		inside[id] = true
		targets.append(bullet)

	for id in pushes.keys():
		if not inside.has(id):
			pushes.erase(id)

	strike_shell(center_px, owner_angle, targets, delta, ppu)

func strike_shell(center_px: Vector2, owner_angle: float, targets: Array, delta: float, ppu: float) -> void:
	if lightning == null or props.lightning == null:
		return

	strike_accumulator += props.strikes_per_second * delta
	var radius_px := props.radius * ppu

	while strike_accumulator >= 1.0:
		strike_accumulator -= 1.0

		var local_angle := props.arc_min + (props.arc_max - props.arc_min) * randf()
		var center_angle := owner_angle + local_angle
		var seg_arc := randf_range(props.segment_arc_min, props.segment_arc_max)
		var half_arc := seg_arc * 0.5
		var dir := 1.0 if randf() < 0.5 else -1.0
		var begin_angle := center_angle + half_arc * dir
		var end_angle := center_angle - half_arc * dir
		var bias_tan := 2.0 * tan(half_arc * 0.5)

		var shell: LightningProps = props.lightning.duplicate()
		shell.bias_angle_min = dir * atan(bias_tan)
		shell.bias_angle_max = shell.bias_angle_min
		shell.start_angle_min = dir * atan(tan(half_arc) - bias_tan)
		shell.start_angle_max = shell.start_angle_min

		lightning.strike(center_px + Vector2.from_angle(begin_angle) * radius_px, center_px + Vector2.from_angle(end_angle) * radius_px, player, shell)

		if targets.is_empty():
			continue

		var target = targets[randi() % targets.size()]
		var target_position: Vector2 = target["sprite"].get_center_of_mass() if target is Dictionary else target.global_position
		var target_angle := (target_position - center_px).angle() - owner_angle
		var arc_angle := clamp_to_arc(target_angle, props.arc_min, props.arc_max)
		var arc_point := center_px + Vector2.from_angle(owner_angle + arc_angle) * radius_px

		lightning.strike(arc_point, target, player)
