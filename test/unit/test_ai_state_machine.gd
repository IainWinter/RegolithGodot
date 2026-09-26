extends GutTest

# the ai state machine: states registered from lua, transitions applied
# after the running update returns, enter/exit order, the log and signal,
# errors naming the state, and the fighter and bomb scripts landing in the
# states their messages call for. the debug panel's ai section lists them

const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const MESSAGE_SCENE := preload("res://game/scenes/ai/AiMessage.tscn")
const FIGHTER_SCENE := preload("res://game/scenes/enemies/EnemyFighter.tscn")
const BOMB_SCENE := preload("res://game/scenes/enemies/EnemyBomb.tscn")
const BASE_SCENE := preload("res://game/scenes/enemies/EnemyBase.tscn")
const STATION_SCENE := preload("res://game/scenes/enemies/EnemyStation.tscn")
const GUN_SCENE := preload("res://game/scenes/enemies/EnemyGun.tscn")

const WALKER := """
local C = class("walker")

function C:init()
	self.events = {}
	self.ticks = 0
	self:register_state("a", {
		enter = function(s) table.insert(s.events, "enter a") end,
		update = function(s, dt)
			table.insert(s.events, "update a")
			s.ticks = s.ticks + 1
			if s.ticks == 2 then s:transition("b") end
			table.insert(s.events, "after update a")
		end,
		exit = function(s) table.insert(s.events, "exit a") end,
	})
	self:register_state("b", { enter = "enter_b", update = "update_b" })
	self:transition("a")
end

function C:enter_b() table.insert(self.events, "enter b " .. self:previous_state()) end
function C:update_b(dt) table.insert(self.events, "update b " .. string.format("%.1f", self:time_in_state())) end
function C:take() local out = self.events; self.events = {}; return out end
return C
"""

class Probe:
	extends Node2D
	var state_machine: AiStateMachine

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
	Dialog.clear()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func fresh_lua() -> RegolithLua:
	var lua := RegolithLua.new()
	lua.run(FileAccess.get_file_as_string("res://game/lua/prelude.lua"), "prelude")
	return lua

# a probe with a machine and a walker instance bound to it
func make_walker(lua: RegolithLua) -> Array:
	var probe := Probe.new()
	probe.state_machine = AiStateMachine.new()
	probe.state_machine.label = "walker"
	add_child_autofree(probe)
	assert_eq(lua.load_class("walker", WALKER), "")
	var id := lua.create("walker", probe)
	assert_gt(id, 0)
	probe.state_machine.bind(lua, id)
	return [probe.state_machine, id]

func events(lua: RegolithLua, id: int) -> Array:
	var out: Variant = lua.call(id, "take", [])
	return out if out is Array else []

# a stand-in for the player: what the sensor looks for is a RegolithSprite
# in the player group
func add_player(units: Vector2) -> RegolithSprite:
	var player := RegolithSprite.new()
	player.position = units * ppu()
	player.angle_fixed = true
	player.add_to_group("regolith")
	player.add_to_group("player")
	arena.add_child(player)
	player.create_blank(Vector2i(8, 8))
	player.fill_rect(Rect2i(0, 0, 8, 8), Color.WHITE, RegolithSprite.CELL_FILLED, 0)
	return player

# machine

func test_states_register_and_first_transition_lands_on_bind() -> void:
	var lua := fresh_lua()
	var pair := make_walker(lua)
	var machine: AiStateMachine = pair[0]
	var id: int = pair[1]
	assert_eq(machine.get_states(), PackedStringArray(["a", "b"]))
	assert_true(machine.has_state("a"))
	assert_false(machine.has_state("c"))
	assert_eq(machine.get_state(), "a")
	assert_eq(machine.get_previous_state(), "")
	assert_eq(machine.get_time_in_state(), 0.0)
	assert_eq(events(lua, id), ["enter a"], "enter ran once, before any update")
	var entries := machine.get_transition_log()
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["from"], "")
	assert_eq(entries[0]["to"], "a")

func test_transition_from_update_applies_after_it_returns() -> void:
	var lua := fresh_lua()
	var pair := make_walker(lua)
	var machine: AiStateMachine = pair[0]
	var id: int = pair[1]
	var changes := []
	machine.state_changed.connect(func(from: String, to: String): changes.append([from, to]))
	events(lua, id)

	machine.tick(0.1)
	assert_eq(events(lua, id), ["update a", "after update a"])
	assert_eq(machine.get_state(), "a")
	assert_almost_eq(machine.get_time_in_state(), 0.1, 0.0001)

	machine.tick(0.1)
	assert_eq(events(lua, id), ["update a", "after update a", "exit a", "enter b a"], "update finished, then exit, then enter with the previous state visible")
	assert_eq(machine.get_state(), "b")
	assert_eq(machine.get_previous_state(), "a")
	assert_eq(machine.get_time_in_state(), 0.0)
	assert_eq(changes, [["a", "b"]])

	machine.tick(0.5)
	assert_eq(events(lua, id), ["update b 0.5"])

	var entries := machine.get_transition_log()
	assert_eq(entries.size(), 2)
	assert_eq(entries[1]["from"], "a")
	assert_eq(entries[1]["to"], "b")
	assert_almost_eq(float(entries[1]["at"]), 0.2, 0.0001)
	assert_eq(entries[1]["tick"], 2)

func test_transition_from_gdscript_applies_at_once_and_same_state_is_a_noop() -> void:
	var lua := fresh_lua()
	var pair := make_walker(lua)
	var machine: AiStateMachine = pair[0]
	var id: int = pair[1]
	events(lua, id)
	assert_true(machine.transition("a"))
	assert_eq(events(lua, id), [], "already there")
	assert_true(machine.transition("b"))
	assert_eq(events(lua, id), ["exit a", "enter b a"])
	assert_eq(machine.get_state(), "b")
	assert_false(machine.transition("nope"))
	assert_eq(machine.get_state(), "b")
	assert_true(machine.get_last_error().contains("nope"))

func test_held_transitions_wait_for_release() -> void:
	var lua := fresh_lua()
	var pair := make_walker(lua)
	var machine: AiStateMachine = pair[0]
	var id: int = pair[1]
	events(lua, id)
	machine.hold()
	assert_true(machine.transition("b"))
	assert_eq(machine.get_state(), "a")
	assert_eq(machine.get_pending_state(), "b")
	assert_eq(events(lua, id), [])
	machine.release()
	assert_eq(machine.get_state(), "b")
	assert_eq(events(lua, id), ["exit a", "enter b a"])

func test_log_keeps_the_last_entries() -> void:
	var lua := fresh_lua()
	var pair := make_walker(lua)
	var machine: AiStateMachine = pair[0]

	for i in AiStateMachine.LOG_SIZE * 2:
		machine.transition("b" if i % 2 == 0 else "a")

	var entries := machine.get_transition_log()
	assert_eq(entries.size(), AiStateMachine.LOG_SIZE)
	assert_eq(entries.back()["to"], "a")

func test_errors_in_a_state_name_it() -> void:
	var lua := fresh_lua()
	lua.print_errors = false
	var errors := []
	lua.script_error.connect(func(_where, message): errors.append(String(message)))
	var probe := Probe.new()
	probe.state_machine = AiStateMachine.new()
	add_child_autofree(probe)
	assert_eq(lua.load_class("boom", """
local C = class("boom")
function C:init()
	self:register_state("fuse", { update = function(s, dt) error("kaboom") end })
	self:register_state("gone", { enter = "missing" })
	self:transition("fuse")
end
function C:bad() self:transition("nowhere") end
return C
"""), "")
	var id := lua.create("boom", probe)
	probe.state_machine.bind(lua, id)
	probe.state_machine.tick(0.1)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("state 'fuse' update"), errors[0])
	assert_true(errors[0].contains("kaboom"), errors[0])
	assert_true(probe.state_machine.get_last_error().contains("fuse"))

	probe.state_machine.transition("gone")
	assert_eq(errors.size(), 2)
	assert_true(errors[1].contains("state 'gone' enter"), errors[1])
	assert_true(errors[1].contains("missing"), errors[1])

	lua.call(id, "bad", [])
	assert_eq(errors.size(), 3)
	assert_true(errors[2].contains("nowhere"), errors[2])

func test_unbound_machine_waits() -> void:
	var machine := AiStateMachine.new()
	assert_true(machine.register_state("x"))
	assert_false(machine.register_state(""))
	assert_true(machine.transition("x"))
	assert_eq(machine.get_state(), "", "nothing to call into yet")
	machine.tick(0.1)
	assert_eq(machine.get_state(), "")

# the game scripts

func test_fighter_states_follow_the_player() -> void:
	add_player(Vector2(200, 0))
	var fighter: EnemyFighter = FIGHTER_SCENE.instantiate()
	arena.add_child(fighter)
	await wait_physics_frames(3)

	assert_gt(fighter.ai_id, 0)
	assert_eq(fighter.state_machine.get_states(), PackedStringArray(["idle", "roam", "formation"]))
	assert_eq(fighter.state_machine.get_state(), "idle", "no player reported, holds position")
	assert_gt(fighter.state_machine.get_time_in_state(), 0.0)

	var sensor: PlayerSensor = fighter.get_node("PlayerSensor")
	sensor.radius = 1000.0
	await wait_physics_frames(3)
	assert_eq(fighter.state_machine.get_state(), "roam", "the sensor told it, it roams near the player")
	var entries := fighter.state_machine.get_transition_log()
	assert_eq(entries.back()["from"], "idle")
	assert_eq(entries.back()["to"], "roam")

	sensor.radius = 1.0
	await wait_physics_frames(3)
	assert_eq(fighter.state_machine.get_state(), "idle", "lost the player, back to idle")

func test_bomb_seeks_the_player_then_fuses() -> void:
	var player := add_player(Vector2(2, 0))
	var bomb: EnemyBomb = BOMB_SCENE.instantiate()
	bomb.start_exploding_radius = 0.0
	arena.add_child(bomb)
	await wait_physics_frames(3)

	assert_eq(bomb.state_machine.get_states(), PackedStringArray(["idle", "seek_thrower", "seek_player", "fused"]))
	assert_eq(bomb.state_machine.get_state(), "seek_player", "no thrower around, chases the player")

	bomb.start_exploding_radius = 10.0
	await wait_physics_frames(3)
	assert_true(bomb.exploding, "lit the fuse close to the player")
	assert_eq(bomb.state_machine.get_state(), "fused")
	assert_eq(bomb.state_machine.get_previous_state(), "seek_player")
	assert_true(is_instance_valid(player))

func test_bomb_idles_without_a_player() -> void:
	var bomb: EnemyBomb = BOMB_SCENE.instantiate()
	arena.add_child(bomb)
	await wait_physics_frames(3)
	assert_eq(bomb.state_machine.get_state(), "idle")

func add_scripted(scene: PackedScene, units: Vector2, config := {}) -> EnemyScripted:
	var enemy: EnemyScripted = scene.instantiate()
	enemy.position = units * ppu()
	enemy.ai_config = config
	arena.add_child(enemy)
	return enemy

func test_base_states_follow_the_player_distance() -> void:
	var base := add_scripted(BASE_SCENE, Vector2.ZERO)
	await wait_physics_frames(3)

	assert_gt(base.ai_id, 0)
	assert_eq(base.state_machine.get_states(), PackedStringArray(["idle", "guard", "throw"]))
	assert_eq(base.state_machine.get_state(), "idle", "no player reported, holds what it has")

	var player := add_player(Vector2(30.0, 0.0))
	await wait_physics_frames(3)
	assert_eq(base.state_machine.get_state(), "guard", "player known, outside the throw radius")

	player.linear_velocity = Vector2(-60.0, 0.0)
	await wait_physics_frames(20)
	player.linear_velocity = Vector2.ZERO
	assert_lt(player.global_position.x / ppu(), 18.0, "player moved inside the throw radius")
	await wait_physics_frames(3)
	assert_eq(base.state_machine.get_state(), "throw")
	var entries := base.state_machine.get_transition_log()
	assert_eq(entries.back()["from"], "guard")
	assert_eq(entries.back()["to"], "throw")

	var sensor: PlayerSensor = base.get_node("PlayerSensor")
	sensor.radius = 1.0
	await wait_physics_frames(3)
	assert_eq(base.state_machine.get_state(), "idle", "lost the player, back to idle")

func test_station_states_pick_escort_or_roam() -> void:
	var station := add_scripted(STATION_SCENE, Vector2.ZERO, {"spawn_interval": 1000.0})
	await wait_physics_frames(3)

	assert_eq(station.state_machine.get_states(), PackedStringArray(["idle", "escort", "roam"]))
	assert_eq(station.state_machine.get_state(), "idle", "no player reported")

	add_player(Vector2(30.0, 0.0))
	await wait_physics_frames(3)
	assert_eq(station.state_machine.get_state(), "roam", "no thrower nearer than the player")

	var base := add_scripted(BASE_SCENE, Vector2(8.0, 0.0))
	await wait_physics_frames(5)
	assert_eq(station.state_machine.get_state(), "escort", "a base with room nearer than the player")

	base.get_thrower().active = false
	await wait_physics_frames(3)
	assert_eq(station.state_machine.get_state(), "roam", "a full or inactive thrower is not escorted")

func test_gun_states_track_then_fire() -> void:
	# facing away from where the player will be; the body takes the node
	# transform as it enters the tree, later sets are ignored in the sim
	var gun: EnemyScripted = GUN_SCENE.instantiate()
	gun.rotation = PI
	arena.add_child(gun)
	await wait_physics_frames(3)

	assert_eq(gun.state_machine.get_states(), PackedStringArray(["idle", "track", "fire"]))
	assert_eq(gun.state_machine.get_state(), "idle")

	add_player(Vector2(5.0, 0.0))

	for i in 300:
		await wait_physics_frames(1)
		if gun.state_machine.get_state() == "fire":
			break

	assert_eq(gun.state_machine.get_state(), "fire", "swung onto the player and pulled the trigger")
	assert_true(gun.weapon.triggered)
	# headless steps run several ticks a frame, so the pass through track
	# shows in the log rather than being caught live
	var entries := gun.state_machine.get_transition_log()
	assert_true(entries.any(func(e): return e["from"] == "idle" and e["to"] == "track"), "seen first, facing the wrong way: %s" % [entries])
	assert_true(entries.any(func(e): return e["from"] == "track" and e["to"] == "fire"), "then aimed")

# inspector

func test_debug_panel_lists_scripted_enemies() -> void:
	add_player(Vector2(200, 0))
	var fighter: EnemyFighter = FIGHTER_SCENE.instantiate()
	arena.add_child(fighter)
	await wait_physics_frames(3)

	var panel := DebugPanel.new(world)
	arena.add_child(panel)
	await wait_process_frames(2)

	var report := panel.ai_report()
	assert_true(report.contains("scripted 1"), report)
	assert_true(report.contains("fighter  idle"), report)
	assert_true(report.contains("(none) -> idle"), report)
	assert_not_null(world.get_node_or_null("AiStateLabels"), "state labels drawn in the world while the panel is open")

	panel.queue_free()
	await wait_process_frames(2)
	assert_null(world.get_node_or_null("AiStateLabels"), "labels gone with the panel")
