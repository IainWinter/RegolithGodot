@tool
class_name EnemyThrower
extends Node

# AiThrower: grabs throwable things near its origin, parks them along an arc
# in front of it, then flings them at the player. a child of a base or a
# boss, which calls update each physics step and hears threw. sim units

const FIND_INTERVAL := 0.2

enum ThrowBias { LEFT, RIGHT, BOTH }
enum ArcSpace { FACE_PLAYER, LOCAL }

signal threw(node: RegolithSprite)

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
var find_timer := 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	host = get_parent() as Enemy

func can_hold_more() -> bool:
	return active and holding.size() < max_holding

func is_holding(node: Node) -> bool:
	return holding.has(node.get_instance_id())

func center_units() -> Vector2:
	if host == null:
		host = get_parent() as Enemy
	return host.local_point_units(origin) if host else Vector2.ZERO

func arc_base_angle(player_pos: Vector2) -> float:
	if arc_space == ArcSpace.LOCAL:
		return host.global_rotation

	return (center - player_pos).angle()

func ring_goal(player_pos: Vector2) -> Vector2:
	var angle := arc_base_angle(player_pos) + lerpf(hold_arc_min, hold_arc_max, 0.5)
	return center + Vector2.from_angle(angle) * lerpf(radius_min, radius_max, 0.5)

func update(delta: float) -> void:
	for id in holding.keys():
		var node: RegolithSprite = holding[id].node

		if not is_instance_valid(node) or node.is_queued_for_deletion():
			holding.erase(id)

	if not active:
		for held in holding.values():
			release(held.node)

		holding.clear()
		return

	center = center_units()

	if host.player == null:
		return

	arc_base = arc_base_angle(host.player_pos)
	find_timer -= delta

	if find_timer <= 0.0 and can_hold_more():
		find_timer = FIND_INTERVAL
		find_things_to_throw()

	calc_goal_positions()

	var player_near := center.distance_to(host.player_pos) <= only_throw_at_radius

	for id in holding.keys():
		var held: Held = holding[id]

		if held.throwing:
			if throw_thing_at_target(held, delta):
				holding.erase(id)
				finish_throw(held.node)
		else:
			hold_thing_in_reserve(held, delta)

			if not player_near:
				continue

			held.timer += delta

			if held.timer >= hold_time:
				held.throwing = true
				held.timer = 0.0

func is_throwable(sprite: Node) -> bool:
	if sprite == host or not sprite is RegolithSprite or not sprite.is_dynamic():
		return false

	var throwable := Throwable.of(sprite)
	if throwable == null or throwable.thrown or throwable.held_by != null:
		return false

	if sprite is EnemyBomb and sprite.exploding:
		return false

	return sprite.get_active_cell_count() <= max_cells

func find_things_to_throw() -> void:
	var world := RegolithWorld.active()

	if world == null:
		return

	for sprite in Steering.sprites_near(world, center, radius_max):
		if not can_hold_more():
			return

		if is_holding(sprite) or not is_throwable(sprite):
			continue

		if (sprite.global_position / Steering.ppu()).distance_to(center) > radius_max:
			continue

		Throwable.of(sprite).held_by = host
		holding[sprite.get_instance_id()] = Held.new(sprite, center)

func release(node: Node) -> void:
	var throwable := Throwable.of(node)
	if throwable:
		throwable.held_by = null

func finish_throw(node: RegolithSprite) -> void:
	var throwable := Throwable.of(node)
	throwable.thrown = true
	throwable.held_by = null

	if node is EnemyBomb:
		var distance: float = host.player_pos.distance_to(node.global_position / Steering.ppu())
		var speed: float = node.linear_velocity.length()
		node.start_fuse(minf(distance / maxf(speed, 0.001), 4.0))

	threw.emit(node)

func calc_goal_positions() -> void:
	var held_list: Array = holding.values()
	var count := held_list.size()
	var arc_start := arc_base + hold_arc_min
	var delta_theta := (hold_arc_max - hold_arc_min) / (count + 1)
	var goals: Array = []

	for i in count:
		var t := float(i) / (count - 1) if count > 1 else 0.0
		var radius := lerpf(radius_min, radius_max, t)

		if held_list[i].throwing:
			radius += 1.0

		goals.append(center + Vector2.from_angle(arc_start + delta_theta * (i + 1)) * radius)

	for held in held_list:
		var held_pos: Vector2 = held.node.global_position / Steering.ppu()
		var best := 0
		var best_distance: float = held_pos.distance_to(goals[0])

		for j in range(1, goals.size()):
			var d: float = held_pos.distance_to(goals[j])

			if d < best_distance:
				best_distance = d
				best = j

		held.goal = goals[best]
		goals[best] = goals.back()
		goals.pop_back()

func hold_thing_in_reserve(held: Held, delta: float) -> void:
	var node := held.node
	var held_pos: Vector2 = node.global_position / Steering.ppu()
	var correction := orbit_steer(held_pos, held.goal)
	node.linear_velocity = Steering.dampen(node.linear_velocity + correction * delta * pull, 20.0, delta)

func throw_thing_at_target(held: Held, delta: float) -> bool:
	var node := held.node
	var held_pos: Vector2 = node.global_position / Steering.ppu()
	var target := host.player_pos
	var target_goal := target
	var thrower_to_goal := center - target
	var thrower_to_held := center - held_pos
	var damping := 1.0

	if thrower_to_goal.dot(thrower_to_held) < 0.0:
		target_goal = center + around_direction(target - held_pos, thrower_to_held)
		damping = 6.0
	else:
		held.timer += delta

		if held.timer >= throw_time:
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
	var center := host_now.to_global(Vector2(origin.x, -origin.y) * Vector2(cells) * 0.5 * Steering.cell_pixels()) / ppu
	var a0 := arc_base + hold_arc_min
	var a1 := arc_base + hold_arc_max

	Steering.gz_cross(g, to_local, ppu, center, 0.25, color, name)
	Steering.gz_arc(g, to_local, ppu, center, radius_min, a0, a1, color, name)
	Steering.gz_arc(g, to_local, ppu, center, radius_max, a0, a1, color, name)
	Steering.gz_line(g, to_local, ppu, center + Vector2.from_angle(a0) * radius_min, center + Vector2.from_angle(a0) * radius_max, color, name)
	Steering.gz_line(g, to_local, ppu, center + Vector2.from_angle(a1) * radius_min, center + Vector2.from_angle(a1) * radius_max, color, name)
	Steering.gz_circle(g, to_local, ppu, center, only_throw_at_radius, color, name)

	for held in holding.values():
		if is_instance_valid(held.node):
			Steering.gz_line(g, to_local, ppu, held.node.global_position / ppu, held.goal, color, name)

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

	var step := clampf(target_theta - theta, -0.6, 0.6)
	var r_goal := clampf((target_goal - center).length(), radius_min, radius_max)
	var r_now := clampf(r, radius_min, radius_max)
	var r_target := clampf(lerpf(r_now, r_goal, 0.25), radius_min, radius_max)

	return center + Vector2.from_angle(theta + step) * r_target - held_pos
