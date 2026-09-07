extends Node2D
class_name SuperLaser

# a beam that lives while its weapon's trigger is held. the weapon aims it
# each physics step and drains its own charge, the beam casts along that
# aim and burns a budget of cells through whatever it reaches. the origin
# jitters sideways so the burn spreads to the beam's width. release() or
# losing the world fades it out

const MAX_SPRITES_PER_STEP := 4
const FADE_TIME := 0.15

var props: BeamWeaponProps
var shooter: RegolithSprite

var aim_origin := Vector2.ZERO
var aim_direction := Vector2.RIGHT
var beam_from := Vector2.ZERO
var beam_to := Vector2.ZERO
var burn_accumulator := 0.0
var particle_counter := 0
var cells_burned := 0
var fade := 1.0
var dead := false

var pixels_per_unit := 0.0
var cell_px := 0.0
var width_px := 0.0
var range_px := 0.0
var cells_per_second := 0.0

signal hit_cell(sprite: RegolithSprite, cell: Vector2i, position: Vector2)

func setup(weapon_props: WeaponProps, start: Vector2, direction: Vector2, _holder_velocity: Vector2, holder: RegolithSprite) -> void:
	props = weapon_props
	shooter = holder
	global_position = start
	pixels_per_unit = RegolithWorld.pixels_per_unit()
	cell_px = RegolithWorld.pixels_per_cell()
	width_px = props.width * pixels_per_unit
	range_px = props.range * pixels_per_unit
	cells_per_second = props.shots_per_ammo * props.cell_life / maxf(props.delay_cooldown, 0.001)
	aim(start, direction)
	beam_from = start
	beam_to = start + direction * range_px

func aim(origin: Vector2, direction: Vector2) -> void:
	aim_origin = origin
	aim_direction = direction

func release() -> void:
	dead = true

func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _draw() -> void:
	var outer := props.color_back
	outer.a = fade
	var inner := props.color_front
	inner.a *= fade
	var a := to_local(beam_from)
	var b := to_local(beam_to)
	draw_line(a, b, outer, width_px)
	draw_line(a, b, inner, width_px * 0.4)
	draw_line(a, b, Color(1.0, 1.0, 1.0, 0.9 * fade), cell_px)

func _process(delta: float) -> void:
	if not dead:
		return

	fade -= delta / FADE_TIME
	if fade <= 0.0:
		queue_free()
		return

	queue_redraw()

func _physics_process(delta: float) -> void:
	if dead:
		return

	if not is_instance_valid(shooter):
		shooter = null

	var world := RegolithWorld.active()
	if world == null:
		queue_free()
		return

	burn_accumulator += cells_per_second * delta

	var direction := aim_direction
	var tangent := Vector2(-direction.y, direction.x)
	var cursor := aim_origin + tangent * props.inaccuracy_tangent * randf_range(-0.5, 0.5) * pixels_per_unit
	var end := cursor + direction * range_px
	var budget := int(burn_accumulator)
	var last_hit := Vector2.INF

	for i in range(MAX_SPRITES_PER_STEP):
		if budget <= 0:
			break

		var hit: Dictionary = world.ray_cast(cursor, end, shooter)
		if hit.is_empty():
			break

		var sprite: RegolithSprite = hit["sprite"]
		var hit_position: Vector2 = hit["position"]

		if last_hit == Vector2.INF:
			last_hit = hit_position

		var cells: Array = sprite.trace_cells(hit_position, end, budget)
		if cells.is_empty():
			cells = [hit["cell"]]

		for c in cells:
			last_hit = burn(world, sprite, c, direction)
			budget -= 1

		cursor = last_hit + direction * cell_px * 0.51

	burn_accumulator -= int(burn_accumulator) - budget

	if last_hit != Vector2.INF:
		end = last_hit + direction * cell_px

	if aim_origin != beam_from or end != beam_to:
		beam_from = aim_origin
		beam_to = end
		global_position = aim_origin
		queue_redraw()

func burn(world: RegolithWorld, sprite: RegolithSprite, cell: Vector2i, direction: Vector2) -> Vector2:
	particle_counter += 1
	var particle_velocity := direction.rotated(randf_range(-1.0, 1.0)) * randf_range(1.0, 4.0) * pixels_per_unit
	var cell_position := Explosion.hit_cell(world, props, sprite, cell, particle_velocity, particle_counter % 3 == 0)
	cells_burned += 1
	hit_cell.emit(sprite, cell, cell_position)
	return cell_position
