class_name RegolithGizmos
extends RefCounted

# painter passed to draw_gizmos(g). scripts emit in LOCAL pixel space, the
# walker sets `transform` to the nearest Node2D ancestor's global_transform
# before calling draw_gizmos, and the subclasses apply it in line() to reach
# scene pixels for the debug renderer. shape helpers all funnel through
# line(), so the transform applies once per emitted segment. every shape is
# tagged with a RegolithDebugDraw name for dock filtering.

var transform: Transform2D = Transform2D.IDENTITY

func line(_a: Vector2, _b: Vector2, _color: Color, _name: int) -> void:
	pass

func circle(center: Vector2, radius: float, color: Color, name: int, steps: int = 24) -> void:
	var prev := center + Vector2.RIGHT * radius
	for i in range(1, steps + 1):
		var angle := TAU * float(i) / steps
		var next := center + Vector2(cos(angle), sin(angle)) * radius
		line(prev, next, color, name)
		prev = next

func polygon(points: PackedVector2Array, color: Color, name: int) -> void:
	var n := points.size()
	if n < 2:
		return
	for i in n:
		line(points[i], points[(i + 1) % n], color, name)

func cross(at: Vector2, half: float, color: Color, name: int) -> void:
	line(at + Vector2(-half, 0), at + Vector2(half, 0), color, name)
	line(at + Vector2(0, -half), at + Vector2(0, half), color, name)

func arc(center: Vector2, radius: float, a0: float, a1: float, color: Color, name: int, steps: int = 24) -> void:
	var prev := center + Vector2.from_angle(a0) * radius
	for i in range(1, steps + 1):
		var next := center + Vector2.from_angle(lerpf(a0, a1, float(i) / steps)) * radius
		line(prev, next, color, name)
		prev = next
