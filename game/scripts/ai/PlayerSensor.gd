@tool
class_name PlayerSensor
extends Sensor

# tells the script about the player: player_seen when they come within
# radius, player_update every update_interval while they stay, player_lost
# when they leave or die. each carries the player node, position (the node
# origin), center (their center of mass), velocity, distance and whether
# the host has a clear line to them. the kinds match
# res://game/lua/message_types.lua
#
# gizmos: the radius circle (AI) in the editor and in game, and at runtime
# a tick on the circle toward the tracked player (AI) plus a line to them
# while inside the radius, solid AI_LOS_CLEAR when the last sight check was
# clear, dashed AI_LOS_BLOCKED when it was blocked

const PLAYER_SEEN := "player_seen"
const PLAYER_UPDATE := "player_update"
const PLAYER_LOST := "player_lost"

@export var radius := 30.0:
	set(value):
		radius = maxf(value, 0.0)
		gizmos_changed()
@export var update_interval := 0.1
# only count the player as seen with a clear line of sight
@export var require_line_of_sight := false

var player: RegolithSprite
var inside := false
var timer := 0.0
# result of the last line of sight cast, kept for the gizmo
var sight_clear := true
# the player never blocks the line to themselves
var sight_ignore_groups := PackedStringArray(["player"])

func find_player() -> RegolithSprite:
	if not Steering.alive(player):
		player = Steering.find_player(get_tree())

	return player

func in_sight(from: Vector2, to: Vector2) -> bool:
	var world := RegolithWorld.active()
	var sprite := host()

	if world == null or sprite == null:
		return true

	var ppu := RegolithWorld.pixels_per_unit()
	return world.has_line_of_sight(from * ppu, to * ppu, sprite, sight_ignore_groups)

# casts and remembers the result for the gizmo
func check_sight(from: Vector2, to: Vector2) -> bool:
	sight_clear = in_sight(from, to)
	return sight_clear

func poll(delta: float) -> void:
	var target := find_player()

	if target == null:
		lose()
		return

	var from := host_pos()
	var ppu := RegolithWorld.pixels_per_unit()
	var position: Vector2 = target.global_position / ppu
	var distance := from.distance_to(position)
	var seen := distance <= radius
	# the line is cast at most once a poll: here when it gates seen, else
	# only on the polls that report
	var checked := false
	var clear := false

	if seen and require_line_of_sight:
		clear = check_sight(from, position)
		checked = true
		seen = clear

	if not seen:
		lose()
		return

	timer -= delta
	var kind := ""

	if not inside:
		inside = true
		timer = update_interval
		kind = PLAYER_SEEN
	elif timer <= 0.0:
		timer = update_interval
		kind = PLAYER_UPDATE

	if kind == "":
		return

	if not checked:
		clear = check_sight(from, position)

	report(kind, {
		"player": target,
		"position": position,
		"center": target.get_center_of_mass() / ppu if target.is_loaded() else position,
		"velocity": target.linear_velocity,
		"distance": distance,
		"in_sight": clear,
	})

func lose() -> void:
	if inside:
		inside = false
		report(PLAYER_LOST)

# the editor plugin repaints its overlay every editor frame, a redraw on the
# host makes sure an inspector edit wakes the viewport for that frame
func gizmos_changed() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return

	var canvas := get_parent() as CanvasItem

	if canvas:
		canvas.queue_redraw()

# world sim units, lifted to host-local pixels by Steering.gz_*
func draw_gizmos(g: RegolithGizmos) -> void:
	var sprite := host()

	if sprite == null:
		return

	var ppu := Steering.ppu()
	var to_local := sprite.global_transform.affine_inverse()
	var center := sprite.global_position / ppu
	Steering.gz_circle(g, to_local, ppu, center, radius, Color(1.0, 0.85, 0.2), RegolithDebugDraw.AI, 32)

	if Engine.is_editor_hint() or not Steering.alive(player):
		return

	var target: Vector2 = player.global_position / ppu
	var offset := target - center
	var distance := offset.length()

	if distance < 0.0001:
		return

	var dir := offset / distance
	var tick := minf(0.5, radius * 0.5)
	Steering.gz_line(g, to_local, ppu, center + dir * (radius - tick), center + dir * (radius + tick), Color(1.0, 0.85, 0.2), RegolithDebugDraw.AI)

	if distance > radius:
		return

	if sight_clear:
		Steering.gz_line(g, to_local, ppu, center, target, Color(0.1, 1.0, 0.1), RegolithDebugDraw.AI_LOS_CLEAR)
	else:
		Steering.gz_dashed(g, to_local, ppu, center, target, 0.5, Color(1.0, 0.1, 0.1), RegolithDebugDraw.AI_LOS_BLOCKED)
