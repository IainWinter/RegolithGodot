extends Node2D
class_name StableSpawner

# StableSpawner: the one place sprites get spawned. it listens on the
# SpawnBus, queues every request and each physics step places the ones whose
# spot the sprite tree has clear, and that the camera cannot see when the
# request asks. a request that finds no room within its lifetime is dropped.
# the scene for each kind, the materials, the regolith group and the parent
# all live here, requesters only name a kind, a spot and a velocity

@export var fighter_scene: PackedScene
@export var bomb_scene: PackedScene
@export var station_scene: PackedScene
@export var base_scene: PackedScene
@export var boss_compass_scene: PackedScene
@export var boss_stingray_scene: PackedScene
@export var sprite_material: Material
@export var rope_material: Material
# spawned sprites go under this node, the world's parent when unset
@export var spawn_parent: Node

signal spawned(request: SpawnRequest, node: RegolithSprite)
signal expired(request: SpawnRequest)

class Entry:
	var request: SpawnRequest
	# scene spawns are built on arrival so their size is known
	var node: RegolithSprite
	var chunks := 0
	# half extents in units
	var half := Vector2.ZERO
	var age := 0.0

var queue: Array[Entry] = []
# placed this step and the one before, the tree sees them only after the
# world's step. each is {node, half}
var recent_now: Array = []
var recent_last: Array = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func _enter_tree() -> void:
	if not SpawnBus.spawn_requested.is_connected(enqueue):
		SpawnBus.spawn_requested.connect(enqueue)

func _exit_tree() -> void:
	if SpawnBus.spawn_requested.is_connected(enqueue):
		SpawnBus.spawn_requested.disconnect(enqueue)

	for entry in queue:
		drop(entry)

	queue.clear()

func pending() -> int:
	return queue.size()

func pending_of(kind: SpawnRequest.Kind) -> int:
	return queue.filter(func(e: Entry): return e.request.kind == kind).size()

# takes a request off the queue before it spawns
func cancel(request: SpawnRequest) -> void:
	for i in queue.size():
		if queue[i].request == request:
			drop(queue[i])
			queue.remove_at(i)
			return

# null for rocks and kinds with no scene set
func scene_for(kind: SpawnRequest.Kind) -> PackedScene:
	match kind:
		SpawnRequest.Kind.FIGHTER:
			return fighter_scene
		SpawnRequest.Kind.BOMB:
			return bomb_scene
		SpawnRequest.Kind.STATION:
			return station_scene
		SpawnRequest.Kind.BASE:
			return base_scene
		SpawnRequest.Kind.BOSS_COMPASS:
			return boss_compass_scene
		SpawnRequest.Kind.BOSS_STINGRAY:
			return boss_stingray_scene

	return null

func kind_name(kind: SpawnRequest.Kind) -> String:
	return SpawnRequest.Kind.keys()[kind]

func enqueue(request: SpawnRequest) -> void:
	var entry := Entry.new()
	entry.request = request

	if request.is_rock():
		if request.rock_props == null:
			push_warning("StableSpawner: rock request without props")
			drop(entry)
			return

		entry.chunks = request.chunks if request.chunks > 0 else RockGenerator.pick_chunks(request_rng(request), request.rock_props)
		entry.half = Vector2.ONE * entry.chunks * 0.5
	else:
		var scene := scene_for(request.kind)

		if scene == null:
			push_warning("StableSpawner: no scene for kind %s" % kind_name(request.kind))
			drop(entry)
			return

		entry.node = scene.instantiate() as RegolithSprite

		if entry.node == null:
			push_warning("StableSpawner: scene for kind %s is not a RegolithSprite" % kind_name(request.kind))
			drop(entry)
			return

		if entry.node.texture:
			entry.half = Vector2(entry.node.texture.get_size()) * 0.5 / RegolithWorld.CELLS_PER_CHUNK

	queue.append(entry)

func request_rng(request: SpawnRequest) -> RandomNumberGenerator:
	return request.rng if request.rng else rng

func _physics_process(delta: float) -> void:
	recent_last = recent_now
	recent_now = []

	var world := RegolithWorld.active()
	var kept: Array[Entry] = []

	for entry in queue:
		entry.age += delta

		if entry.age > entry.request.lifetime:
			drop(entry)
		elif world != null and world.is_inside_tree() and can_place(world, entry):
			place(world, entry)
		else:
			kept.append(entry)

	queue = kept

# the sprite's bounds at the spot, units
func bounds(entry: Entry) -> Rect2:
	return Rect2(entry.request.position - entry.half, entry.half * 2.0)

func can_place(world: RegolithWorld, entry: Entry) -> bool:
	var request := entry.request

	if request.offscreen_only and camera_sees(bounds(entry)):
		return false

	if not request.wait_for_room:
		return true

	var rect := bounds(entry).grow(request.clearance)
	var ppu := Steering.ppu()

	for sprite in world.query_rect(Rect2(rect.position * ppu, rect.size * ppu)):
		if not request.ignore.has(sprite):
			return false

	for placed in recent_last + recent_now:
		var node = placed["node"]

		if not is_instance_valid(node) or request.ignore.has(node):
			continue

		var half: Vector2 = placed["half"]
		var center: Vector2 = node.global_position / ppu

		if rect.intersects(Rect2(center - half, half * 2.0)):
			return false

	return true

# the camera's view against a rect in units, both axis aligned
func camera_sees(rect: Rect2) -> bool:
	var viewport := get_viewport()
	var camera := viewport.get_camera_2d() if viewport else null

	if camera == null:
		return false

	var ppu := Steering.ppu()
	var half := viewport.get_visible_rect().size / camera.zoom * 0.5 / ppu
	var center := camera.get_screen_center_position() / ppu
	return Rect2(center - half, half * 2.0).intersects(rect)

func place(world: RegolithWorld, entry: Entry) -> void:
	var request := entry.request
	var parent := spawn_parent if spawn_parent else world.get_parent()
	var ppu := Steering.ppu()
	var node: RegolithSprite

	if request.is_rock():
		node = RockGenerator.spawn_rock(parent, world, request.position * ppu, request_rng(request), request.rock_props, sprite_material, entry.chunks)

		if node == null:
			drop(entry)
			return

		if not request.drift:
			node.linear_velocity = request.velocity
			node.angular_velocity = 0.0
	else:
		node = entry.node
		entry.node = null

		if sprite_material:
			node.material = sprite_material

		if rope_material:
			node.rope_material = rope_material

		# placed before it enters the tree so physics interpolation does not
		# sweep it in from the parent's origin
		var placement := Transform2D(request.rotation, request.position * ppu)
		var parent_2d := parent as Node2D
		node.transform = parent_2d.global_transform.affine_inverse() * placement if parent_2d else placement
		node.add_to_group("regolith")
		parent.add_child(node)
		node.reset_physics_interpolation()
		node.linear_velocity = request.velocity

	recent_now.append({"node": node, "half": entry.half})
	request.spawned.emit(node)
	spawned.emit(request, node)

func drop(entry: Entry) -> void:
	if entry.node:
		entry.node.free()
		entry.node = null

	entry.request.expired.emit()
	expired.emit(entry.request)
