@tool
class_name Sensor
extends Node

# a sense organ on a scripted enemy: a child node that watches the world
# for one thing and emits a message when something about it changes. the
# ai never asks, it only gets told. EnemyScripted polls each sensor child on
# the physics step and forwards the messages to its script. positions in
# messages are sim units. @tool so sensors can draw editor gizmos, nothing
# here runs on its own, polling only happens from a live EnemyScripted

signal message(payload: Dictionary)

func host() -> RegolithSprite:
	return get_parent() as RegolithSprite

func host_pos() -> Vector2:
	var sprite := host()
	return sprite.global_position / RegolithWorld.pixels_per_unit() if sprite else Vector2.ZERO

func poll(_delta: float) -> void:
	pass

func report(kind: String, fields: Dictionary = {}) -> void:
	fields["kind"] = kind
	fields["sensor"] = name
	message.emit(fields)
