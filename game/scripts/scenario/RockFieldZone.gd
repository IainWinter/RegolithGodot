@tool
extends Node2D
class_name RockFieldZone

# a box of drifting rocks centered on this node. the Scenario turns it into
# a RegionRockField with count rocks from density over the box area. the
# box follows the node's rotation in the editor gizmo only, the region
# fills an axis aligned box. size is the full box in sim units

#
# every export that changes the layout marks the Scenario's preview dirty
# from its setter, see mark_dirty

@export var size := Vector2(20.0, 20.0):
	set(value):
		size = value.abs()
		mark_dirty()
# rocks per square unit
@export_range(0.0, 1.0, 0.001, "or_greater") var density := 0.02:
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

func area() -> float:
	return size.x * size.y

func rock_count() -> int:
	return maxi(int(round(density * area())), 0)

func field_rock_props(fallback: RockProps) -> RockProps:
	var source := rock_props if rock_props else fallback

	if source == null:
		return null

	var props: RockProps = source.duplicate()
	props.min_chunks = min_chunks
	props.max_chunks = maxi(max_chunks, min_chunks)
	return props

func to_rock_field(offset_units: Vector2, fallback: RockProps) -> RegionRockField:
	var field := RegionRockField.new()
	field.position = offset_units
	field.size = size
	field.seed = seed
	field.min_count = rock_count()
	field.max_count = rock_count()
	field.rock_props = field_rock_props(fallback)
	return field
