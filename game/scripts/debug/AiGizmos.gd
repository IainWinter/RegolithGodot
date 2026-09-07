class_name AiGizmos
extends Node

# debug lines for the enemy ai parts: thrower arcs, shield polygons, trap
# boxes. a child of the scene's RegolithDebugDraw, runs while that is
# visible, quiet otherwise. the parts expose their geometry, this only
# draws it. sim units in, pixels out at the drawer

const ARC_SEGMENTS := 24

var draw: RegolithDebugDraw

func _ready() -> void:
	draw = get_parent() as RegolithDebugDraw
	process_priority = -1

func _process(_delta: float) -> void:
	if draw == null or not draw.is_visible_in_tree():
		return

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Enemy or enemy.dead or not enemy.is_loaded():
			continue

		for child in enemy.get_children():
			if child is EnemyThrower:
				draw_thrower(enemy, child)
			elif child is EnemyBossShield:
				draw_shield(enemy, child)
			elif child is EnemyBossTrap:
				draw_trap(child)

func draw_thrower(host: Enemy, thrower: EnemyThrower) -> void:
	var name := RegolithDebugDraw.AI_THROWER
	var center := thrower.center_units()
	var base := thrower.arc_base_angle(host.player_pos)
	var a0 := base + thrower.hold_arc_min
	var a1 := base + thrower.hold_arc_max

	cross(center, 0.25, name)
	arc(center, thrower.radius_min, a0, a1, name)
	arc(center, thrower.radius_max, a0, a1, name)
	line(center + Vector2.from_angle(a0) * thrower.radius_min, center + Vector2.from_angle(a0) * thrower.radius_max, name)
	line(center + Vector2.from_angle(a1) * thrower.radius_min, center + Vector2.from_angle(a1) * thrower.radius_max, name)
	circle(center, thrower.only_throw_at_radius, name)

	for held in thrower.holding.values():
		if is_instance_valid(held.node):
			line(held.node.global_position / Steering.ppu(), held.goal, name)

func draw_shield(host: Enemy, shield: EnemyBossShield) -> void:
	var name := RegolithDebugDraw.AI_SHIELD

	if shield.points.size() < 3:
		return

	var points := shield.world_points(host)
	var centroid := shield.world_centroid(host)

	polygon(points, name)
	cross(centroid, 0.25, name)
	circle(centroid, shield.capture_radius, name)

	if host.player == null:
		return

	var slot := shield.slot_point(host, host.player_pos)
	cross(slot, 0.5, name)

	for rock in shield.holding:
		if is_instance_valid(rock):
			line(rock.global_position / Steering.ppu(), slot, name)

func draw_trap(trap: EnemyBossTrap) -> void:
	var name := RegolithDebugDraw.AI_TRAP

	polygon(trap.box_corners(), name)
	polygon(trap.box_corners(trap.boundary_margin), name)
	cross(trap.push, 0.25, name)
	circle(trap.push, trap.margin, name)

	if trap.pull_target and is_instance_valid(trap.pull_target):
		line(trap.pull_target.global_position / Steering.ppu(), trap.push, name)

func line(a: Vector2, b: Vector2, name: int) -> void:
	draw.add_line(a * Steering.ppu(), b * Steering.ppu(), name)

func circle(center: Vector2, radius: float, name: int) -> void:
	draw.add_circle(center * Steering.ppu(), radius * Steering.ppu(), name)

func cross(at: Vector2, half: float, name: int) -> void:
	line(at + Vector2(-half, 0), at + Vector2(half, 0), name)
	line(at + Vector2(0, -half), at + Vector2(0, half), name)

func arc(center: Vector2, radius: float, a0: float, a1: float, name: int) -> void:
	var previous := center + Vector2.from_angle(a0) * radius

	for i in range(1, ARC_SEGMENTS + 1):
		var point := center + Vector2.from_angle(lerpf(a0, a1, float(i) / ARC_SEGMENTS)) * radius
		line(previous, point, name)
		previous = point

func polygon(points: PackedVector2Array, name: int) -> void:
	for i in points.size():
		line(points[i], points[(i + 1) % points.size()], name)
