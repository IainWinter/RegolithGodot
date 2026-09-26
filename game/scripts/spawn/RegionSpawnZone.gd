extends Resource
class_name RegionSpawnZone

# RegionSpawnZone: a box that fills with a weighted pick of kinds when the
# region generates. endless zones fill to max_alive, others spawn
# spawn_count, each pick lands burst_count in a row. positions are picked
# inside the box. units, radians. trigger_radius, respawn_seconds and
# require_line_of_sight are kept from the asset but unused, as they were

@export var position := Vector2.ZERO
@export var half_size := Vector2(1.0, 1.0)
@export var angle := 0.0
@export var kinds: Array[SpawnRequest.Kind] = []
@export var weights: Array[float] = []
@export var burst_count := 1
@export var trigger_radius := 30.0
@export var max_alive := 5
@export var spawn_count := 0
@export var endless := true
@export var respawn_seconds := 2.0
@export var require_line_of_sight := true

func pick(rng: RandomNumberGenerator) -> int:
	if kinds.is_empty():
		return -1

	var total := 0.0

	for i in kinds.size():
		total += weights[i] if i < weights.size() else 1.0

	var roll := rng.randf() * total

	for i in kinds.size():
		roll -= weights[i] if i < weights.size() else 1.0

		if roll <= 0.0:
			return kinds[i]

	return kinds[kinds.size() - 1]

func count() -> int:
	return maxi(max_alive if endless else spawn_count, 1)

func random_point(rng: RandomNumberGenerator, origin: Vector2) -> Vector2:
	return Steering.random_in_box(origin + position, half_size, angle, rng)
