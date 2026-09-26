@tool
extends Node2D
class_name SpawnZone

# a spot enemies come from. the Scenario turns it into a RegionSpawnZone
# which fills with a weighted pick of kinds when the region generates: a
# box of size rotated with the node, or a circle of radius (the region
# fills the circle's bounding box, it has no round zones). max_alive caps
# the fill, interval is kept on the zone as respawn_seconds for when the
# region respawns. sim units, radians

#
# every export that changes the fill marks the Scenario's preview dirty
# from its setter, see mark_dirty

enum Shape { RECT, CIRCLE }

@export var shape := Shape.RECT:
	set(value):
		shape = value
		mark_dirty()
# full box size for RECT
@export var size := Vector2(8.0, 8.0):
	set(value):
		size = value.abs()
		mark_dirty()
# for CIRCLE
@export var radius := 4.0:
	set(value):
		radius = maxf(value, 0.0)
		mark_dirty()
@export var kinds: Array[SpawnRequest.Kind] = [SpawnRequest.Kind.FIGHTER]:
	set(value):
		kinds = value
		mark_dirty()
# one weight per kind, missing weights count as 1
@export var weights: Array[float] = [1.0]:
	set(value):
		weights = value
		mark_dirty()
@export var max_alive := 3:
	set(value):
		max_alive = value
		mark_dirty()
# seconds between respawns
@export var interval := 5.0
@export var burst_count := 1:
	set(value):
		burst_count = value
		mark_dirty()
@export var endless := true:
	set(value):
		endless = value
		mark_dirty()
# used instead of max_alive when not endless
@export var spawn_count := 0:
	set(value):
		spawn_count = value
		mark_dirty()

func _ready() -> void:
	ScenarioGizmos.watch_transform(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		mark_dirty()

# the Scenario above replans its preview, nothing outside one or in the game
func mark_dirty() -> void:
	ScenarioGizmos.mark_dirty(self)

func half_size() -> Vector2:
	return Vector2.ONE * radius if shape == Shape.CIRCLE else size * 0.5

func to_spawn_zone(offset_units: Vector2) -> RegionSpawnZone:
	var zone := RegionSpawnZone.new()
	zone.position = offset_units
	zone.half_size = half_size()
	zone.angle = 0.0 if shape == Shape.CIRCLE else global_rotation
	zone.kinds = kinds.duplicate()
	zone.weights = weights.duplicate()
	zone.max_alive = max_alive
	zone.respawn_seconds = interval
	zone.burst_count = maxi(burst_count, 1)
	zone.endless = endless
	zone.spawn_count = spawn_count
	return zone
