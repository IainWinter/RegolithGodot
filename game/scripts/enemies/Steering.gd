class_name Steering
extends RefCounted

# static helpers shared by the enemy ai. sim units throughout, one unit is
# one chunk, pixels only at the world boundary

static func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

static func cell_pixels() -> float:
	return RegolithWorld.pixels_per_cell()

static func wrap_angle(angle: float) -> float:
	return fposmod(angle + PI, TAU) - PI

static func turn_toward(angle: float, target_angle: float, max_turn: float) -> float:
	return angle + clampf(angle_difference(angle, target_angle), -max_turn, max_turn)

static func seek(position: Vector2, velocity: Vector2, goal: Vector2, max_speed: float, max_accel: float, delta: float) -> Vector2:
	var to_goal := goal - position
	var wanted := to_goal.limit_length(max_speed)
	return velocity + (wanted - velocity).limit_length(max_accel * delta)

static func find_player(tree: SceneTree) -> RegolithSprite:
	var player := tree.get_first_node_in_group("player") as RegolithSprite
	return player if player and is_instance_valid(player) and not player.is_queued_for_deletion() else null

static func prune_dead(list: Array) -> void:
	for i in range(list.size() - 1, -1, -1):
		var node = list[i]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			list.remove_at(i)

# cell size of a sprite, the texture stands in before it is loaded so the
# editor gizmos see the same hull the game will
static func cell_count(sprite: RegolithSprite) -> Vector2:
	if sprite.is_loaded():
		return Vector2(sprite.get_cell_count())

	return sprite.texture.get_size() if sprite.texture else Vector2.ZERO

static func half_extent_units(sprite: RegolithSprite) -> Vector2:
	return cell_count(sprite) * 0.5 / RegolithWorld.CELLS_PER_CHUNK

# a point on the sprite's hull, -1..1 with y up, in world pixels or units
static func hull_point_pixels(sprite: RegolithSprite, p: Vector2) -> Vector2:
	return sprite.to_global(Vector2(p.x, -p.y) * cell_count(sprite) * 0.5 * cell_pixels())

static func hull_point_units(sprite: RegolithSprite, p: Vector2) -> Vector2:
	return hull_point_pixels(sprite, p) / ppu()

static func sprite_radius_units(sprite: RegolithSprite) -> float:
	return half_extent_units(sprite).length()


static func sprites_near(world: RegolithWorld, center: Vector2, radius: float) -> Array:
	var r := radius * ppu()
	return world.query_rect(Rect2(center * ppu() - Vector2.ONE * r, Vector2.ONE * 2.0 * r))

static func nearest(point: Vector2, nodes: Array, max_distance := INF) -> Node2D:
	var best: Node2D = null
	var best_distance := max_distance * max_distance
	var scale := ppu()

	for node in nodes:
		var d: float = (node.global_position / scale).distance_squared_to(point)
		if d < best_distance:
			best_distance = d
			best = node

	return best

static func wrap_from(angle: float, lo: float) -> float:
	return lo + fposmod(angle - lo, TAU)

static func dampen(v: Vector2, damping: float, delta: float) -> Vector2:
	return v * clampf(1.0 - damping * delta, 0.0, 1.0)

static func random_outside_box(extent: Vector2, padding: Vector2) -> Vector2:
	var area_horizontal := 2.0 * extent.x * padding.y
	var area_vertical := 2.0 * extent.y * padding.x
	var area_corner := padding.x * padding.y
	var pick := randf() * (area_horizontal + area_vertical + area_corner)
	var p: Vector2

	if pick < area_horizontal:
		p = Vector2(randf_range(-extent.x, extent.x), randf_range(-padding.y, padding.y))
		p.y += extent.y if p.y > 0.0 else -extent.y
	elif pick < area_horizontal + area_vertical:
		p = Vector2(randf_range(-padding.x, padding.x), randf_range(-extent.y, extent.y))
		p.x += extent.x if p.x > 0.0 else -extent.x
	else:
		p = Vector2(randf_range(-padding.x, padding.x), randf_range(-padding.y, padding.y))
		p.x += extent.x if p.x > 0.0 else -extent.x
		p.y += extent.y if p.y > 0.0 else -extent.y

	return p

static func random_in_box(center: Vector2, half_size: Vector2, angle: float) -> Vector2:
	var local := Vector2(randf_range(-half_size.x, half_size.x), randf_range(-half_size.y, half_size.y))
	return center + local.rotated(angle)

static func random_in_circle(radius: float) -> Vector2:
	return Vector2.from_angle(randf() * TAU) * randf() * radius

static func closest_point_on_polygon(points: PackedVector2Array, query: Vector2) -> Vector2:
	if points.is_empty():
		return query

	var best := points[0]
	var best_distance := INF

	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var candidate := Geometry2D.get_closest_point_to_segment(query, a, b)
		var d := candidate.distance_squared_to(query)

		if d < best_distance:
			best_distance = d
			best = candidate

	return best

static func camera_half_extents(node: Node) -> Vector2:
	var viewport := node.get_viewport()
	var camera := viewport.get_camera_2d() if viewport else null

	if camera:
		var size := viewport.get_visible_rect().size / camera.zoom
		return size * 0.5 / ppu()

	var height := float(RegolithWorld.CAMERA_HEIGHT)
	return Vector2(height * 16.0 / 9.0, height) * 0.5

static func camera_center(node: Node, fallback: Vector2) -> Vector2:
	var viewport := node.get_viewport()
	var camera := viewport.get_camera_2d() if viewport else null

	if camera:
		return camera.get_screen_center_position() / ppu()

	return fallback
