extends Node2D
class_name Item

# a pickup drifting through the world: not a sprite, nothing collides with
# it. port of the ItemEntity and ItemMoveSystem of the original. it drifts
# and spins with damping until its life runs out; once the pickup delay has
# passed the player (any node in group player with collect_item) within the
# props radius pulls it in: it is thrown outward first, then steered so it
# lands on the player's center of mass, velocity included, exactly
# collect_time later, when the player collects it. a cloud only pulls cores
# and its death timer waits while one flies. spawned by the Items autoload
# from a SpawnRequest of Kind.ITEM. state is sim units, the node sits in
# world pixels, velocities move in _physics_process

var props: ItemProps
# units
var pos := Vector2.ZERO
# units per second
var velocity := Vector2.ZERO
var angular_velocity := 0.0
var damping := 0.0
var life := 0.0
var pickup_delay := 0.0
var spin_angle := 0.0

# the sink pulling the item in, null while loose
var collecting: Node2D
var collect_elapsed := 0.0
var done := false

var visual: Sprite2D

signal collected(sink: Node2D)
signal expired

func setup(item_props: ItemProps, at: Vector2, with_velocity := Vector2.ZERO) -> void:
	props = item_props
	pos = at
	velocity = with_velocity
	angular_velocity = randf_range(-props.spin, props.spin)
	damping = randf_range(props.damping_min, props.damping_max)
	life = props.life
	pickup_delay = props.pickup_delay

	if props.speed_max > 0.0 and velocity.length_squared() > 0.0:
		velocity = velocity.normalized() * randf_range(props.speed_min, props.speed_max)

	global_position = pos * RegolithWorld.pixels_per_unit()

func _ready() -> void:
	add_to_group("item")

	for child in get_children():
		if child is Sprite2D:
			visual = child
			break

	if visual == null:
		visual = Sprite2D.new()
		visual.name = "Visual"
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(visual)

	if props != null:
		visual.texture = props.texture
		visual.modulate = props.tint

	visual.scale = Vector2.ONE * RegolithWorld.pixels_per_cell()

func is_collecting() -> bool:
	return collecting != null

func _physics_process(delta: float) -> void:
	if done or props == null:
		return

	if collecting != null:
		update_collecting(delta)
	else:
		update_loose(delta)

	if done:
		return

	global_position = pos * RegolithWorld.pixels_per_unit()
	rotation = spin_angle

func update_collecting(delta: float) -> void:
	if not sink_alive(collecting):
		release_sink()
		collecting = null
		collect_elapsed = 0.0
		return

	var remaining := maxf(props.collect_time - collect_elapsed, delta)
	var sink_position := sink_center(collecting)
	var sink_velocity := sink_velocity_of(collecting)
	var sink_future := sink_position + sink_velocity * remaining

	var acceleration := 2.0 * (sink_future - pos - velocity * remaining) / (remaining * remaining)
	velocity += acceleration * delta
	pos += velocity * delta
	spin_angle += angular_velocity * delta

	collect_elapsed += delta

	if collect_elapsed >= props.collect_time:
		pickup()

func update_loose(delta: float) -> void:
	life -= delta

	if life <= 0.0:
		finish()
		expired.emit()
		return

	pos += velocity * delta
	spin_angle += angular_velocity * delta

	velocity = Steering.dampen(velocity, damping, delta)
	angular_velocity *= clampf(1.0 - damping * delta, 0.0, 1.0)

	pickup_delay -= delta

	if pickup_delay > 0.0:
		return

	var sink := find_sink()

	if sink == null:
		return

	var to_item := pos - sink_center(sink)

	if to_item.length_squared() >= props.radius * props.radius:
		return

	start_collecting(sink, to_item)

func start_collecting(sink: Node2D, away: Vector2) -> void:
	collecting = sink
	collect_elapsed = 0.0
	velocity = away.normalized().rotated(randf()) * randf_range(4.0, 8.0)
	angular_velocity = randf()
	damping = 0.0

	if props.is_core():
		var cloud: Variant = sink.get("cloud")

		if cloud != null:
			cloud.collecting = true

func release_sink() -> void:
	if collecting == null or not is_instance_valid(collecting) or not props.is_core():
		return

	var cloud: Variant = collecting.get("cloud")

	if cloud != null:
		cloud.collecting = false

func pickup() -> void:
	var sink := collecting
	release_sink()
	finish()

	if sink_alive(sink):
		sink.collect_item(props)

	collected.emit(sink)

func finish() -> void:
	done = true
	queue_free()

# the player, the only sink: the first node in group player that collects,
# pieces split off the hull carry the group without the script. a cloud
# only takes cores
func find_sink() -> Node2D:
	for node in get_tree().get_nodes_in_group("player"):
		var sink := node as Node2D

		if sink == null or not sink.has_method("collect_item") or not sink_alive(sink):
			continue

		if not props.is_core() and sink.has_method("is_cloud") and sink.is_cloud():
			return null

		return sink

	return null

static func sink_alive(sink: Node2D) -> bool:
	return sink != null and is_instance_valid(sink) and sink.is_inside_tree() and not sink.is_queued_for_deletion()

# center of mass in units
static func sink_center(sink: Node2D) -> Vector2:
	var center: Vector2 = sink.get_center_of_mass() if sink.has_method("get_center_of_mass") else sink.global_position
	return center / RegolithWorld.pixels_per_unit()

static func sink_velocity_of(sink: Node2D) -> Vector2:
	var linear: Variant = sink.get("linear_velocity")
	return linear if linear is Vector2 else Vector2.ZERO
