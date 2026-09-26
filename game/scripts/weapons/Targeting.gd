extends RefCounted
class_name Targeting

# what a homing shot flies at: the first cell along the aim, else the nearest
# sprite around the aim point, enemies before anything else. the target is a
# point in that sprite's local space so it rides along with it. pixels in

static func find(world: RegolithWorld, origin: Vector2, aim_point: Vector2, search_radius: float, exclude: RegolithSprite) -> Dictionary:
	var hit: Dictionary = world.ray_cast(origin, aim_point, exclude)
	if not hit.is_empty():
		var hit_sprite: RegolithSprite = hit["sprite"]
		return {"sprite": hit_sprite, "local_position": hit_sprite.to_local(hit["position"])}

	var best: RegolithSprite = null
	var best_distance := search_radius
	var best_enemy := false

	for candidate in world.query_rect(Rect2(aim_point - Vector2.ONE * search_radius, Vector2.ONE * 2.0 * search_radius)):
		if candidate == exclude:
			continue

		var enemy: bool = candidate.is_in_group("enemy")
		if best_enemy and not enemy:
			continue

		var distance: float = candidate.global_position.distance_to(aim_point)
		if distance < best_distance or (enemy and not best_enemy):
			best = candidate
			best_distance = distance
			best_enemy = enemy

	if best == null:
		return {}

	return {"sprite": best, "local_position": best.to_local(aim_point)}

# the live projectiles of anyone but exclude_shooter within radius_px of
# center. the distance test comes first, it is the cheap one and most of
# the group is far away
static func projectiles_near(center: Vector2, radius_px: float, exclude_shooter) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var tree := Engine.get_main_loop() as SceneTree

	if tree == null:
		return out

	var radius_sq := radius_px * radius_px

	for node in tree.get_nodes_in_group("projectile"):
		var projectile := node as Node2D

		if projectile == null or projectile.global_position.distance_squared_to(center) > radius_sq:
			continue

		if projectile.get("shooter") == exclude_shooter or projectile.get("dead") == true:
			continue

		out.append(projectile)

	return out
