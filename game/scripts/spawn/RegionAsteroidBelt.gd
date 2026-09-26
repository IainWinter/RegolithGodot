extends Resource
class_name RegionAsteroidBelt

# RegionAsteroidBelt: count rocks scattered on a ring around position at
# radii between min_radius and max_radius, all riding an OrbitMover at
# angular_speed around the ring center. the seed makes the layout the same
# every time. sizes are chunks, one chunk is one unit

@export var position := Vector2.ZERO
@export var min_radius := 20.0
@export var max_radius := 30.0
@export var min_chunks := 1
@export var max_chunks := 3
@export var count := 24
@export var angular_speed := 0.1
@export var seed := 1337
@export var rock_props: RockProps
