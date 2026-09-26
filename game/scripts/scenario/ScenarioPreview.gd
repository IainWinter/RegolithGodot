@tool
extends Node2D
class_name ScenarioPreview

# editor only: what a Scenario's zones will spawn, drawn where it will
# land before the game runs. the Scenario makes one under the editor as an
# internal child with no owner (Scenario.ensure_preview), so it is never
# saved and never exists in the game. it keeps the plan Region.plan gave
# and one ImageTexture per planned rock, generated a few per frame from
# the rock's description (RockGenerator.generate_described gives the very
# pixels the spawner loads) and kept by description key until a plan no
# longer names it, so a moved zone redraws at once and a rerolled seed
# only builds the rocks that changed. enemies from spawn zones draw as a
# faint silhouette of their scene's art, belts get orbit arrows. world
# pixels are the plan's units times pixels_per_unit

const BUILD_BUDGET_MSEC := 6
const ARROWS_PER_BELT := 8
const ARROW_UNITS := 1.2
const ROCK_TINT := Color(1.0, 1.0, 1.0, 0.9)
const ROCK_PENDING := Color(1.0, 0.65, 0.2, 0.5)
const ENEMY_TINT := Color(1.0, 0.55, 0.55, 0.45)
const ARROW_COLOR := Color(1.0, 0.65, 0.2, 0.6)
const LINE_WIDTH := 2.0

signal built

var items: Array[Dictionary] = []
# {center, radius (units), angular_speed}
var belts: Array[Dictionary] = []
# describe_key -> ImageTexture
var textures := {}
# rock items whose texture is not made yet
var queue: Array[Dictionary] = []
# kind -> Texture2D, null for kinds with no scene art
var silhouettes := {}
var pixels_per_unit := 64.0

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	set_process(false)

# the plan to draw, from Region.plan, with the belt rings for the arrows
func set_plan(new_items: Array[Dictionary], new_belts: Array[Dictionary], ppu: float) -> void:
	items = new_items
	belts = new_belts
	pixels_per_unit = ppu
	queue.clear()

	var wanted := {}
	# config instance id -> pixel_key, the rocks of a zone share a config
	var config_keys := {}

	for item in items:
		if item["type"] != Region.PLAN_ROCK:
			continue

		var config: RockProps = item["rock"]["config"]
		var config_id := config.get_instance_id()

		if not config_keys.has(config_id):
			config_keys[config_id] = config.pixel_key()

		var key := RockGenerator.describe_key(item["rock"], config_keys[config_id])
		item["key"] = key

		if not wanted.has(key) and not textures.has(key):
			queue.append(item)

		wanted[key] = true

	for key in textures.keys():
		if not wanted.has(key):
			textures.erase(key)

	set_process(not queue.is_empty())
	queue_redraw()

func _process(_delta: float) -> void:
	build_pending(BUILD_BUDGET_MSEC)

# makes textures off the queue until the budget is spent, all of them for a
# negative budget. gives the number made
func build_pending(budget_msec := -1) -> int:
	var start := Time.get_ticks_msec()
	var made := 0

	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var key: String = item["key"]

		if not textures.has(key):
			var images := RockGenerator.generate_described(item["rock"])
			textures[key] = ImageTexture.create_from_image(images["color"])
			made += 1

		if budget_msec >= 0 and Time.get_ticks_msec() - start >= budget_msec:
			break

	if queue.is_empty():
		set_process(false)
		built.emit()

	if made > 0:
		queue_redraw()

	return made

func pending_count() -> int:
	return queue.size()

func texture_count() -> int:
	return textures.size()

func texture_of(item: Dictionary) -> Texture2D:
	return textures.get(item.get("key", ""))

# drops every rock texture, the next set_plan builds them again
func clear_cache() -> void:
	textures.clear()
	silhouettes.clear()
	queue_redraw()

func rock_count() -> int:
	return items.filter(func(item: Dictionary) -> bool: return item["type"] == Region.PLAN_ROCK).size()

func enemy_count() -> int:
	return items.filter(func(item: Dictionary) -> bool: return item["type"] == Region.PLAN_ENEMY).size()

func silhouette_for(kind: int) -> Texture2D:
	if silhouettes.has(kind):
		return silhouettes[kind]

	var texture := EnemyPlacement.scene_texture(EnemyPlacement.scene_path_for(EnemyPlacement.kind_to_name(kind)))
	silhouettes[kind] = texture
	return texture

func _draw() -> void:
	var ppu := pixels_per_unit
	var cell := ppu / RegolithWorld.CELLS_PER_CHUNK
	var to_local := global_transform.affine_inverse()

	for item in items:
		var is_rock: bool = item["type"] == Region.PLAN_ROCK
		var rotation_of: float = item["rock"]["rotation"] if is_rock else item.get("rotation", 0.0)
		draw_set_transform_matrix(to_local * Transform2D(rotation_of, item["position"] * ppu))

		if is_rock:
			# a rock is a whole number of chunks, so the padded grid is the art
			# and the origin is its center
			var size: Vector2 = Vector2.ONE * item["chunks"] * ppu
			var texture := texture_of(item)

			if texture:
				draw_texture_rect(texture, Rect2(-size * 0.5, size), false, ROCK_TINT)
			else:
				draw_arc(Vector2.ZERO, size.x * 0.45, 0.0, TAU, 32, ROCK_PENDING, LINE_WIDTH, true)
		else:
			var texture := silhouette_for(item["kind"])

			if texture:
				draw_texture_rect(texture, ScenarioGizmos.padded_art_rect(texture.get_size(), cell), false, ENEMY_TINT)
			else:
				draw_arc(Vector2.ZERO, 0.5 * ppu, 0.0, TAU, 24, ENEMY_TINT, LINE_WIDTH, true)

	draw_set_transform_matrix(to_local)

	for belt in belts:
		draw_orbit_arrows(belt["center"] * ppu, belt["radius"] * ppu, belt["angular_speed"], ARROW_UNITS * ppu)

	draw_set_transform_matrix(Transform2D.IDENTITY)

# arrows along the ring pointing the way the rocks will go, none for a
# belt that stands still
func draw_orbit_arrows(center: Vector2, radius: float, angular_speed: float, length: float) -> void:
	if angular_speed == 0.0 or radius <= 0.0:
		return

	var turn := PI * 0.5 if angular_speed > 0.0 else -PI * 0.5

	for i in ARROWS_PER_BELT:
		var angle := TAU * i / ARROWS_PER_BELT
		var at := center + Vector2.from_angle(angle) * radius
		var arrow := ScenarioGizmos.arrow_points(at, angle + turn, length)
		draw_line(at, arrow[0], ARROW_COLOR, LINE_WIDTH)
		draw_line(arrow[0], arrow[1], ARROW_COLOR, LINE_WIDTH)
		draw_line(arrow[0], arrow[2], ARROW_COLOR, LINE_WIDTH)
