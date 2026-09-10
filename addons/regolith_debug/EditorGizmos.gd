class_name EditorGizmos
extends RegolithGizmos

# painter that draws onto the 2D editor viewport overlay. scripts emit in
# world pixel space, the canvas transform maps them to overlay pixels.
# reads channel enabled/color from the shared source so the dock's filter
# and colors apply here the same as at runtime; the script's color arg is
# used as a fallback when there is no source

var overlay: Control
var xform: Transform2D
var source: RegolithDebugDraw

func line(a: Vector2, b: Vector2, color: Color, name: int) -> void:
	if source:
		if not source.is_name_enabled(name):
			return
		color = source.get_name_color(name)
	overlay.draw_line(xform * (transform * a), xform * (transform * b), color, 2.0)
