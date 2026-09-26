@tool
extends Node2D
class_name Scenario

# the root of a level layout. its children are zones (AsteroidBeltZone,
# RockFieldZone, SpawnZone), EnemyPlacements and a PlayerStart, laid out in
# the editor with the regolith_scenario plugin. in the game it drives the
# world once: it moves the player to the PlayerStart, frees the sample
# sprites the host scene ships, turns the zones into one RegionProps on a
# Region child (the existing region system does the scatter and the
# orbits, over the SpawnBus and the scene's StableSpawner) and sends the
# placements over the bus itself, in child order, with the placement's
# rotation and meta. nothing here spawns a scene directly.
#
# the level scene inherits Main.tscn and adds a Scenario under it, so the
# world, spawner, camera, background, effects and player come from Main
# without a copy. positions are node pixels, exports on the zones are
# sim units, one unit is one chunk, RegolithWorld.pixels_per_unit() maps

#
# in the editor the Scenario also previews itself: plan() runs the same
# math as start() (Region.plan) and a ScenarioPreview child, made only
# under the editor as an internal node with no owner so it is never saved,
# draws the planned rocks with their generated textures, the spawn zone
# silhouettes and the belt orbit arrows. zones call request_replan() from
# their export setters, the replan runs once, deferred, never per frame

# Main's world runs 2 pixels per cell, 32 cells per chunk. the editor has
# no active world to ask when the scene has none, so this stands in
const DEFAULT_PIXELS_PER_UNIT := 64.0
# preloaded rather than named so the preview can name Scenario back
const ScenarioPreviewScript := preload("res://game/scripts/scenario/ScenarioPreview.gd")

# frees every RegolithSprite beside this node that is not the player, so
# the level starts from its own layout and not the host scene's samples
@export var clear_scene_sprites := true
# run start() on ready, off to call it yourself
@export var auto_start := true
# rocks for zones that name none
@export var rock_props: RockProps:
	set(value):
		rock_props = value
		request_replan()
# editor: draw the planned rocks and enemies where they will spawn. does
# nothing in the game
@export var preview := true:
	set(value):
		preview = value

		if preview_node:
			preview_node.visible = value

signal started
signal placed(placement: EnemyPlacement, node: RegolithSprite)
signal replanned

var region: Region
var requests: Array[SpawnRequest] = []
var is_started := false
var player_placed := false
# the ScenarioPreview, editor only, null in the game
var preview_node: Node2D
var replan_queued := false

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return

	# before the siblings' _ready: a sprite loads its body from the node
	# transform on ready and ignores position writes after, and a sprite
	# with no texture never loads at all
	if clear_scene_sprites:
		clear_siblings()

	place_player()

func _ready() -> void:
	if Engine.is_editor_hint():
		# the plan is in world units, a dragged Scenario replans it
		ScenarioGizmos.watch_transform(self)
		ensure_preview()
		return

	if not player_placed:
		place_player()

	if auto_start:
		start()

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		request_replan()

# preview

# the preview child, made on the first call. the editor calls this from
# _ready, tests call it to drive the preview headless. internal and
# without an owner: get_children() skips it, so do zones() and the scene
# saver, and the game never sees one
func ensure_preview() -> Node2D:
	if preview_node:
		return preview_node

	preview_node = ScenarioPreviewScript.new()
	preview_node.name = "ScenarioPreview"
	preview_node.visible = preview
	add_child(preview_node, false, Node.INTERNAL_MODE_BACK)

	if not child_entered_tree.is_connected(on_child_changed):
		child_entered_tree.connect(on_child_changed)
		child_exiting_tree.connect(on_child_changed)

	request_replan()
	return preview_node

func on_child_changed(_child: Node) -> void:
	request_replan()

# zones call this from their setters. one replan per frame at most, and
# nothing at all without a preview, so the game pays a null check
func request_replan() -> void:
	if preview_node == null or replan_queued:
		return

	replan_queued = true
	replan.call_deferred()

func replan() -> void:
	replan_queued = false

	if preview_node == null or not is_inside_tree():
		return

	preview_node.set_plan(plan(), belt_rings(), pixels_per_unit())
	replanned.emit()

# what start() will ask the Region for, without asking: Region.plan over
# the same props with the same origin, world units
func plan() -> Array[Dictionary]:
	return Region.plan(build_region_props(), global_position / pixels_per_unit())

# the belt rings for the preview's orbit arrows, world units
func belt_rings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ppu := pixels_per_unit()

	for zone in belt_zones():
		out.append({
			"center": zone.global_position / ppu,
			"radius": (zone.inner_radius + zone.outer_radius) * 0.5,
			"angular_speed": zone.angular_speed(),
		})

	return out

# a new seed on every seeded zone, the preview follows. gives the zones
# rerolled
func reroll_seeds() -> Array[Node2D]:
	var out: Array[Node2D] = []

	for child in get_children():
		if child.has_method("reroll_seed"):
			child.reroll_seed()
			out.append(child)

	return out

func clear_siblings() -> void:
	var parent := get_parent()

	if parent == null:
		return

	for sibling in parent.get_children():
		if sibling is RegolithSprite and sibling.is_in_group("regolith") and not sibling.is_in_group("player"):
			sibling.texture = null
			sibling.queue_free()

func place_player() -> void:
	var start := player_start()
	var tree := get_tree()

	if start == null or tree == null:
		return

	var player := tree.get_first_node_in_group("player") as Node2D

	if player == null or not player.is_inside_tree():
		return

	start.apply(player)
	player_placed = true

# lays the level out: one Region for the zones, then the placements
func start() -> void:
	if is_started:
		return

	is_started = true
	requests.clear()

	region = Region.new()
	region.name = "Region"
	region.auto_generate = false
	region.props = build_region_props()
	add_child(region)
	region.generate()

	var ppu := pixels_per_unit()

	for placement in placements():
		var request := placement.make_request(ppu)
		request.spawned.connect(on_placed.bind(placement))
		requests.append(request)
		SpawnBus.send(request)

	started.emit()

func on_placed(node: RegolithSprite, placement: EnemyPlacement) -> void:
	placed.emit(placement, node)

# the RegionProps the zones describe, offsets from this node in units
func build_region_props() -> RegionProps:
	var props := RegionProps.new()

	for zone in belt_zones():
		props.asteroid_belts.append(zone.to_belt(offset_units(zone), rock_props))

	for zone in rock_field_zones():
		props.rock_fields.append(zone.to_rock_field(offset_units(zone), rock_props))

	for zone in spawn_zones():
		props.spawn_zones.append(zone.to_spawn_zone(offset_units(zone)))

	return props

# a child's offset from this node in units, world axes: Region adds it to
# its own origin unrotated
func offset_units(node: Node2D) -> Vector2:
	return (node.global_position - global_position) / pixels_per_unit()

func zones() -> Array[Node2D]:
	var out: Array[Node2D] = []

	for child in get_children():
		if child is AsteroidBeltZone or child is RockFieldZone or child is SpawnZone:
			out.append(child)

	return out

func belt_zones() -> Array[AsteroidBeltZone]:
	var out: Array[AsteroidBeltZone] = []

	for child in get_children():
		if child is AsteroidBeltZone:
			out.append(child)

	return out

func rock_field_zones() -> Array[RockFieldZone]:
	var out: Array[RockFieldZone] = []

	for child in get_children():
		if child is RockFieldZone:
			out.append(child)

	return out

func spawn_zones() -> Array[SpawnZone]:
	var out: Array[SpawnZone] = []

	for child in get_children():
		if child is SpawnZone:
			out.append(child)

	return out

func placements() -> Array[EnemyPlacement]:
	var out: Array[EnemyPlacement] = []

	for child in get_children():
		if child is EnemyPlacement:
			out.append(child)

	return out

# the first PlayerStart child, null when the level has none
func player_start() -> PlayerStart:
	for child in get_children():
		if child is PlayerStart:
			return child

	return null

func pixels_per_unit() -> float:
	return world_pixels_per_unit(self)

# the units to pixels scale for a node: its Scenario's, else the world's
static func pixels_per_unit_of(node: Node) -> float:
	var scenario := scenario_of(node)
	return scenario.pixels_per_unit() if scenario else world_pixels_per_unit(node)

# the Scenario a node sits under, itself included, null outside one
static func scenario_of(node: Node) -> Scenario:
	var at := node

	while at:
		if at is Scenario:
			return at

		at = at.get_parent()

	return null

# in the game the active world answers, as everywhere else. the editor has
# no active world, so the edited scene is searched for one and Main's
# scale stands in when there is none
static func world_pixels_per_unit(from: Node) -> float:
	if not Engine.is_editor_hint():
		return RegolithWorld.pixels_per_unit()

	var world := find_edited_world(from)
	return world.pixels_per_cell * RegolithWorld.CELLS_PER_CHUNK if world else DEFAULT_PIXELS_PER_UNIT

static func find_edited_world(from: Node) -> RegolithWorld:
	var tree := from.get_tree()
	var root: Node = tree.edited_scene_root if tree else null

	if root == null:
		root = from.owner if from.owner else from

	if root is RegolithWorld:
		return root

	var found := root.find_children("*", "RegolithWorld", true, false)
	return found[0] as RegolithWorld if not found.is_empty() else null
