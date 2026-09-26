@tool
class_name EnemyThrower
extends Node

# the hold-and-throw mechanics of AiThrower: a ring of slots along an arc
# in front of a host, things grabbed near its origin get pulled to the
# slots, a thing told to throw swings around the ring and is let go toward
# the target. what to grab and when to throw is the host's script's call:
# base.lua and boss_compass.lua drive it with find_throwables/grab/throw
# and run step each physics step for the pull. a child of a base or a
# boss. sim units

enum ThrowBias { LEFT, RIGHT, BOTH }
enum ArcSpace { FACE_PLAYER, LOCAL }

signal threw(node: RegolithSprite)
signal grabbed(node: RegolithSprite)

@export var origin := Vector2.ZERO
@export var radius_min := 2.5
@export var radius_max := 3.5
@export var only_throw_at_radius := 18.0
@export var hold_arc_min := 0.0
@export var hold_arc_max := 1.25
@export var arc_space: ArcSpace = ArcSpace.FACE_PLAYER
@export var bias: ThrowBias = ThrowBias.LEFT
@export var max_holding := 5
@export var max_cells := 200
@export var hold_time := 3.0
@export var throw_time := 1.0
@export var pull := 30.0

class Held:
	var node: RegolithSprite
	var goal: Vector2
	# seconds swinging once told to throw
	var timer := 0.0
	var throwing := false

	func _init(held_node: RegolithSprite, held_goal: Vector2) -> void:
		node = held_node
		goal = held_goal

var active := true
var host: Enemy
var holding := {}

var center := Vector2.ZERO
var arc_base := 0.0
# where thrown things go, the player as last given to step
var target := Vector2.ZERO

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	host = get_parent() as Enemy

func can_hold_more() -> bool:
	return active and holding.size() < max_holding

func is_holding(node: Node) -> bool:
	return node != null and holding.has(node.get_instance_id())

func is_throwing(node: Node) -> bool:
	return is_holding(node) and holding[node.get_instance_id()].throwing

func count() -> int:
	return holding.size()

# the nodes held right now, the ones swinging included
func held() -> Array:
	var out := []

	for held_entry in holding.values():
		out.append(held_entry.node)

	return out

func center_units() -> Vector2:
	if host == null:
		host = get_parent() as Enemy
	return host.local_point_units(origin) if host else Vector2.ZERO

func arc_base_angle(player_pos: Vector2) -> float:
	if arc_space == ArcSpace.LOCAL:
		return host.global_rotation

	return (center - player_pos).angle()

# the middle of the ring, where a bomb heads to be picked up
func ring_goal(player_pos: Vector2) -> Vector2:
	var angle := arc_base_angle(player_pos) + lerpf(hold_arc_min, hold_arc_max, 0.5)
	return center + Vector2.from_angle(angle) * lerpf(radius_min, radius_max, 0.5)

# the mechanics of one physics step: drops what is gone, lets everything go
# when inactive, faces the arc at the target, assigns slots, pulls the held
# to them and swings the throwing ones out, letting go when the swing is done
func step(delta: float, target_pos: Vector2) -> void:
	prune()

	if not active:
		release_all()
		return

	center = center_units()
	target = target_pos
	arc_base = arc_base_angle(target_pos)
	calc_goal_positions()

	for id in holding.keys():
		var held_entry: Held = holding[id]

		if held_entry.throwing:
			if throw_thing_at_target(held_entry, delta):
				holding.erase(id)
				finish_throw(held_entry.node)
		else:
			hold_thing_in_reserve(held_entry, delta)

func prune() -> void:
	for id in holding.keys():
		var node: RegolithSprite = holding[id].node

		if not is_instance_valid(node) or node.is_queued_for_deletion():
			holding.erase(id)

func is_throwable(sprite: Node) -> bool:
	if sprite == host or not sprite is RegolithSprite or not sprite.is_dynamic():
		return false

	var throwable := Throwable.of(sprite)
	if throwable == null or throwable.thrown or throwable.held_by != null:
		return false

	if sprite is EnemyBomb and sprite.exploding:
		return false

	return sprite.get_active_cell_count() <= max_cells

# the throwable sprites within radius_max of the origin not held yet
func find_throwables() -> Array:
	var world := RegolithWorld.active()
	var out := []

	if world == null or host == null:
		return out

	center = center_units()

	for sprite in Steering.sprites_near(world, center, radius_max):
		if is_holding(sprite) or not is_throwable(sprite):
			continue

		if (sprite.global_position / Steering.ppu()).distance_to(center) > radius_max:
			continue

		out.append(sprite)

	return out

# takes hold of a sprite, false when it cannot be held
func grab(node: Node) -> bool:
	if not can_hold_more() or is_holding(node) or not is_throwable(node):
		return false

	Throwable.of(node).held_by = host
	holding[node.get_instance_id()] = Held.new(node, center)
	grabbed.emit(node)
	return true

# starts the swing of a held thing, it is let go at the target by step
func throw(node: Node) -> bool:
	if not is_holding(node):
		return false

	var held_entry: Held = holding[node.get_instance_id()]

	if held_entry.throwing:
		return false

	held_entry.throwing = true
	held_entry.timer = 0.0
	return true

# lets go of a held thing without throwing it
func release(node: Node) -> void:
	if node == null:
		return

	holding.erase(node.get_instance_id())
	var throwable := Throwable.of(node)

	if throwable and throwable.held_by == host:
		throwable.held_by = null

func release_all() -> void:
	for held_entry in holding.values():
		release(held_entry.node)

	holding.clear()

func finish_throw(node: RegolithSprite) -> void:
	var throwable := Throwable.of(node)
	throwable.thrown = true
	throwable.held_by = null

	# a thrown bomb fuses to burst about when it reaches the target
	if node is EnemyBomb:
		var distance: float = target.distance_to(node.global_position / Steering.ppu())
		var speed: float = node.linear_velocity.length()
		node.start_fuse(minf(distance / maxf(speed, 0.001), 4.0))

	threw.emit(node)

func calc_goal_positions() -> void:
	var held_list: Array = holding.values()
	var count_held := held_list.size()
	var arc_start := arc_base + hold_arc_min
	var delta_theta := (hold_arc_max - hold_arc_min) / (count_held + 1)
	var goals: Array = []

	for i in count_held:
		var t := float(i) / (count_held - 1) if count_held > 1 else 0.0
		var radius := lerpf(radius_min, radius_max, t)

		if held_list[i].throwing:
			radius += 1.0

		goals.append(center + Vector2.from_angle(arc_start + delta_theta * (i + 1)) * radius)

	for held_entry in held_list:
		var held_pos: Vector2 = held_entry.node.global_position / Steering.ppu()
		var best := 0
		var best_distance: float = held_pos.distance_to(goals[0])

		for j in range(1, goals.size()):
			var d: float = held_pos.distance_to(goals[j])

			if d < best_distance:
				best_distance = d
				best = j

		held_entry.goal = goals[best]
		goals[best] = goals.back()
		goals.pop_back()

func hold_thing_in_reserve(held_entry: Held, delta: float) -> void:
	var node := held_entry.node
	var held_pos: Vector2 = node.global_position / Steering.ppu()
	var correction := orbit_steer(held_pos, held_entry.goal)
	node.linear_velocity = Steering.dampen(node.linear_velocity + correction * delta * pull, 20.0, delta)

# swings the thing around the ring until it is on the target's side, then
# drives it at the target and lets go after throw_time or within two units
func throw_thing_at_target(held_entry: Held, delta: float) -> bool:
	var node := held_entry.node
	var held_pos: Vector2 = node.global_position / Steering.ppu()
	var target_goal := target
	var thrower_to_goal := center - target
	var thrower_to_held := center - held_pos
	var damping := 1.0

	if thrower_to_goal.dot(thrower_to_held) < 0.0:
		target_goal = center + around_direction(target - held_pos, thrower_to_held)
		damping = 6.0
	else:
		held_entry.timer += delta

		if held_entry.timer >= throw_time:
			return true

		if target.distance_to(held_pos) < 2.0:
			return true

	var correction := (target_goal - held_pos).normalized()
	node.linear_velocity = Steering.dampen(node.linear_velocity + correction * delta * pull, damping, delta)
	return false

func around_direction(held_to_goal: Vector2, thrower_to_held: Vector2) -> Vector2:
	var perp := Vector2(-held_to_goal.y, held_to_goal.x).normalized()
	var swing_left: bool
	match bias:
		ThrowBias.LEFT:
			swing_left = true
		ThrowBias.RIGHT:
			swing_left = false
		_:
			swing_left = perp.dot(thrower_to_held) >= 0.0
	return (perp if swing_left else -perp) * radius_max

func draw_gizmos(g: RegolithGizmos) -> void:
	var host_now := host if host else get_parent() as Enemy
	if host_now == null:
		return

	# everything is computed in world sim units; Steering.gz_* lift each
	# emitted point to host-local scene pixels via to_local * (p * ppu),
	# and the walker's host.global_transform puts it back at world position
	var color := Color(1.0, 0.55, 0.15)
	var name := RegolithDebugDraw.AI_THROWER
	var ppu := Steering.ppu()
	var to_local := host_now.global_transform.affine_inverse()
	# inline of Enemy.local_point_units — Enemy.gd is not @tool so calling
	# its gdscript methods on a placeholder at editor time errors. use only
	# c++ methods on RegolithSprite/Node2D, which work on placeholders. at
	# edit time is_loaded() is false (no active world), so fall back to the
	# texture size — "cells are the pixels of the texture" (RegolithSprite.h)
	var cells: Vector2i = host_now.get_cell_count()
	if cells == Vector2i.ZERO:
		var tex: Texture2D = host_now.get_texture()
		if tex != null:
			cells = Vector2i(tex.get_size())
	var center_now := host_now.to_global(Vector2(origin.x, -origin.y) * Vector2(cells) * 0.5 * Steering.cell_pixels()) / ppu
	var a0 := arc_base + hold_arc_min
	var a1 := arc_base + hold_arc_max

	Steering.gz_cross(g, to_local, ppu, center_now, 0.25, color, name)
	Steering.gz_arc(g, to_local, ppu, center_now, radius_min, a0, a1, color, name)
	Steering.gz_arc(g, to_local, ppu, center_now, radius_max, a0, a1, color, name)
	Steering.gz_line(g, to_local, ppu, center_now + Vector2.from_angle(a0) * radius_min, center_now + Vector2.from_angle(a0) * radius_max, color, name)
	Steering.gz_line(g, to_local, ppu, center_now + Vector2.from_angle(a1) * radius_min, center_now + Vector2.from_angle(a1) * radius_max, color, name)
	Steering.gz_circle(g, to_local, ppu, center_now, only_throw_at_radius, color, name)

	for held_entry in holding.values():
		if is_instance_valid(held_entry.node):
			Steering.gz_line(g, to_local, ppu, held_entry.node.global_position / ppu, held_entry.goal, color, name)

func orbit_steer(held_pos: Vector2, target_goal: Vector2) -> Vector2:
	var to_pos := held_pos - center
	var r := to_pos.length()

	if r < 0.0001:
		to_pos = Vector2.from_angle(arc_base)
		r = 0.0001

	var arc_lo := arc_base + hold_arc_min
	var arc_hi := arc_base + hold_arc_max
	var theta := Steering.wrap_from(to_pos.angle(), arc_lo)
	var goal_theta := clampf(Steering.wrap_from((target_goal - center).angle(), arc_lo), arc_lo, arc_hi)
	var target_theta: float

	if theta <= arc_hi:
		target_theta = goal_theta
	else:
		match bias:
			ThrowBias.RIGHT:
				target_theta = arc_hi
			ThrowBias.LEFT:
				target_theta = arc_lo + TAU
			_:
				var to_hi := theta - arc_hi
				var to_lo := (arc_lo + TAU) - theta
				target_theta = arc_hi if to_hi <= to_lo else arc_lo + TAU

	var step_angle := clampf(target_theta - theta, -0.6, 0.6)
	var r_goal := clampf((target_goal - center).length(), radius_min, radius_max)
	var r_now := clampf(r, radius_min, radius_max)
	var r_target := clampf(lerpf(r_now, r_goal, 0.25), radius_min, radius_max)

	return center + Vector2.from_angle(theta + step_angle) * r_target - held_pos
