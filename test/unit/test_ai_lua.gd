extends GutTest

# the lua ai layer: the RegolithLua bridge round trips values and objects,
# classes load and instance, errors do not escape, the runtime delivers
# instant messages and courier sprites, a shot courier never lands, the
# player sensor reports the player coming into range

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const MESSAGE_SCENE := preload("res://game/scenes/ai/AiMessage.tscn")
const FIGHTER_SCENE := preload("res://game/scenes/enemies/EnemyFighter.tscn")
const BOMB_SCENE := preload("res://game/scenes/enemies/EnemyBomb.tscn")
const PLAYER_SCENE := preload("res://game/scenes/player/Player.tscn")

class Probe:
	extends Node2D
	var inbox: Array = []
	var last_args: Array = []
	func receive(message: Dictionary) -> void:
		inbox.append(message)
	func add(a: int, b: int) -> int:
		last_args = [a, b]
		return a + b
	func where() -> Vector2:
		return position

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)
	spawner = StableSpawner.new()
	spawner.message_scene = MESSAGE_SCENE
	spawner.fighter_scene = FIGHTER_SCENE
	spawner.bomb_scene = BOMB_SCENE
	arena.add_child(spawner)
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func fresh_lua() -> RegolithLua:
	var lua := RegolithLua.new()
	lua.run(FileAccess.get_file_as_string("res://game/lua/prelude.lua"), "prelude")
	return lua

# bridge

func test_values_round_trip() -> void:
	var lua := fresh_lua()
	lua.set_global("v", {"n": 3, "f": 1.5, "s": "hi", "b": true, "p": Vector2(2, 4), "list": [1, 2, 3], "nested": {"k": "v"}})
	assert_eq(lua.run("out = { n = v.n + 1, f = v.f * 2, s = v.s .. '!', b = not v.b, p = v.p * 2, list = { v.list[3], v.list[1] }, len = #v.list, k = v.nested.k }"), "")
	var out: Dictionary = lua.get_global("out")
	assert_eq(out["n"], 4)
	assert_eq(out["f"], 3.0)
	assert_eq(out["s"], "hi!")
	assert_eq(out["b"], false)
	assert_eq(out["p"], Vector2(4, 8))
	assert_eq(out["list"], [3, 1])
	assert_eq(out["len"], 3)
	assert_eq(out["k"], "v")

func test_vec2_math() -> void:
	var lua := fresh_lua()
	assert_eq(lua.run("a = vec2(3, 4); b = vec2(1, 0); len = a:length(); n = a:normalized(); d = a:dot(b); r = from_angle(0); s = a - b; m = 2 * b"), "")
	assert_almost_eq(float(lua.get_global("len")), 5.0, 0.0001)
	assert_almost_eq(Vector2(lua.get_global("n")).x, 0.6, 0.0001)
	assert_eq(lua.get_global("d"), 3.0)
	assert_eq(lua.get_global("r"), Vector2(1, 0))
	assert_eq(lua.get_global("s"), Vector2(2, 4))
	assert_eq(lua.get_global("m"), Vector2(2, 0))

func test_objects_call_methods_and_read_properties() -> void:
	var lua := fresh_lua()
	var probe := Probe.new()
	probe.position = Vector2(10, 20)
	add_child_autofree(probe)
	lua.set_global("probe", probe)
	assert_eq(lua.run("sum = probe:add(2, 3); pos = probe.position; w = probe:where(); probe.position = vec2(1, 2); ok = ai.valid(probe); same = probe == probe"), "")
	assert_eq(lua.get_global("sum"), 5)
	assert_eq(probe.last_args, [2, 3])
	assert_eq(lua.get_global("pos"), Vector2(10, 20))
	assert_eq(lua.get_global("w"), Vector2(10, 20))
	assert_eq(probe.position, Vector2(1, 2))
	assert_true(lua.get_global("ok"))
	assert_true(lua.get_global("same"))

func test_freed_object_reads_nil_and_is_invalid() -> void:
	var lua := fresh_lua()
	var probe := Probe.new()
	lua.set_global("probe", probe)
	probe.free()
	assert_eq(lua.run("ok = ai.valid(probe); pos = probe.position; r = probe.add"), "")
	assert_false(lua.get_global("ok"))
	assert_null(lua.get_global("pos"))
	assert_null(lua.get_global("r"), "no methods on a freed object")

func test_class_instances_keep_state_and_call_node() -> void:
	var lua := fresh_lua()
	var probe := Probe.new()
	add_child_autofree(probe)
	var source := """
local C = class("counter")
function C:init() self.count = 0 end
function C:update(dt) self.count = self.count + 1; return self.count end
function C:poke(a, b) return self.node:add(a, b) end
return C
"""
	assert_eq(lua.load_class("counter", source), "")
	assert_true(lua.has_class("counter"))
	var id := lua.create("counter", probe)
	assert_gt(id, 0)
	assert_eq(lua.get_instance_count(), 1)
	assert_eq(lua.call(id, "update", [0.1]), 1)
	assert_eq(lua.call(id, "update", [0.1]), 2)
	assert_eq(lua.call(id, "poke", [4, 5]), 9)
	assert_true(lua.has_method(id, "update"))
	assert_false(lua.has_method(id, "nothing"))
	assert_null(lua.call(id, "nothing", []), "missing methods are nil, not errors")
	lua.destroy(id)
	assert_eq(lua.get_instance_count(), 0)
	assert_false(lua.has_instance(id))

func test_reload_swaps_methods_under_live_instances() -> void:
	var lua := fresh_lua()
	var probe := Probe.new()
	add_child_autofree(probe)
	assert_eq(lua.load_class("c", "local C = class('c'); function C:init() self.n = 5 end; function C:get() return self.n end; return C"), "")
	var id := lua.create("c", probe)
	assert_eq(lua.call(id, "get", []), 5)
	assert_eq(lua.load_class("c", "local C = class('c'); function C:get() return self.n * 10 end; return C"), "")
	assert_eq(lua.call(id, "get", []), 50, "old state, new method")

func test_errors_are_reported_not_thrown() -> void:
	var lua := fresh_lua()
	lua.print_errors = false
	var errors := []
	lua.script_error.connect(func(where, message): errors.append([where, message]))
	assert_ne(lua.run("this is not lua"), "")
	assert_ne(lua.load_class("bad", "return 5"), "")
	assert_eq(lua.load_class("boom", "local C = class('boom'); function C:update() error('kaboom') end; return C"), "")
	var id := lua.create("boom", null)
	assert_null(lua.call(id, "update", [0.1]))
	assert_eq(errors.size(), 3)
	assert_true(String(errors[2][1]).contains("kaboom"))

func test_instruction_limit_stops_runaway_loops() -> void:
	var lua := fresh_lua()
	lua.instruction_limit = 100000
	lua.print_errors = false
	var errors := []
	lua.script_error.connect(func(_where, message): errors.append(message))
	assert_ne(lua.run("while true do end"), "")
	assert_eq(errors.size(), 1)
	assert_true(String(errors[0]).contains("instruction limit"))
	assert_eq(lua.run("x = 1"), "", "the state still works after")

func test_sandbox_has_no_io_or_load() -> void:
	var lua := fresh_lua()
	assert_eq(lua.run("has = { io = io ~= nil, os = os ~= nil, load = load ~= nil, loadfile = loadfile ~= nil, dofile = dofile ~= nil, math = math ~= nil, string = string ~= nil, debug = debug ~= nil }"), "")
	var has: Dictionary = lua.get_global("has")
	assert_false(has["io"])
	assert_false(has["os"])
	assert_false(has["load"])
	assert_false(has["loadfile"])
	assert_false(has["dofile"])
	assert_false(has["debug"])
	assert_true(has["math"])
	assert_true(has["string"])

# the prelude's require only hands back tables the runtime loaded
func test_require_is_the_module_shim() -> void:
	var lua := fresh_lua()
	lua.print_errors = false
	assert_ne(lua.run("m = require('nothing')"), "", "unknown modules error")
	assert_eq(lua.run(Ai.wrap_module("thing", "local T = { N = 4 }; return T"), "thing"), "")
	assert_eq(lua.run("n = require('thing').N"), "")
	assert_eq(lua.get_global("n"), 4)

func test_runtime_loaded_message_types() -> void:
	assert_eq(Ai.lua.run("__kinds = require('message_types')"), "")
	var kinds: Dictionary = Ai.lua.get_global("__kinds")
	assert_eq(kinds["PLAYER_SEEN"], PlayerSensor.PLAYER_SEEN)
	assert_eq(kinds["PLAYER_UPDATE"], PlayerSensor.PLAYER_UPDATE)
	assert_eq(kinds["PLAYER_LOST"], PlayerSensor.PLAYER_LOST)
	assert_true(kinds.has("SQUAD_JOIN") and kinds.has("SQUAD_ACCEPT") and kinds.has("SQUAD_JOINED") and kinds.has("SQUAD_FULL"))

# runtime

func test_runtime_loaded_game_classes() -> void:
	assert_true(Ai.has_class("fighter"))
	assert_true(Ai.has_class("bomb"))
	assert_true(Ai.has_class("base"))
	assert_true(Ai.has_class("station"))
	assert_true(Ai.has_class("gun"))

func test_runtime_spawn_kinds_mirror_message_types() -> void:
	assert_eq(Ai.lua.run("__kinds = require('message_types')"), "")
	var kinds: Dictionary = Ai.lua.get_global("__kinds")
	assert_eq(kinds["SPAWNED"], Ai.SPAWNED)
	assert_eq(kinds["SPAWN_EXPIRED"], Ai.SPAWN_EXPIRED)

# the world through the runtime

func test_spawn_answers_the_sender_with_a_spawned_message() -> void:
	var probe := Probe.new()
	probe.position = Vector2(4, 0) * ppu()
	arena.add_child(probe)

	assert_null(Ai.spawn(probe, "nothing_of_the_sort", Vector2.ZERO), "unknown kinds are refused")

	var request := Ai.spawn(probe, "fighter", Vector2(4, 0), Vector2(1, 0))
	assert_not_null(request)
	assert_eq(request.kind, SpawnRequest.Kind.FIGHTER)
	assert_eq(request.velocity, Vector2(1, 0))
	await wait_physics_frames(3)

	assert_eq(probe.inbox.size(), 1, "the sender heard back")
	if probe.inbox.is_empty():
		return
	var message: Dictionary = probe.inbox[0]
	assert_eq(message["kind"], Ai.SPAWNED)
	assert_true(message["node"] is EnemyFighter, "the placed node rides along")
	assert_eq(message["request"], request)
	assert_eq(message["transport"], "runtime")
	assert_eq(message["sender"], Ai)

func test_spawn_expired_reaches_the_sender() -> void:
	var probe := Probe.new()
	arena.add_child(probe)
	var blocker: EnemyFighter = FIGHTER_SCENE.instantiate()
	blocker.ai_class = ""
	arena.add_child(blocker)
	await wait_physics_frames(2)

	# the spot is taken and the request gives up within a few frames
	var request := Ai.spawn(probe, "fighter", Vector2.ZERO, Vector2.ZERO, false, 0.05)
	assert_not_null(request)
	await wait_physics_frames(10)
	assert_eq(probe.inbox.size(), 1)
	if not probe.inbox.is_empty():
		assert_eq(probe.inbox[0]["kind"], Ai.SPAWN_EXPIRED)

func test_lua_spawn_lands_in_the_script_inbox() -> void:
	var bomb: EnemyBomb = BOMB_SCENE.instantiate()
	arena.add_child(bomb)
	await wait_physics_frames(2)

	assert_eq(Ai.lua.run("__t = __instance(%d); __t.got = nil; function __t:on_message(msg) if msg.kind == 'spawned' then self.got = msg.node end end; __r = __t:spawn('fighter', vec2(20, 0), vec2(0, 1))" % bomb.ai_id), "")
	assert_true(Ai.lua.get_global("__r") is SpawnRequest, "the request comes back to lua")
	await wait_physics_frames(4)
	assert_eq(Ai.lua.run("__got = __t.got"), "")
	assert_true(Ai.lua.get_global("__got") is EnemyFighter, "the script saw its spawn land")

func test_group_sprites_near_and_line_of_sight() -> void:
	var a := Probe.new()
	a.position = Vector2.ZERO
	arena.add_child(a)
	var fighter: EnemyFighter = FIGHTER_SCENE.instantiate()
	fighter.position = Vector2(3, 0) * ppu()
	arena.add_child(fighter)
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(12, 0) * ppu()
	player.set_process(false)
	arena.add_child(player)
	await wait_physics_frames(2)

	assert_eq(Ai.group("player"), [player])
	assert_true(Ai.group("enemy").has(fighter))
	assert_eq(Ai.group("nobody_here"), [])

	var near := Ai.sprites_near(a, 5.0)
	assert_true(near.has(fighter), "the fighter is within five units")
	assert_false(near.has(player), "the player is not")

	# the art sits at the top left of the padded grid, so aim through the
	# body's center of mass, not the node origin
	var body: Vector2 = fighter.get_center_of_mass() / ppu()
	var from := Vector2(body.x - 3.0, body.y)
	var to := Vector2(body.x + 9.0, body.y)
	assert_false(Ai.line_of_sight(a, from, to), "the fighter is in the way")
	assert_true(Ai.line_of_sight(a, from, to, ["enemy", "player"]), "ignoring enemies clears it")
	assert_true(Ai.line_of_sight(a, from + Vector2(0, 10), to + Vector2(0, 10)), "nothing along that line")

	var hit := Ai.ray_cast(a, from, to)
	assert_false(hit.is_empty(), "the cast hit")
	if not hit.is_empty():
		assert_eq(hit["sprite"], fighter)
		assert_lt(float(hit["distance"]), 4.0, "distance in units")
	assert_eq(Ai.ray_cast(a, from + Vector2(0, 10), to + Vector2(0, 10)), {}, "no hit, empty")

	assert_eq(Ai.lua.run("__los = ai.line_of_sight(__runtime, vec2(%f, %f), vec2(%f, %f), {'enemy', 'player'}); __hit = ai.ray_cast(__runtime, vec2(%f, %f), vec2(%f, %f)).distance" % [from.x, from.y, to.x, to.y, from.x, from.y, to.x, to.y]), "")
	assert_true(Ai.lua.get_global("__los"), "a lua table of groups crosses")
	assert_lt(float(Ai.lua.get_global("__hit")), 4.0)

func test_jointed_reports_the_joint_partner() -> void:
	var a: EnemyFighter = FIGHTER_SCENE.instantiate()
	a.ai_class = ""
	arena.add_child(a)
	var b: EnemyFighter = FIGHTER_SCENE.instantiate()
	b.ai_class = ""
	b.position = Vector2(4, 0) * ppu()
	arena.add_child(b)
	await wait_physics_frames(2)

	assert_eq(Ai.jointed(a), [], "loose")
	world.add_distance_joint(a, b, a.global_position, b.global_position, 4.0)
	await wait_physics_frames(2)
	assert_eq(Ai.jointed(a), [b])
	assert_eq(Ai.jointed(b), [a])

func test_lua_say_reaches_the_dialog() -> void:
	Dialog.clear()
	var bomb: EnemyBomb = BOMB_SCENE.instantiate()
	arena.add_child(bomb)
	await wait_physics_frames(2)

	assert_eq(Ai.lua.run("__said = __instance(%d):say('fuse is lit')" % bomb.ai_id), "")
	assert_true(Ai.lua.get_global("__said"), "the line was taken")
	var texts := Dialog.queued_texts()
	texts.append(Dialog.current_text())
	assert_true(texts.has("fuse is lit"), "the line is on screen or waiting: %s" % [texts])
	Dialog.clear()

# tunables

func test_ai_config_overrides_the_script_defaults() -> void:
	var station: EnemyScripted = load("res://game/scenes/enemies/EnemyStation.tscn").instantiate()
	station.ai_config = {"spawn_interval": 0.5, "spawn_origin": Vector2(0.25, 0.25)}
	arena.add_child(station)
	await wait_physics_frames(2)

	assert_eq(Ai.lua.run("__cfg = __instance(%d).cfg" % station.ai_id), "")
	var cfg: Dictionary = Ai.lua.get_global("__cfg")
	assert_eq(cfg["spawn_interval"], 0.5, "overridden")
	assert_eq(cfg["spawn_origin"], Vector2(0.25, 0.25), "a Vector2 crosses as vec2")
	assert_eq(cfg["max_spawned"], 8, "the default stays")

	station.configure({"max_spawned": 3})
	assert_eq(Ai.lua.run("__cfg = __instance(%d).cfg" % station.ai_id), "")
	assert_eq(Ai.lua.get_global("__cfg")["max_spawned"], 3, "changed on the live instance")
	assert_eq(station.ai_config["max_spawned"], 3)

func test_send_instant_lands_next_tick_with_sender_and_transport() -> void:
	var a := Probe.new()
	var b := Probe.new()
	add_child_autofree(a)
	add_child_autofree(b)
	assert_true(Ai.send_instant(a, b, {"kind": "ping", "n": 1}))
	assert_eq(b.inbox.size(), 0, "not during the call")
	await wait_physics_frames(1)
	assert_eq(b.inbox.size(), 1)
	assert_eq(b.inbox[0]["kind"], "ping")
	assert_eq(b.inbox[0]["sender"], a)
	assert_eq(b.inbox[0]["transport"], "instant")
	assert_false(Ai.send_instant(a, Node.new(), {}), "no receive, no delivery")

func test_courier_flies_to_target_and_delivers() -> void:
	var a := Probe.new()
	var b := Probe.new()
	a.position = Vector2(0, 0)
	b.position = Vector2(6, 0) * ppu()
	arena.add_child(a)
	arena.add_child(b)

	var request := Ai.send(a, b, {"kind": "hello"})
	assert_not_null(request)

	var couriers := {}
	request.spawned.connect(func(node): couriers["node"] = node)

	for i in 240:
		await wait_physics_frames(1)
		if not b.inbox.is_empty():
			break

	assert_true(couriers.has("node"), "a courier spawned")
	assert_eq(b.inbox.size(), 1, "the message landed")
	if b.inbox.is_empty():
		return
	assert_eq(b.inbox[0]["kind"], "hello")
	assert_eq(b.inbox[0]["transport"], "courier")
	assert_eq(b.inbox[0]["sender"], a)
	await wait_physics_frames(2)
	assert_false(is_instance_valid(couriers["node"]), "courier gone after delivery")

func test_shot_courier_never_lands() -> void:
	var a := Probe.new()
	var b := Probe.new()
	b.position = Vector2(12, 0) * ppu()
	arena.add_child(a)
	arena.add_child(b)

	var request := Ai.send(a, b, {"kind": "secret"})
	var couriers := {}
	var hits := {"intercepted": 0}
	request.spawned.connect(func(node):
		couriers["node"] = node
		node.intercepted.connect(func(_payload): hits["intercepted"] += 1))

	for i in 30:
		await wait_physics_frames(1)
		if couriers.has("node") and couriers["node"].get_active_cell_count() > 0:
			break

	assert_true(couriers.has("node"), "a courier spawned")
	if not couriers.has("node"):
		return

	var courier: AiMessage = couriers["node"]
	assert_gt(courier.get_active_cell_count(), 0, "courier has cells to shoot")
	await wait_physics_frames(2)

	# shoot it: take one cell
	var count := courier.get_cell_count()
	for y in count.y:
		for x in count.x:
			if courier.has_cell(Vector2i(x, y)):
				courier.remove_cell(Vector2i(x, y))
				break

	await wait_physics_frames(120)
	assert_eq(hits["intercepted"], 1, "courier reported the hit")
	assert_eq(b.inbox.size(), 0, "message never arrived")
	assert_false(is_instance_valid(courier), "courier gone")

func test_broadcast_reaches_receivers_in_range() -> void:
	var a := Probe.new()
	arena.add_child(a)
	var fighter: EnemyFighter = FIGHTER_SCENE.instantiate()
	fighter.position = Vector2(3, 0) * ppu()
	arena.add_child(fighter)
	var far: EnemyFighter = FIGHTER_SCENE.instantiate()
	far.position = Vector2(40, 0) * ppu()
	arena.add_child(far)
	await wait_physics_frames(2)

	assert_eq(Ai.broadcast_instant(a, 10.0, {"kind": "hey"}), 1, "one receiver in range")
	await wait_physics_frames(1)

# sensors

func test_player_sensor_reports_seen_update_lost() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(20, 0) * ppu()
	player.set_process(false)
	arena.add_child(player)

	var host: EnemyFighter = FIGHTER_SCENE.instantiate()
	host.ai_class = ""
	arena.add_child(host)
	var sensor: PlayerSensor = host.get_node("PlayerSensor")
	sensor.radius = 10.0
	sensor.update_interval = 0.05
	var kinds := []
	sensor.message.connect(func(message: Dictionary): kinds.append(message["kind"]))
	await wait_physics_frames(10)
	assert_eq(kinds.size(), 0, "player out of range, nothing to say")

	sensor.radius = 100.0
	await wait_physics_frames(2)
	assert_eq(kinds.front(), "player_seen")
	await wait_physics_frames(30)
	assert_true(kinds.has("player_update"))

	sensor.radius = 10.0
	await wait_physics_frames(3)
	assert_eq(kinds.back(), "player_lost")

func test_scripted_enemy_gets_sensor_messages_in_lua() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.position = Vector2(6, 0) * ppu()
	player.set_process(false)
	arena.add_child(player)

	var bomb: EnemyBomb = BOMB_SCENE.instantiate()
	arena.add_child(bomb)
	await wait_physics_frames(5)

	assert_gt(bomb.ai_id, 0, "bomb has a lua instance")
	assert_eq(Ai.lua.run("__t = __instance(%d); __seen = __t.player ~= nil and __t.player.position or nil" % bomb.ai_id), "")
	var seen: Variant = Ai.lua.get_global("__seen")
	assert_true(seen is Vector2, "the script was told about the player")
	if seen is Vector2:
		assert_almost_eq(Vector2(seen).x, 6.0, 0.5)
