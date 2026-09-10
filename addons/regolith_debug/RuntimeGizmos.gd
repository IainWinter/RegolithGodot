class_name RuntimeGizmos
extends RegolithGizmos

# painter that forwards to a RegolithDebugDraw. scripts emit local pixels,
# transform lifts them to scene pixels for the world-space debug renderer.
# color arg is ignored, name drives the color at draw time

var draw: RegolithDebugDraw

func line(a: Vector2, b: Vector2, _color: Color, name: int) -> void:
	draw.add_line(transform * a, transform * b, name)
