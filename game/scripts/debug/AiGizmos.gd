@tool
class_name AiGizmos
extends Node

# debug lines for the enemy ai parts: thrower arcs, shield polygons, trap
# boxes. a child of the DebugDraw autoload, runs while that is visible,
# quiet otherwise. the parts expose their geometry, this only draws it. sim
# units in, pixels out at the drawer
#
# two walks share the drawing: _process walks the live enemies and adds what
# only a running game knows (held rocks, the player), emit_scene walks a
# scene tree by node type and exports alone, which is what the editor plugin
# calls to draw over the scene being edited, where no enemy script runs

const ARC_SEGMENTS := 24

var draw: RegolithDebugDraw

func _ready() -> void:
	draw = get_parent() as RegolithDebugDraw
	process_priority = -1

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or draw == null or not draw.is_visible_in_tree():
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

# editor walk: every RegolithSprite under root with part children, read
# through their exports. the parts are placeholders here, so only property
# gets and the parts' static geometry are safe
func emit_scene(root: Node) -> void:
	var hosts: Array[Node] = root.find_children("*", "RegolithSprite", true, false)

	if root is RegolithSprite:
		hosts.append(root)

	for host in hosts:
		for child in host.get_children():
			if script_is(child, EnemyThrower):
				thrower_lines(host, child, host.global_rotation)
			elif script_is(child, EnemyBossShield):
				shield_lines(host, child)
			elif script_is(child, EnemyBossTrap):
				var box: Array = EnemyBossTrap.hull_box(child, host)
				trap_lines(child, box[0], box[1], box[2], box[3])

# script inheritance check that also holds for placeholder instances
static func script_is(node: Node, type: Script) -> bool:
	var script := node.get_script() as Script

	while script:
		if script == type:
			return true
		script = script.get_base_script()

	return false

# live

func draw_thrower(host: Enemy, thrower: EnemyThrower) -> void:
	thrower_lines(host, thrower, thrower.arc_base_angle(host.player_pos))

	for held in thrower.holding.values():
		if is_instance_valid(held.node):
			line(held.node.global_position / Steering.ppu(), held.goal, RegolithDebugDraw.AI_THROWER)

func draw_shield(host: Enemy, shield: EnemyBossShield) -> void:
	var name := RegolithDebugDraw.AI_SHIELD

	if not shield_lines(host, shield) or host.player == null:
		return

	var slot := shield.slot_point(host, host.player_pos)
	cross(slot, 0.5, name)

	for rock in shield.holding:
		if is_instance_valid(rock):
			line(rock.global_position / Steering.ppu(), slot, name)

func draw_trap(trap: EnemyBossTrap) -> void:
	trap_lines(trap, trap.center, trap.half, trap.angle, trap.push)

	if trap.pull_target and is_instance_valid(trap.pull_target):
		line(trap.pull_target.global_position / Steering.ppu(), trap.push, RegolithDebugDraw.AI_TRAP)

# geometry from exports, shared by both walks. parts untyped, see emit_scene

func thrower_lines(host: RegolithSprite, thrower: Node, base: float) -> void:
	var name := RegolithDebugDraw.AI_THROWER
	var center: Vector2 = EnemyThrower.center_of(thrower, host)
	var a0: float = base + thrower.hold_arc_min
	var a1: float = base + thrower.hold_arc_max
	var r0: float = thrower.radius_min
	var r1: float = thrower.radius_max

	cross(center, 0.25, name)
	arc(center, r0, a0, a1, name)
	arc(center, r1, a0, a1, name)
	line(center + Vector2.from_angle(a0) * r0, center + Vector2.from_angle(a0) * r1, name)
	line(center + Vector2.from_angle(a1) * r0, center + Vector2.from_angle(a1) * r1, name)
	circle(center, thrower.only_throw_at_radius, name)

func shield_lines(host: RegolithSprite, shield: Node) -> bool:
	var name := RegolithDebugDraw.AI_SHIELD
	var hull: PackedVector2Array = EnemyBossShield.hull_world(shield, host)

	if hull.size() < 3:
		return false

	var centroid: Vector2 = EnemyBossShield.centroid_of(hull)
	polygon(hull, name)
	cross(centroid, 0.25, name)
	circle(centroid, shield.capture_radius, name)
	return true

func trap_lines(trap: Node, center: Vector2, half: Vector2, angle: float, push: Vector2) -> void:
	var name := RegolithDebugDraw.AI_TRAP

	polygon(EnemyBossTrap.corners_of(center, half, angle), name)
	polygon(EnemyBossTrap.corners_of(center, half, angle, trap.boundary_margin), name)
	cross(push, 0.25, name)
	circle(push, trap.margin, name)

# primitives, sim units

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
