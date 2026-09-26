extends Resource
class_name RegionRockField

# RegionGeneratedRegion with its rock rule: a box of size around position
# filled with min_count to max_count rocks at random spots. units

@export var position := Vector2.ZERO
@export var size := Vector2(20.0, 20.0)
@export var seed := 1337
@export var min_count := 1
@export var max_count := 5
@export var rock_props: RockProps
