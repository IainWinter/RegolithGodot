class_name CellSensor
extends Sensor

# tells the script what the world does to its host's body: cells_removed
# when cells leave it (the count), sprite_split when a piece breaks off
# (the piece), core_exploded when one of its cores goes (position in
# units, power, type). the world's signals arrive whenever it commits, the
# messages wait in the host's inbox for its next ai tick. the kinds match
# res://game/lua/message_types.lua

const CELLS_REMOVED := "cells_removed"
const SPRITE_SPLIT := "sprite_split"
const CORE_EXPLODED := "core_exploded"

var world: RegolithWorld

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	watch()

# the world may not be active yet when the host enters the tree
func watch() -> void:
	if world != null:
		return

	world = RegolithWorld.active()

	if world == null:
		return

	world.cells_removed.connect(on_cells_removed)
	world.sprite_split.connect(on_sprite_split)
	world.core_exploded.connect(on_core_exploded)

func poll(_delta: float) -> void:
	watch()

func on_cells_removed(sprite: RegolithSprite, count: int) -> void:
	if sprite == host():
		report(CELLS_REMOVED, {"count": count})

func on_sprite_split(source: RegolithSprite, piece: RegolithSprite) -> void:
	if source == host():
		report(SPRITE_SPLIT, {"piece": piece})

func on_core_exploded(sprite: RegolithSprite, position: Vector2, power: int, type: int) -> void:
	if sprite == host():
		report(CORE_EXPLODED, {"position": position / RegolithWorld.pixels_per_unit(), "power": power, "type": type})
