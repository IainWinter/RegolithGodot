extends Node
class_name GravityMover

# marks its parent sprite as something gravity pulls on, with how hard.
# every GravityAttractor in the scene tugs at every mover each physics step

@export var strength := 1.0

var sprite: RegolithSprite

func _enter_tree() -> void:
	add_to_group("gravity_mover")

func _ready() -> void:
	sprite = get_parent() as RegolithSprite

	if sprite == null:
		push_warning("GravityMover must be a child of a RegolithSprite")
