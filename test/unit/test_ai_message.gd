extends GutTest

# the courier sprite: its box sits on the node origin (blank art loads at the
# padded grid corner, the box is filled around the grid center), its streak
# is a Trail line keyed off the box center with no particle tail, and the
# streak lingers on its own once the courier is gone

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const MESSAGE_SCENE := preload("res://game/scenes/ai/AiMessage.tscn")

class Probe:
	extends Node2D
	var inbox: Array = []
	func receive(message: Dictionary) -> void:
		inbox.append(message)

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)
	spawner = StableSpawner.new()
	spawner.message_scene = MESSAGE_SCENE
	arena.add_child(spawner)
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func send_courier(from: Vector2, to: Vector2) -> Dictionary:
	var a := Probe.new()
	var b := Probe.new()
	a.position = from
	b.position = to
	arena.add_child(a)
	arena.add_child(b)

	var request := Ai.send(a, b, {"kind": "hello"})
	var out := {"sender": a, "target": b}
	request.spawned.connect(func(node): out["courier"] = node)

	for i in 30:
		await wait_physics_frames(1)
		if out.has("courier") and out["courier"].get_active_cell_count() > 0:
			break

	return out

func trails_in(node: Node) -> Array:
	var found := []
	for child in node.get_children():
		if child is Trail:
			found.append(child)
	return found

func test_box_is_centered_on_the_origin() -> void:
	var sent := await send_courier(Vector2.ZERO, Vector2(8, 0) * ppu())
	assert_true(sent.has("courier"), "a courier spawned")
	if not sent.has("courier"):
		return

	var courier: AiMessage = sent["courier"]
	var cell := RegolithWorld.pixels_per_cell()
	assert_eq(courier.get_active_cell_count(), courier.size_cells * courier.size_cells, "a full box")

	var grid := courier.get_cell_count()
	var middle := Vector2(grid) * 0.5
	var box_middle := Vector2(courier.box.position) + Vector2(courier.box.size) * 0.5
	assert_lt(middle.distance_to(box_middle), 1.0, "box fills the middle of the padded grid, not its corner")

	# the box center and the body's center of mass both sit on the node origin
	assert_lt(courier.box_center().distance_to(courier.global_position), cell, "box center on the origin")
	assert_lt(courier.get_center_of_mass().distance_to(courier.global_position), cell, "center of mass on the origin")

	# every filled cell is within the box radius of the origin
	for y in grid.y:
		for x in grid.x:
			if courier.has_cell(Vector2i(x, y)):
				var at := courier.cell_to_world(Vector2i(x, y))
				assert_lt(at.distance_to(courier.global_position), courier.size_cells * cell, "cell %s near the origin" % Vector2i(x, y))

func test_streak_is_a_trail_line_from_the_box() -> void:
	var sent := await send_courier(Vector2.ZERO, Vector2(10, 0) * ppu())
	assert_true(sent.has("courier"), "a courier spawned")
	if not sent.has("courier"):
		return

	var courier: AiMessage = sent["courier"]
	await wait_physics_frames(20)
	if not is_instance_valid(courier):
		return

	var particles := courier.find_children("*", "GPUParticles2D", true, false)
	assert_eq(particles.size(), 0, "no particle tail")

	var trail := courier.trail
	assert_not_null(trail, "a trail line")
	if trail == null:
		return

	assert_true(trail.top_level, "trail points are world pixels")
	assert_eq(trail.width, RegolithWorld.pixels_per_cell() * 0.5, "a cell wide streak drawn at half, like the bullets since the sparks pass")
	assert_true(trail.material is CanvasItemMaterial and trail.material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "additive streak")
	assert_eq(trail.gradient.get_color(1), Trail.tonemapped(courier.color), "full color at the tip, through the trail tonemap")
	assert_almost_eq(trail.gradient.get_color(0).a, 0.0, 0.001, "fades to nothing at the back")
	assert_gt(trail.points.size(), 2, "the streak has grown behind the box")

	var cell := RegolithWorld.pixels_per_cell()
	var center := courier.box_center()
	assert_lt(trail.tip().distance_to(center), cell * 2.0, "tip rides the box center")
	var step := courier.speed * RegolithWorld.pixels_per_unit() / Engine.physics_ticks_per_second
	assert_lt(trail.tip().distance_to(courier.global_position), cell * 2.0 + step, "no offset between streak and box beyond one interpolated step")

	var span := courier.trail_length * ppu()
	for point in trail.points:
		assert_lt(point.distance_to(center), span + cell * 2.0, "streak stays within its length of the box")

	# the streak trails on the sender's side
	var behind: Vector2 = trail.points[0] - center
	assert_lt(behind.x, 0.0, "back of the streak lies behind the flight direction")

func test_streak_lingers_after_delivery_then_goes() -> void:
	var sent := await send_courier(Vector2.ZERO, Vector2(4, 0) * ppu())
	assert_true(sent.has("courier"), "a courier spawned")
	if not sent.has("courier"):
		return

	var courier: AiMessage = sent["courier"]
	var target: Probe = sent["target"]

	for i in 240:
		await wait_physics_frames(1)
		if not target.inbox.is_empty():
			break

	assert_eq(target.inbox.size(), 1, "the message landed")
	await wait_physics_frames(2)
	assert_false(is_instance_valid(courier), "courier gone after delivery")
	assert_eq(trails_in(arena).size(), 1, "the streak was handed to the arena to fade")

	await wait_seconds(1.0)
	assert_eq(trails_in(arena).size(), 0, "streak faded out and freed itself")
