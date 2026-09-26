@tool
extends Node2D
class_name EnemyPlacement

# one enemy placed once where this node stands, facing its rotation. the
# Scenario sends a SpawnRequest for it over the SpawnBus with
# wait_for_room off, so it lands exactly here, and with the placement's
# extras as request meta. kind picks from the SpawnRequest kinds, kind_name
# overrides it by name so a kind the enum has not got yet ("turret") can be
# authored now: it resolves against SpawnRequest.Kind at runtime and falls
# back to kind with a warning until the enum grows it. scale_cells is a
# size hint, the turret pass reads it off the request meta. the editor
# gizmo draws the enemy's art from its scene when there is one, else a
# labeled circle scale_cells wide

# meta keys on the request the spawner side reads
const META_KIND_NAME := &"kind_name"
const META_SCALE_CELLS := &"scale_cells"
const META_PLACEMENT := &"placement"
const SCENE_DIR := "res://game/scenes/enemies/"

@export var kind := SpawnRequest.Kind.FIGHTER
# empty uses kind, else resolved by name against SpawnRequest.Kind
@export var kind_name: StringName = &""
# size hint in cells, zero for the scene's own size
@export var scale_cells := 0:
	set(value):
		scale_cells = maxi(value, 0)
# gizmo text, the kind when empty
@export var label := ""

signal spawned(node: RegolithSprite)

var node: RegolithSprite
var request: SpawnRequest

# the name this placement spawns under, kind_name or the enum key
func effective_kind_name() -> StringName:
	if kind_name != &"":
		return kind_name

	return StringName(String(SpawnRequest.Kind.keys()[kind]).to_lower())

# the Kind kind_name resolves to, -1 when the enum has no such key
func resolve_kind() -> int:
	if kind_name == &"":
		return kind

	var key := String(kind_name).to_upper()

	if SpawnRequest.Kind.has(key):
		return SpawnRequest.Kind[key]

	return -1

func make_request(ppu: float) -> SpawnRequest:
	var resolved := resolve_kind()

	if resolved < 0:
		push_warning("EnemyPlacement %s: SpawnRequest.Kind has no %s, spawning %s" % [name, kind_name, SpawnRequest.Kind.keys()[kind]])
		resolved = kind

	request = SpawnRequest.enemy(resolved, global_position / ppu)
	request.rotation = global_rotation
	request.wait_for_room = false
	request.set_meta(META_KIND_NAME, effective_kind_name())
	request.set_meta(META_SCALE_CELLS, scale_cells)
	request.set_meta(META_PLACEMENT, name)
	request.spawned.connect(on_spawned)
	return request

func on_spawned(spawned_node: RegolithSprite) -> void:
	node = spawned_node
	node.set_meta(META_KIND_NAME, effective_kind_name())
	node.set_meta(META_SCALE_CELLS, scale_cells)
	spawned.emit(node)

func gizmo_label() -> String:
	return label if label != "" else String(effective_kind_name())

# res://game/scenes/enemies/Enemy<Kind>.tscn for the effective kind
func scene_path() -> String:
	return scene_path_for(effective_kind_name())

# the SpawnRequest.Kind key in lower case: FIGHTER -> "fighter"
static func kind_to_name(kind: int) -> StringName:
	var keys := SpawnRequest.Kind.keys()

	if kind < 0 or kind >= keys.size():
		return &""

	return StringName(String(keys[kind]).to_lower())

static func scene_path_for(kind_name: StringName) -> String:
	return SCENE_DIR + "Enemy" + ScenarioGizmos.pascal_case(String(kind_name)) + ".tscn"

var silhouette_cache: Texture2D
var silhouette_cache_path := ""

# the texture the enemy's scene root carries, read off the packed scene
# state so nothing is instanced in the editor. null with no scene
func silhouette_texture() -> Texture2D:
	var path := scene_path()

	if path == silhouette_cache_path:
		return silhouette_cache

	silhouette_cache_path = path
	silhouette_cache = scene_texture(path)
	return silhouette_cache

# the texture property on the root of a packed scene, off its state so
# nothing is instanced. null with no scene or no texture. the scenario
# preview draws spawn zone enemies with this too
static func scene_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path, "PackedScene"):
		return null

	var scene := load(path) as PackedScene

	if scene == null:
		return null

	var state := scene.get_state()

	if state.get_node_count() == 0:
		return null

	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"texture":
			return state.get_node_property_value(0, i) as Texture2D

	return null
