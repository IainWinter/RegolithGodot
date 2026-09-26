@tool
extends Node2D
class_name AsteroidBeltZone

# a ring of orbiting rocks around this node. the Scenario turns it into a
# RegionAsteroidBelt: rocks land at random radii between inner_radius and
# outer_radius and ride an OrbitMover around the center. count comes from
# density over the ring's area so a wider ring stays as busy. sizes are
# sim units, rock sizes are chunks, speed is radians per second

#
# every export that changes the layout marks the Scenario's preview dirty
# from its setter, see mark_dirty

@export var inner_radius := 8.0:
	set(value):
		inner_radius = maxf(value, 0.0)
		mark_dirty()
@export var outer_radius := 14.0:
	set(value):
		outer_radius = maxf(value, 0.0)
		mark_dirty()
# rocks per square unit of ring
@export_range(0.0, 1.0, 0.001, "or_greater") var density := 0.06:
	set(value):
		density = value
		mark_dirty()
@export var min_chunks := 1:
	set(value):
		min_chunks = value
		mark_dirty()
@export var max_chunks := 3:
	set(value):
		max_chunks = value
		mark_dirty()
# below zero keeps the rock props' own chance
@export_range(-1.0, 1.0, 0.01) var ore_chance := -1.0:
	set(value):
		ore_chance = value
		mark_dirty()
@export var orbit_speed := 0.05:
	set(value):
		orbit_speed = value
		mark_dirty()
# screen clockwise (positive angle in Godot's y down frame)
@export var clockwise := true:
	set(value):
		clockwise = value
		mark_dirty()
@export var seed := 1337:
	set(value):
		seed = value
		mark_dirty()
# none uses the Scenario's rock_props
@export var rock_props: RockProps:
	set(value):
		rock_props = value
		mark_dirty()

func _ready() -> void:
	ScenarioGizmos.watch_transform(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		mark_dirty()

# the Scenario above replans its preview, nothing outside one or in the game
func mark_dirty() -> void:
	ScenarioGizmos.mark_dirty(self)

# a fresh layout seed, the preview follows through the setter
func reroll_seed() -> int:
	seed = ScenarioGizmos.fresh_seed(seed)
	return seed

func ring_area() -> float:
	var r_max := maxf(outer_radius, inner_radius)
	var r_min := minf(outer_radius, inner_radius)
	return PI * (r_max * r_max - r_min * r_min)

func rock_count() -> int:
	return maxi(int(round(density * ring_area())), 0)

func angular_speed() -> float:
	return orbit_speed if clockwise else -orbit_speed

# the props the belt's rocks generate from: the chosen props with this
# zone's chunk range and ore chance on a copy, the shared .tres untouched
func belt_rock_props(fallback: RockProps) -> RockProps:
	var source := rock_props if rock_props else fallback

	if source == null:
		return null

	var props: RockProps = source.duplicate()
	props.min_chunks = min_chunks
	props.max_chunks = maxi(max_chunks, min_chunks)

	if ore_chance >= 0.0:
		props.ore_chance = ore_chance

	return props

func to_belt(offset_units: Vector2, fallback: RockProps) -> RegionAsteroidBelt:
	var belt := RegionAsteroidBelt.new()
	belt.position = offset_units
	belt.min_radius = minf(inner_radius, outer_radius)
	belt.max_radius = maxf(inner_radius, outer_radius)
	belt.min_chunks = min_chunks
	belt.max_chunks = maxi(max_chunks, min_chunks)
	belt.count = rock_count()
	belt.angular_speed = angular_speed()
	belt.seed = seed
	belt.rock_props = belt_rock_props(fallback)
	return belt
