extends GutTest

# PlayerSensor draws its radius circle, a tick toward the tracked player and
# a solid (clear) or dashed (blocked) line to them while inside the radius,
# through draw_gizmos into a recording painter

class Recorder:
	extends RegolithGizmos

	var lines: Array = []

	func line(a: Vector2, b: Vector2, _color: Color, name: int) -> void:
		lines.append({"a": a, "b": b, "name": name})

	func named(name: int) -> Array:
		return lines.filter(func(l): return l["name"] == name)

class BlockedSensor:
	extends PlayerSensor

	func in_sight(_from: Vector2, _to: Vector2) -> bool:
		return false

var arena: Node2D
var host: RegolithSprite
var target: RegolithSprite

func before_each() -> void:
	arena = Node2D.new()
	add_child(arena)
	host = RegolithSprite.new()
	arena.add_child(host)
	target = RegolithSprite.new()
	arena.add_child(target)

func after_each() -> void:
	arena.free()

func make_sensor(sensor: PlayerSensor = null) -> PlayerSensor:
	if sensor == null:
		sensor = PlayerSensor.new()
	sensor.radius = 5.0
	host.add_child(sensor)
	return sensor

func record(sensor: PlayerSensor) -> Recorder:
	var g := Recorder.new()
	sensor.draw_gizmos(g)
	return g

func put_target(units: Vector2) -> void:
	target.global_position = units * Steering.ppu()

func test_script_is_tool() -> void:
	var source := (load("res://game/scripts/ai/PlayerSensor.gd") as Script).get_source_code()
	assert_true(source.strip_edges().begins_with("@tool"))
	source = (load("res://game/scripts/ai/Sensor.gd") as Script).get_source_code()
	assert_true(source.strip_edges().begins_with("@tool"))

func test_circle_at_radius() -> void:
	var sensor := make_sensor()
	var circle := record(sensor).named(RegolithDebugDraw.AI)
	assert_gt(circle.size(), 8)
	var r := 5.0 * Steering.ppu()
	for l in circle:
		assert_almost_eq((l["a"] as Vector2).length(), r, 0.01)
		assert_almost_eq((l["b"] as Vector2).length(), r, 0.01)

func test_radius_change_redraws_circle() -> void:
	var sensor := make_sensor()
	sensor.radius = 12.0
	for l in record(sensor).named(RegolithDebugDraw.AI):
		assert_almost_eq((l["a"] as Vector2).length(), 12.0 * Steering.ppu(), 0.01)

func test_circle_in_host_local_space() -> void:
	host.global_position = Vector2(300, -200)
	var sensor := make_sensor()
	for l in record(sensor).named(RegolithDebugDraw.AI):
		assert_almost_eq((l["a"] as Vector2).length(), 5.0 * Steering.ppu(), 0.01)

func test_no_player_only_circle() -> void:
	var g := record(make_sensor())
	assert_eq(g.lines.size(), g.named(RegolithDebugDraw.AI).size())
	assert_eq(g.lines.size(), 32)

func test_player_inside_clear_draws_solid_line() -> void:
	var sensor := make_sensor()
	sensor.player = target
	put_target(Vector2(3, 0))
	var g := record(sensor)
	var clear := g.named(RegolithDebugDraw.AI_LOS_CLEAR)
	assert_eq(clear.size(), 1)
	assert_eq(clear[0]["a"], Vector2.ZERO)
	assert_almost_eq((clear[0]["b"] as Vector2).x, 3.0 * Steering.ppu(), 0.01)
	assert_eq(g.named(RegolithDebugDraw.AI_LOS_BLOCKED).size(), 0)
	# 32 circle segments plus the tick
	assert_eq(g.named(RegolithDebugDraw.AI).size(), 33)
	var tick: Dictionary = g.named(RegolithDebugDraw.AI)[32]
	assert_almost_eq((tick["a"] as Vector2).x, 4.5 * Steering.ppu(), 0.01)
	assert_almost_eq((tick["b"] as Vector2).x, 5.5 * Steering.ppu(), 0.01)

func test_player_outside_draws_tick_only() -> void:
	var sensor := make_sensor()
	sensor.player = target
	put_target(Vector2(0, 8))
	var g := record(sensor)
	assert_eq(g.named(RegolithDebugDraw.AI_LOS_CLEAR).size(), 0)
	assert_eq(g.named(RegolithDebugDraw.AI_LOS_BLOCKED).size(), 0)
	assert_eq(g.named(RegolithDebugDraw.AI).size(), 33)

func test_player_blocked_draws_dashed_line() -> void:
	var sensor := make_sensor(BlockedSensor.new())
	sensor.player = target
	put_target(Vector2(4, 0))
	sensor.poll(0.0)
	assert_false(sensor.sight_clear)
	var g := record(sensor)
	assert_eq(g.named(RegolithDebugDraw.AI_LOS_CLEAR).size(), 0)
	var dashes := g.named(RegolithDebugDraw.AI_LOS_BLOCKED)
	# 4 units in 0.5 dashes with 0.5 gaps
	assert_eq(dashes.size(), 4)
	for d in dashes:
		assert_almost_eq(((d["b"] as Vector2) - (d["a"] as Vector2)).length(), 0.5 * Steering.ppu(), 0.01)

func test_poll_records_clear_sight() -> void:
	var sensor := make_sensor()
	sensor.player = target
	sensor.sight_clear = false
	put_target(Vector2(2, 0))
	sensor.poll(0.0)
	assert_true(sensor.inside)
	assert_true(sensor.sight_clear)
	assert_eq(record(sensor).named(RegolithDebugDraw.AI_LOS_CLEAR).size(), 1)
