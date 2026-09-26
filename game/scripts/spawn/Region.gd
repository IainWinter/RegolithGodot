extends Node2D
class_name Region

# port of RegionManagementSystem and the RegionEntity: a spot in the world
# that lays out its props once, right after it enters the tree. one time
# spawns are placed as they are, zones fill from their weighted kinds,
# belts scatter seeded rocks on a ring and put them on orbit as they land,
# rock fields fill a box. every request goes over the SpawnBus and what
# comes back is kept in spawned. node position is the region origin

@export var props: RegionProps
# generate once ready, off to call generate() yourself
@export var auto_generate := true

signal generated

var is_generated := false
var spawned: Array = []
var pending := 0

func origin_units() -> Vector2:
	return global_position / Steering.ppu()

func _ready() -> void:
	if auto_generate:
		generate.call_deferred()

func generate() -> void:
	if is_generated:
		return

	is_generated = true

	if props == null:
		generated.emit()
		return

	var origin := origin_units()

	for spawn in props.one_time_spawns:
		var request := SpawnRequest.enemy(spawn.kind, origin + spawn.position)
		request.rotation = spawn.rotation
		request.wait_for_room = false
		send(request)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for zone in props.spawn_zones:
		if zone.kinds.is_empty():
			continue

		var count := zone.count()
		var total := 0

		while total < count:
			var kind := zone.pick(rng)

			for b in maxi(zone.burst_count, 1):
				if total >= count:
					break

				send(SpawnRequest.enemy(kind, zone.random_point(rng, origin)))
				total += 1

	for belt in props.asteroid_belts:
		if belt.rock_props == null:
			continue

		var belt_rng := RandomNumberGenerator.new()
		belt_rng.seed = belt.seed
		var center := origin + belt.position
		var r_min := belt.min_radius
		var r_max := maxf(belt.max_radius, r_min)
		var c_min := maxi(belt.min_chunks, 1)
		var c_max := maxi(belt.max_chunks, c_min)

		for i in belt.count:
			var angle := belt_rng.randf_range(0.0, TAU)
			var radius := belt_rng.randf_range(r_min, r_max)
			var request := SpawnRequest.rock(belt.rock_props, center + Vector2.from_angle(angle) * radius)
			request.chunks = belt_rng.randi_range(c_min, c_max)
			var rock_rng := RandomNumberGenerator.new()
			rock_rng.seed = belt_rng.randi()
			request.rng = rock_rng
			request.spawned.connect(on_belt_rock_spawned.bind(center, belt.angular_speed))
			send(request)

	for field in props.rock_fields:
		if field.rock_props == null:
			continue

		var field_rng := RandomNumberGenerator.new()
		field_rng.seed = field.seed
		var center := origin + field.position
		var count := field_rng.randi_range(field.min_count, maxi(field.max_count, field.min_count))

		for i in count:
			var request := SpawnRequest.rock(field.rock_props, Steering.random_in_box(center, field.size * 0.5, 0.0, field_rng))
			var rock_rng := RandomNumberGenerator.new()
			rock_rng.seed = field_rng.randi()
			request.rng = rock_rng
			send(request)

	generated.emit()

func send(request: SpawnRequest) -> SpawnRequest:
	pending += 1
	request.spawned.connect(on_spawned)
	request.expired.connect(func(): pending -= 1)
	return SpawnBus.send(request)

func on_spawned(node: RegolithSprite) -> void:
	pending -= 1
	spawned.append(node)

# a belt rock rides its orbit from where it landed. the one split watcher
# for every belt is hooked the first time a rock lands, the world is
# certainly there by then
func on_belt_rock_spawned(node: RegolithSprite, center: Vector2, angular_speed: float) -> void:
	OrbitMover.attach(node, center, angular_speed)

	var world := RegolithWorld.active()

	if world and not world.sprite_split.is_connected(OrbitMover.release_piece):
		world.sprite_split.connect(OrbitMover.release_piece)

func alive() -> Array:
	Steering.prune_dead(spawned)
	return spawned

# plan: what generate() will ask for, without asking. the same seeds and
# the same draws in the same order as generate() above, so the scenario
# editor preview shows the rocks that will spawn. every item is a
# Dictionary with "type" (PLAN_ROCK or PLAN_ENEMY) and "position" in world
# units. rocks carry "chunks", "rock" (the RockGenerator.plan_rock
# description: seed, config, ore, rotation), "props", and for belt rocks
# "orbit_center" and "angular_speed". enemies carry "kind". spawn zones
# roll from a fresh randomized rng at runtime, so their spots are only
# representative: plan_spawn_zone takes the rng to use, plan() seeds one
# from the zone's index so a preview holds still between redraws
const PLAN_ROCK := &"rock"
const PLAN_ENEMY := &"enemy"

static func plan(props: RegionProps, origin: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if props == null:
		return out

	for spawn in props.one_time_spawns:
		out.append({
			"type": PLAN_ENEMY,
			"kind": spawn.kind,
			"position": origin + spawn.position,
			"rotation": spawn.rotation,
		})

	for i in props.spawn_zones.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(i)
		out.append_array(plan_spawn_zone(props.spawn_zones[i], origin, rng))

	for belt in props.asteroid_belts:
		out.append_array(plan_belt(belt, origin))

	for field in props.rock_fields:
		out.append_array(plan_rock_field(field, origin))

	return out

static func plan_spawn_zone(zone: RegionSpawnZone, origin: Vector2, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if zone.kinds.is_empty():
		return out

	var count := zone.count()
	var total := 0

	while total < count:
		var kind := zone.pick(rng)

		for b in maxi(zone.burst_count, 1):
			if total >= count:
				break

			out.append({
				"type": PLAN_ENEMY,
				"kind": kind,
				"position": zone.random_point(rng, origin),
				"rotation": 0.0,
			})
			total += 1

	return out

static func plan_belt(belt: RegionAsteroidBelt, origin: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if belt.rock_props == null:
		return out

	var belt_rng := RandomNumberGenerator.new()
	belt_rng.seed = belt.seed
	var center := origin + belt.position
	var r_min := belt.min_radius
	var r_max := maxf(belt.max_radius, r_min)
	var c_min := maxi(belt.min_chunks, 1)
	var c_max := maxi(belt.max_chunks, c_min)

	for i in belt.count:
		var angle := belt_rng.randf_range(0.0, TAU)
		var radius := belt_rng.randf_range(r_min, r_max)
		var position := center + Vector2.from_angle(angle) * radius
		var chunks := belt_rng.randi_range(c_min, c_max)
		var rock_rng := RandomNumberGenerator.new()
		rock_rng.seed = belt_rng.randi()
		var rock := RockGenerator.plan_rock(rock_rng, belt.rock_props, chunks)
		out.append({
			"type": PLAN_ROCK,
			"position": position,
			"chunks": chunks,
			"rock": rock,
			"props": belt.rock_props,
			"orbit_center": center,
			"angular_speed": belt.angular_speed,
		})

	return out

static func plan_rock_field(field: RegionRockField, origin: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if field.rock_props == null:
		return out

	var field_rng := RandomNumberGenerator.new()
	field_rng.seed = field.seed
	var center := origin + field.position
	var count := field_rng.randi_range(field.min_count, maxi(field.max_count, field.min_count))

	for i in count:
		var position := Steering.random_in_box(center, field.size * 0.5, 0.0, field_rng)
		var rock_rng := RandomNumberGenerator.new()
		rock_rng.seed = field_rng.randi()
		# the request leaves chunks to the spawner, which picks them off the
		# rock rng first, as plan_rock does with no chunks
		var rock := RockGenerator.plan_rock(rock_rng, field.rock_props, 0)
		out.append({
			"type": PLAN_ROCK,
			"position": position,
			"chunks": rock["chunks"],
			"rock": rock,
			"props": field.rock_props,
		})

	return out
