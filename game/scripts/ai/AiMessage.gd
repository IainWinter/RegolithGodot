extends RegolithSprite
class_name AiMessage

# a courier: a message on its way as a tiny box with a streak behind it.
# it flies from the sender toward the target and hands over its payload on
# arrival. every weapon already only hits sprites, so it can be shot down
# like anything else, one lost cell and the message never lands. spawned
# through the SpawnBus as Kind.MESSAGE, Ai.send sets it up once placed.
#
# the node origin is the center of the chunk padded grid and blank art
# loads at the grid corner, so the box is filled around the grid center
# and everything (steering, arrival, the streak) keys off the box center

@export var speed := 8.0
# units from the target's origin that count as arrived
@export var arrive_radius := 0.75
# the engine drops any sprite under 20 cells at commit, so 5x5 is the floor
@export var size_cells := 5
@export var color := Color(1.0, 0.85, 0.3, 1.0)
# units of streak behind the box, one cell wide, fading to nothing at the back
@export var trail_length := 1.0
# seconds the streak lingers once the courier is gone
@export var trail_fade := 0.3
# seconds before a courier that never arrives gives up
@export var lifetime := 10.0

signal delivered(target: Object, payload: Dictionary)
signal intercepted(payload: Dictionary)

var sender: Object
var target: Object
var payload := {}
var age := 0.0
var done := false
# the filled cells inside the padded grid
var box := Rect2i()
var trail: Trail
var trail_px := 0.0
var tip_from := Vector2.ZERO
var tip_to := Vector2.ZERO

func _ready() -> void:
	add_to_group("regolith")
	add_to_group("ai_message")
	angle_fixed = true
	create_blank(Vector2i(size_cells, size_cells))

	var size := Vector2i(size_cells, size_cells)
	box = Rect2i((get_cell_count() - size) / 2, size)
	fill_rect(box, color, RegolithSprite.CELL_FILLED, 0)

	var world := RegolithWorld.active()

	if world:
		world.cells_removed.connect(on_cells_removed)

	trail_px = trail_length * RegolithWorld.pixels_per_unit()
	tip_from = box_center()
	tip_to = tip_from

	var look := WeaponProps.new()
	look.color_front = color
	look.color_back = Color(color, 0.0)

	trail = Trail.new()
	trail.setup(look, RegolithWorld.pixels_per_cell(), tip_to)
	# additive like the original's line passes, the streak glows over the rocks
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	trail.material = additive
	add_child(trail)

func setup(from: Object, to: Object, message: Dictionary) -> void:
	sender = from
	target = to
	payload = message

# world pixels of the middle of the filled box
func box_center() -> Vector2:
	if not is_loaded():
		return global_position

	return grid_point_to_world(Vector2(box.position) + Vector2(box.size) * 0.5)

func _process(_delta: float) -> void:
	if done or trail == null:
		return

	trail.set_tip(tip_from.lerp(tip_to, Engine.get_physics_interpolation_fraction()))
	trail.trim(trail_px)

func _physics_process(delta: float) -> void:
	if done or target == null:
		return

	age += delta

	if not target is Node2D or not Steering.alive(target) or age > lifetime:
		finish()
		return

	var center := box_center()
	var to: Vector2 = target.global_position - center
	var ppu := RegolithWorld.pixels_per_unit()

	if to.length() <= arrive_radius * ppu:
		deliver()
		return

	linear_velocity = to.normalized() * speed

	# the last point is the tip, _process slides it from tip_from to tip_to
	trail.set_tip(tip_to)
	tip_from = tip_to
	tip_to = center
	trail.push(tip_from)

func deliver() -> void:
	if done:
		return

	if target is Node and Steering.alive(target) and target.has_method("receive"):
		target.receive(payload)
		delivered.emit(target, payload)

	finish()

func on_cells_removed(sprite: RegolithSprite, _count: int) -> void:
	if sprite == self and not done:
		intercepted.emit(payload)
		finish()

# every remaining cell becomes a particle, the streak lingers a moment on
# its own, then the node goes
func finish() -> void:
	if done:
		return

	done = true

	if is_loaded():
		remove_all_cells()

	release_trail()
	queue_free()

func release_trail() -> void:
	if trail == null:
		return

	var streak := trail
	trail = null
	streak.set_tip(tip_to)
	var holder := get_parent()

	if holder == null or not is_inside_tree():
		streak.queue_free()
		return

	# top_level, so it keeps its world points across the reparent
	streak.reparent(holder)
	var fade := holder.create_tween()
	fade.tween_property(streak, "modulate:a", 0.0, trail_fade)
	fade.tween_callback(streak.queue_free)
