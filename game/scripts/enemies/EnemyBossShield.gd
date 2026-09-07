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
	if local_points.is_empty():
		build_local_points(host)

	return host.global_transform.scaled(Vector2.ONE / Steering.ppu()) * local_points

func world_centroid(host: Enemy) -> Vector2:
	if local_points.is_empty():
		build_local_points(host)

	return host.global_transform.scaled(Vector2.ONE / Steering.ppu()) * local_centroid

# where rocks are driven to for a threat at point, world units
func slot_point(host: Enemy, point: Vector2) -> Vector2:
	return Steering.closest_point_on_polygon(world_points(host), point)

func build_local_points(host: Enemy) -> void:
	local_points = hull_local(self, host)
	local_centroid = centroid_of(local_points)

# geometry from the exports alone, for the editor gizmo. shield is untyped
# on purpose, in the editor it is a placeholder that only answers property gets
static func hull_local(shield: Node, on: RegolithSprite) -> PackedVector2Array:
	var half := Steering.cell_count(on) * 0.5 * Steering.cell_pixels()
	var out := PackedVector2Array()

	for p in shield.points:
		out.append(Vector2(p.x, -p.y) * half)

	return out

static func hull_world(shield: Node, on: RegolithSprite) -> PackedVector2Array:
	return on.global_transform.scaled(Vector2.ONE / Steering.ppu()) * hull_local(shield, on)

static func centroid_of(hull: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO

	for p in hull:
		sum += p

	return sum / hull.size() if hull.size() > 0 else Vector2.ZERO

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
