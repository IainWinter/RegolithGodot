extends Node

# Ai autoload: the one lua state every scripted enemy lives in. loads
# res://game/lua/prelude.lua, then the MODULES (plain tables scripts reach
# with require(name), message_types holds the message kind constants),
# then each other .lua file there as a class named after the file.
# instances are made per node by EnemyScripted and addressed by id, the lua
# side reaches its node through self.node and the runtime through the ai
# table the prelude wraps around __runtime. each scripted node also owns an
# AiStateMachine the script registers its states with, see that file.
#
# messages are dictionaries with a kind. between scripted things they go
# out as a courier sprite (send) that flies to the target and can be shot
# down, or land next tick with no node (send_instant). either way the
# target's receive gets the payload plus sender and transport

const SCRIPT_DIR := "res://game/lua"
const PRELUDE := "prelude"
# loaded after the prelude and before any class, in this order
const MODULES := ["message_types"]

# what spawn answers with, mirrors message_types.lua
const SPAWNED := "spawned"
const SPAWN_EXPIRED := "spawn_expired"

signal script_error(where: String, message: String)
# a courier spawned or a message landed, for tests and debug views
signal sent(sender: Object, target: Object, payload: Dictionary, transport: String)

var lua: RegolithLua

func _ready() -> void:
	lua = RegolithLua.new()
	lua.script_error.connect(func(where: String, message: String): script_error.emit(where, message))
	lua.set_global("__runtime", self)
	load_all()

func read_script(name: String) -> String:
	var path := "%s/%s.lua" % [SCRIPT_DIR, name]

	if not FileAccess.file_exists(path):
		push_warning("Ai: no script at %s" % path)
		return ""

	return FileAccess.get_file_as_string(path)

func load_all() -> void:
	var prelude := read_script(PRELUDE)

	if prelude != "":
		lua.run(prelude, PRELUDE)

	for module in MODULES:
		load_module(module)

	for file in DirAccess.get_files_at(SCRIPT_DIR):
		if file.get_extension() == "lua" and file.get_basename() != PRELUDE and not MODULES.has(file.get_basename()):
			load_class(file.get_basename())

# a module chunk returns a table that lands in __modules[name] for
# require(name). "" on success, else the error
func load_module(name: String) -> String:
	var source := read_script(name)

	if source == "":
		return "empty script"

	return lua.run(wrap_module(name, source), name)

# the chunk runs as a function so its return value can be kept. the source
# starts on the first line so error line numbers match the file
static func wrap_module(name: String, source: String) -> String:
	return '__modules["%s"] = (function() %s\nend)()' % [name, source]

# "" on success, else the error. loading a live class again hot swaps its
# methods under every instance
func load_class(name: String) -> String:
	var source := read_script(name)

	if source == "":
		return "empty script"

	return lua.load_class(name, source)

func has_class(name: String) -> bool:
	return lua.has_class(name)

# instances

func create(class_name_: String, owner: Object) -> int:
	if not lua.has_class(class_name_):
		push_warning("Ai: no class %s for %s" % [class_name_, owner])
		return 0

	return lua.create(class_name_, owner)

func destroy(id: int) -> void:
	lua.destroy(id)

func invoke(id: int, method: String, args: Array = []) -> Variant:
	return lua.call(id, method, args)

# messages. sender and target are nodes, the payload a dictionary with a
# kind. anything with a receive(payload) method can be a target

func stamp(sender: Object, payload: Dictionary, transport: String) -> Dictionary:
	var message := payload.duplicate()
	message["sender"] = sender
	message["transport"] = transport
	return message

func can_receive(target: Object) -> bool:
	return Steering.alive(target) and target.has_method("receive")

func send_instant(sender: Object, target: Object, payload: Dictionary) -> bool:
	if not can_receive(target):
		return false

	var message := stamp(sender, payload, "instant")
	target.call_deferred("receive", message)
	sent.emit(sender, target, message, "instant")
	return true

func send(sender: Object, target: Object, payload: Dictionary) -> SpawnRequest:
	if not can_receive(target) or not is_instance_valid(sender) or not sender is Node2D:
		return null

	var message := stamp(sender, payload, "courier")
	var ppu := RegolithWorld.pixels_per_unit()
	var from: Vector2 = sender.global_position / ppu
	var to: Vector2 = target.global_position / ppu
	var direction := (to - from).normalized() if to != from else Vector2.RIGHT
	var clear := Steering.sprite_radius_units(sender) + 0.5 if sender is RegolithSprite else 0.5

	var request := SpawnRequest.message(from + direction * clear)
	request.spawned.connect(func(node: RegolithSprite):
		node.setup(sender, target, message)
		sent.emit(sender, target, message, "courier"))
	return SpawnBus.send(request)

func receivers_near(sender: Object, radius: float) -> Array:
	var world := RegolithWorld.active()

	if world == null or not is_instance_valid(sender) or not sender is Node2D:
		return []

	var out := []

	for sprite in Steering.sprites_near(world, sender.global_position / RegolithWorld.pixels_per_unit(), radius):
		if sprite != sender and can_receive(sprite):
			out.append(sprite)

	return out

func broadcast(sender: Object, radius: float, payload: Dictionary) -> int:
	var count := 0

	for target in receivers_near(sender, radius):
		if send(sender, target, payload) != null:
			count += 1

	return count

func broadcast_instant(sender: Object, radius: float, payload: Dictionary) -> int:
	var count := 0

	for target in receivers_near(sender, radius):
		if send_instant(sender, target, payload):
			count += 1

	return count

# the world for the scripts: spawning and queries, generic, no enemy in
# particular. sender is the node asking, positions and radii are sim
# units, results in units too

# lands a runtime message in the target's inbox at once, stamped like the
# others with the runtime as sender
func deliver(target: Object, payload: Dictionary) -> bool:
	if not can_receive(target):
		return false

	var message := stamp(self, payload, "runtime")
	target.receive(message)
	sent.emit(self, target, message, "runtime")
	return true

# a SpawnRequest of the kind named as in SpawnRequest.Kind (any case) sent
# on the bus with the sender allowed to touch the spot. the sender hears
# SPAWNED (node, request, tag) or SPAWN_EXPIRED (request, tag) later, the
# tag is whatever string the script wants to tell its requests apart by.
# null for an unknown kind
func spawn(sender: Object, kind_name: String, position: Vector2, velocity := Vector2.ZERO, offscreen_only := false, lifetime := 10.0, tag := "") -> SpawnRequest:
	var key := kind_name.to_upper()

	if not SpawnRequest.Kind.has(key):
		push_warning("Ai: no spawn kind %s" % kind_name)
		return null

	return send_spawn(sender, SpawnRequest.enemy(SpawnRequest.Kind[key], position, velocity, offscreen_only, lifetime), tag)

# a rock generated from the props, answered like spawn
func spawn_rock(sender: Object, props: RockProps, position: Vector2, velocity := Vector2.ZERO, offscreen_only := false, lifetime := 10.0, tag := "") -> SpawnRequest:
	if props == null:
		push_warning("Ai: spawn_rock without props")
		return null

	return send_spawn(sender, SpawnRequest.rock(props, position, velocity, offscreen_only, lifetime), tag)

func send_spawn(sender: Object, request: SpawnRequest, tag: String) -> SpawnRequest:
	if sender is RegolithSprite:
		request.ignore = [sender]

	request.spawned.connect(func(node: RegolithSprite): deliver(sender, {"kind": SPAWNED, "node": node, "request": request, "tag": tag}))
	request.expired.connect(func(): deliver(sender, {"kind": SPAWN_EXPIRED, "request": request, "tag": tag}))
	return SpawnBus.send(request)

# the camera as the scripts see it: half extents and center in units, and
# the height of the design camera
func camera_half_extents(node: Object) -> Vector2:
	if not is_instance_valid(node) or not node is Node:
		return Vector2.ZERO

	return Steering.camera_half_extents(node)

func camera_center(node: Object, fallback: Vector2) -> Vector2:
	if not is_instance_valid(node) or not node is Node:
		return fallback

	return Steering.camera_center(node, fallback)

func camera_size() -> float:
	return float(RegolithWorld.CAMERA_HEIGHT)

# the warning line telegraph between two points in units
func warn(from: Vector2, to: Vector2, seconds := 2.0) -> WarningLine:
	var ppu := RegolithWorld.pixels_per_unit()
	return WarningLine.warn(from * ppu, to * ppu, seconds)

# a RegolithSprite cell type constant by name, CELL_WEAKPOINT1 and the
# like, -1 when there is none
func cell_type(name: String) -> int:
	if not ClassDB.class_has_integer_constant("RegolithSprite", name):
		push_warning("Ai: no cell type %s" % name)
		return -1

	return ClassDB.class_get_integer_constant("RegolithSprite", name)

# every other sprite whose bounds touch the box of radius around the sender
func sprites_near(sender: Object, radius: float) -> Array:
	var world := RegolithWorld.active()

	if world == null or not is_instance_valid(sender) or not sender is Node2D:
		return []

	var out := []

	for sprite in Steering.sprites_near(world, sender.global_position / RegolithWorld.pixels_per_unit(), radius):
		if sprite != sender:
			out.append(sprite)

	return out

# the live nodes in a scene group
func group(name: String) -> Array:
	var out := []

	for node in get_tree().get_nodes_in_group(name):
		if Steering.alive(node):
			out.append(node)

	return out

# lua hands groups over as a table, which crosses as an Array, or as
# nothing at all
static func to_groups(groups: Variant) -> PackedStringArray:
	if groups is PackedStringArray:
		return groups

	if groups is Array:
		return PackedStringArray(groups)

	return PackedStringArray()

# a clear line between two points, the sender never blocks it, nor do the
# groups named
func line_of_sight(sender: Object, from: Vector2, to: Vector2, ignore_groups: Variant = null) -> bool:
	var world := RegolithWorld.active()

	if world == null:
		return true

	var ppu := RegolithWorld.pixels_per_unit()
	return world.has_line_of_sight(from * ppu, to * ppu, sender as RegolithSprite, to_groups(ignore_groups))

# the first cell hit along the segment: sprite, cell, position and
# distance (units), empty when nothing is in the way
func ray_cast(sender: Object, from: Vector2, to: Vector2, ignore_groups: Variant = null) -> Dictionary:
	var world := RegolithWorld.active()

	if world == null:
		return {}

	var ppu := RegolithWorld.pixels_per_unit()
	var hit: Dictionary = world.ray_cast(from * ppu, to * ppu, sender as RegolithSprite, to_groups(ignore_groups))

	if hit.is_empty():
		return {}

	return {
		"sprite": hit["sprite"],
		"cell": hit["cell"],
		"position": hit["position"] / ppu,
		"distance": float(hit["distance"]) / ppu,
	}

# the sprites on the other end of a world joint with the node
func jointed(node: Object) -> Array:
	var world := RegolithWorld.active()
	var out := []

	if world == null or not is_instance_valid(node):
		return out

	for joint_id in world.get_joint_ids():
		var sprites: Array = world.get_joint_sprites(joint_id)

		for sprite in sprites:
			if sprite != node and is_instance_valid(sprite) and sprites.has(node) and not out.has(sprite):
				out.append(sprite)

	return out

# a voice line from a scripted node's character, see the Dialog autoload.
# the speaker resolves from the node (its ai_class) through CharacterRegistry
func say(node: Object, text: String, duration := -1.0) -> bool:
	if not is_instance_valid(node) or not node is Node:
		return false

	return Dialog.say_from(node, text, duration)
