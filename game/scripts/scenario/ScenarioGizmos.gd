class_name ScenarioGizmos
extends RefCounted

# geometry for the scenario editor gizmos, pure functions so they are unit
# tested without the editor. every point is in whatever frame the caller
# uses (world pixels for the handles, overlay pixels for the hit tests),
# nothing here knows about units. the plugin owns colors and drawing

# overlay pixels a handle answers to
const HANDLE_RADIUS := 7.0

# a ring's four drag handles: right, down, left, up
static func ring_handles(center: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
		center + Vector2(0.0, -radius),
	])

# the index of the first handle within radius of point, -1 for none
static func hit_handle(point: Vector2, handles: PackedVector2Array, radius := HANDLE_RADIUS) -> int:
	for i in handles.size():
		if point.distance_to(handles[i]) <= radius:
			return i

	return -1

# the ring radius a drag to point asks for
static func radius_from_drag(center: Vector2, point: Vector2) -> float:
	return center.distance_to(point)

# a box's eight handles: the four corners then the four edge midpoints, in
# the box frame rotated by angle. half is the half size
static func rect_handles(center: Vector2, half: Vector2, angle := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()

	for dir in rect_handle_dirs():
		out.append(center + (dir * half).rotated(angle))

	return out

static func rect_handle_dirs() -> Array[Vector2]:
	return [
		Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1),
		Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0),
	]

# the half size a drag of handle index to point asks for: corners set both
# axes, edge handles only theirs. the box stays centered on center
static func half_from_drag(center: Vector2, angle: float, index: int, point: Vector2, old_half: Vector2) -> Vector2:
	var local := (point - center).rotated(-angle)
	var dirs := rect_handle_dirs()

	if index < 0 or index >= dirs.size():
		return old_half

	var dir := dirs[index]
	var half := old_half

	if dir.x != 0.0:
		half.x = absf(local.x)

	if dir.y != 0.0:
		half.y = absf(local.y)

	return half

# the four corners of a box, for outlines
static func rect_corners(center: Vector2, half: Vector2, angle := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()

	for dir in rect_handle_dirs().slice(0, 4):
		out.append(center + (dir * half).rotated(angle))

	return out

# an arrow from at along angle: shaft end and the two head barbs, in that
# order so [0] is the tip
static func arrow_points(at: Vector2, angle: float, length: float, head := 0.25) -> PackedVector2Array:
	var dir := Vector2.from_angle(angle)
	var tip := at + dir * length
	var barb := length * head

	return PackedVector2Array([
		tip,
		tip - dir.rotated(0.5) * barb,
		tip - dir.rotated(-0.5) * barb,
	])

# where a sprite's art lands in its node's local pixels: the origin is the
# center of the grid padded to whole chunks and the art fills from the
# grid's top left, so a 13x13 sprite sits off center. see the
# sprite-origin convention in RegolithSprite
static func padded_art_rect(texture_size: Vector2, cell_pixels: float, cells_per_chunk := RegolithWorld.CELLS_PER_CHUNK) -> Rect2:
	var chunks := Vector2(ceilf(texture_size.x / cells_per_chunk), ceilf(texture_size.y / cells_per_chunk))
	var padded := chunks * cells_per_chunk * cell_pixels
	return Rect2(-padded * 0.5, texture_size * cell_pixels)

# the scale that fits texture_size inside a square of cells on its larger
# side, 1 when cells is zero
static func fit_scale(texture_size: Vector2, cells: int) -> float:
	var largest := maxf(texture_size.x, texture_size.y)

	if cells <= 0 or largest <= 0.0:
		return 1.0

	return float(cells) / largest

# "boss_compass" -> "BossCompass", for kind names to scene names
static func pascal_case(snake: String) -> String:
	var out := ""

	for part in snake.split("_", false):
		out += part.substr(0, 1).to_upper() + part.substr(1).to_lower()

	return out

# preview plumbing shared by the zones

# tells the nearest node above with request_replan (the Scenario) to
# replan its preview. a zone outside a Scenario, or one still loading with
# no parent yet, changes nothing. the Scenario answers with a null check in
# the game, so this costs nothing there
static func mark_dirty(node: Node) -> void:
	var at := node.get_parent()

	while at:
		if at.has_method("request_replan"):
			at.request_replan()
			return

		at = at.get_parent()

# a zone dragged in the editor moves its rocks: the local transform
# notification feeds mark_dirty. only under the editor, the game never
# moves a zone
static func watch_transform(node: Node2D) -> void:
	if Engine.is_editor_hint():
		node.set_notify_local_transform(true)

# a new seed that is never the old one, six digits so it reads in the
# inspector
static func fresh_seed(old: int) -> int:
	var fresh := randi_range(1, 999999)

	while fresh == old:
		fresh = randi_range(1, 999999)

	return fresh
