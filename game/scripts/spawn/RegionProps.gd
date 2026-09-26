extends Resource
class_name RegionProps

# the RegionAsset: what a Region node lays out once when it generates.
# offsets are relative to the region node, in units

@export var one_time_spawns: Array[RegionSpawn] = []
@export var spawn_zones: Array[RegionSpawnZone] = []
@export var asteroid_belts: Array[RegionAsteroidBelt] = []
@export var rock_fields: Array[RegionRockField] = []
