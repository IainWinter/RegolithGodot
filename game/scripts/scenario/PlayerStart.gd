@tool
extends Node2D
class_name PlayerStart

# where the player begins: this node's position and rotation. the Scenario
# applies it to the player before the sprite loads its body, since a
# dynamic sprite ignores position writes once it is in the sim. the arrow
# gizmo shows the facing, arrow_length is its size in sim units

@export var arrow_length := 1.5

func apply(player: Node2D) -> void:
	player.global_position = global_position
	player.global_rotation = global_rotation
