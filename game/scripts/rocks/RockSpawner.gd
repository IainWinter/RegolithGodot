extends Node2D
class_name RockSpawner

# keeps a belt of generated rocks drifting around the target. rocks are asked
# for on the bus just outside the camera view, the StableSpawner places them
# on a free spot, and they are freed once they drift past the despawn
# radius. sizes are sim units

@export var target: Node2D
@export var props: RockProps
@export var radius_units := 18.0
@export var despawn_radius_units := 26.0
@export var max_rocks := 24
@export var seed := 0
@export var spawn_interval := 0.25
@export var view_margin_units := 1.0
@export var spot_margin_units := 0.25
@export var view_radius_units := 0.0

signal rock_spawned(sprite: RegolithSprite)

var rocks: Array[RegolithSprite] = []
var pieces: Array[RegolithSprite] = []
var pending := 0

var rng := RandomNumberGenerator.new()
var world: RegolithWorld
var timer := 0.0

func _ready() -> void:
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()

func _physics_process(delta: float) -> void:
	if not find_world():
		return

	var focus := focus_position()
	prune(rocks, focus)
	prune(pieces, focus)

	timer -= delta

	if timer > 0.0 or rocks.size() + pending >= max_rocks or props == null:
		return

	timer = spawn_interval
	request_rock(focus)

func find_world() -> bool:
	if world and is_instance_valid(world) and world.is_inside_tree():
		return true

	world = RegolithWorld.active()

	if world and not world.sprite_split.is_connected(on_sprite_split):
		world.sprite_split.connect(on_sprite_split)

	return world != null

func focus_position() -> Vector2:
	if target == null or not is_instance_valid(target):
		target = Steering.find_player(get_tree())

	return target.global_position if target else global_position

func on_sprite_split(source: RegolithSprite, piece: RegolithSprite) -> void:
	if source in rocks or source in pieces:
		piece.add_to_group("regolith")
		pieces.append(piece)

func prune(list: Array[RegolithSprite], focus: Vector2) -> void:
	Steering.prune_dead(list)
	var despawn := despawn_radius_units * Steering.ppu()

	for i in range(list.size() - 1, -1, -1):
		if focus.distance_to(list[i].global_position) > despawn:
			list[i].queue_free()
			list.remove_at(i)

func view_radius() -> float:
	if view_radius_units > 0.0:
		return view_radius_units * Steering.ppu()

	return Steering.camera_half_extents(self).length() * Steering.ppu()

func request_rock(focus: Vector2) -> SpawnRequest:
	var ppu := Steering.ppu()
	var chunks := RockGenerator.pick_chunks(rng, props)
	var half := chunks * ppu * 0.5
	var inner := view_radius() + view_margin_units * ppu + half
	var outer := maxf(radius_units * ppu, inner)
	var spot := focus + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(inner, outer)

	var request := SpawnRequest.rock(props, spot / ppu, Vector2.ZERO, true)
	request.chunks = chunks
	request.drift = true
	request.rng = rng
	request.clearance = spot_margin_units
	pending += 1
	request.spawned.connect(on_spawned)
	request.expired.connect(func(): pending -= 1)
	return SpawnBus.send(request)

func on_spawned(rock: RegolithSprite) -> void:
	pending -= 1
	rocks.append(rock)
	rock_spawned.emit(rock)
