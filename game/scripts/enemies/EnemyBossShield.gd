@tool
class_name EnemyBossShield
extends Node

# AiRockShield: gathers loose rocks near the hull and drives them to the
# point of a hull polygon closest to the player, a shield of rubble. the
# host calls update each physics step. points are in the original's -1..1
# local space

const CAPTURE_INTERVAL := 0.2

@export var active := true
@export var points: PackedVector2Array
@export var min_rock_cells := 25
@export var max_rock_cells := 1024
@export var max_holding := 8
@export var capture_radius := 10.0
@export var arrive_radius := 1.0
@export var max_speed := 3.0
@export var max_accel := 7.0
@export var stiffness := 2.5
@export var held_angular_damping := 4.0

var holding: Array = []
var capture_timer := 0.0

var local_points := PackedVector2Array()
var local_centroid := Vector2.ZERO

func update(host: Enemy, delta: float) -> void:
	if not active:
		holding.clear()
		return

	if points.size() < 3:
		return

	Steering.prune_dead(holding)

	var want_more := holding.size() < max_holding

	if not want_more and holding.is_empty():
		return

	if want_more:
		capture_timer -= delta

		if capture_timer <= 0.0:
			capture_timer = CAPTURE_INTERVAL
			capture(host, world_centroid(host))

	if holding.is_empty() or host.player == null:
		return

	var target := slot_point(host, host.player_pos)
	var scale := Steering.ppu()

	for rock in holding:
		var rock_pos: Vector2 = rock.global_position / scale
		var to_slot := target - rock_pos
		var distance := to_slot.length()
		var speed := max_speed * (distance / arrive_radius) if distance < arrive_radius else max_speed
		var desired := to_slot.normalized() * speed
		var steering: Vector2 = ((desired - rock.linear_velocity) * stiffness).limit_length(max_accel)

		rock.linear_velocity += steering * delta
		rock.angular_velocity *= 1.0 / (1.0 + delta * held_angular_damping)

# the hull polygon and its centroid in world units, built on first use
func world_points(host: Enemy) -> PackedVector2Array:
	build_local_points(host)

	return host.global_transform.scaled(Vector2.ONE / Steering.ppu()) * local_points

func world_centroid(host: Enemy) -> Vector2:
	build_local_points(host)

	return host.global_transform.scaled(Vector2.ONE / Steering.ppu()) * local_centroid

# where rocks are driven to for a threat at point, world units
func slot_point(host: Enemy, point: Vector2) -> Vector2:
	return Steering.closest_point_on_polygon(world_points(host), point)

func build_local_points(host: Enemy) -> void:
	local_points.clear()
	local_centroid = Vector2.ZERO
	if not host.is_loaded():
		return

	var half := Vector2(host.get_cell_count()) * 0.5 * Steering.cell_pixels()
	for p in points:
		var local := Vector2(p.x, -p.y) * half
		local_points.append(local)
		local_centroid += local

	local_centroid /= points.size()

func capture(host: Enemy, centroid: Vector2) -> void:
	var world := RegolithWorld.active()

	if world == null:
		return

	var scale := Steering.ppu()

	for sprite in Steering.sprites_near(world, centroid, capture_radius):
		if holding.size() >= max_holding:
			break

		if sprite in holding or not is_rock(sprite, host):
			continue

		var cells: int = sprite.get_active_cell_count()

		if cells < min_rock_cells or cells > max_rock_cells:
			continue

		if (sprite.global_position / scale).distance_to(centroid) > capture_radius:
			continue

		holding.append(sprite)

func push_rocks(away_from: Vector2, speed: float) -> void:
	Steering.prune_dead(holding)

	for rock in holding:
		var away: Vector2 = (rock.global_position / Steering.ppu() - away_from).normalized()
		rock.linear_velocity = away * speed

	holding.clear()

static func is_rock(sprite: Node, host: Enemy) -> bool:
	if not sprite is RegolithSprite or sprite == host or not sprite.is_dynamic():
		return false

	return not sprite is Enemy and sprite != host.player

# emits in host-local pixels; the walker sets g.transform to the host's
# global_transform, so everything lifts to scene pixels at push time
func draw_gizmos(g: RegolithGizmos) -> void:
	var host := get_parent() as Enemy
	if host == null or points.size() < 3:
		return

	build_local_points(host)
	if local_points.is_empty():
		return

	var color := Color(0.24, 0.86, 1.0)
	var name := RegolithDebugDraw.AI_SHIELD
	var ppu := Steering.ppu()

	g.polygon(local_points, color, name)
	g.cross(local_centroid, 0.25 * ppu, color, name)
	g.circle(local_centroid, capture_radius * ppu, color, name)

	if not Engine.is_editor_hint() and host.player != null:
		var to_local := host.global_transform.affine_inverse()
		var slot_local := to_local * (slot_point(host, host.player_pos) * ppu)
		g.cross(slot_local, 0.5 * ppu, color, name)
		for rock in holding:
			if is_instance_valid(rock):
				g.line(to_local * rock.global_position, slot_local, color, name)
