extends RefCounted
class_name CharacterRegistry

# the Character resources by id, loaded once from every .tres under
# res://game/config/characters, and the rules that turn a node into a
# speaker for Dialog.say_from:
#   1. a `character` property holding a Character
#   2. a `character_id` meta (StringName or String)
#   3. the node's `ai_class` (the lua class name of a scripted enemy)
#   4. the node's script class_name, walking up the base scripts, with the
#      Enemy prefix dropped and snake cased: EnemyBossCompass -> boss_compass,
#      Player -> player
# static so tests and tools reach it without a node

const DIR := "res://game/config/characters"
const CLASS_PREFIX := "Enemy"

static var characters: Dictionary = {}
static var loaded := false

static func all() -> Array[Character]:
	load_all()
	var out: Array[Character] = []
	for id in characters:
		out.append(characters[id])
	return out

static func find(id: StringName) -> Character:
	load_all()
	return characters.get(id)

static func has(id: StringName) -> bool:
	load_all()
	return characters.has(id)

# the character for an id, a placeholder named after the id when none exists
static func find_or_placeholder(id: StringName) -> Character:
	var character := find(id)
	return character if character != null else Character.placeholder(id)

static func reload() -> void:
	loaded = false
	characters.clear()
	load_all()

static func load_all() -> void:
	if loaded:
		return

	loaded = true

	for file in DirAccess.get_files_at(DIR):
		# exports rename .tres to .tres.remap
		var file_name := file.trim_suffix(".remap")

		if file_name.get_extension() != "tres":
			continue

		var character := load("%s/%s" % [DIR, file_name]) as Character

		if character == null:
			push_warning("CharacterRegistry: %s is not a Character" % file_name)
			continue

		if character.id == &"":
			character.id = StringName(file_name.get_basename())

		characters[character.id] = character

# node lookup

static func for_node(node: Object) -> Character:
	var id := id_for_node(node)
	return find(id) if id != &"" else null

static func id_for_node(node: Object) -> StringName:
	if node == null or not is_instance_valid(node):
		return &""

	if "character" in node and node.character is Character:
		return node.character.id

	if node.has_meta(&"character_id"):
		return StringName(node.get_meta(&"character_id"))

	if "ai_class" in node and String(node.ai_class) != "":
		var from_lua := StringName(node.ai_class)
		if has(from_lua):
			return from_lua

	var script: Script = node.get_script()

	while script != null:
		var id := id_for_class_name(script.get_global_name())
		if id != &"" and has(id):
			return id
		script = script.get_base_script()

	return id_for_class_name(node.get_class())

# EnemyBossCompass -> boss_compass, Player -> player, "" -> ""
static func id_for_class_name(class_name_: String) -> StringName:
	if class_name_ == "":
		return &""

	return StringName(class_name_.trim_prefix(CLASS_PREFIX).to_snake_case())
