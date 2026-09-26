extends Resource
class_name RegionSpawn

# RegionOneTimeSpawn: one thing placed once when the region generates, at
# an offset from the region node. units, radians

@export var kind := SpawnRequest.Kind.FIGHTER
@export var position := Vector2.ZERO
@export var rotation := 0.0
