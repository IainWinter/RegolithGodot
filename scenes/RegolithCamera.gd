extends Camera2D
class_name RegolithCamera

# vertical view size in sim units, aspect comes from the viewport
@export var height_units: float = RegolithWorld.CAMERA_HEIGHT
@export var target: Node2D
@export var follow_speed := 8.0

func _ready() -> void:
	get_viewport().size_changed.connect(update_zoom)
	update_zoom()

	if target:
		global_position = target.global_position

func update_zoom() -> void:
	var view_height := float(get_viewport_rect().size.y)
	var world_height := height_units * RegolithWorld.pixels_per_unit()
	zoom = Vector2.ONE * (view_height / world_height)

# smoothing is visual, it runs on the drawn frame
func _process(delta: float) -> void:
	if target:
		global_position = global_position.lerp(target.global_position, minf(delta * follow_speed, 1.0))
