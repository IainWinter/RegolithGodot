class_name Throwable
extends Node

# marker for things EnemyThrower can grab. hold state lives here so any
# dynamic sprite (bomb or otherwise) shares the same wire

var thrown := false
var held_by: Node = null

static func of(sprite: Node) -> Throwable:
	if sprite == null:
		return null
	for child in sprite.get_children():
		if child is Throwable:
			return child
	return null
