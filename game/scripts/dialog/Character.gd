extends Resource
class_name Character

# who is talking in the dialog window. one .tres per ship under
# res://game/config/characters, found by id through CharacterRegistry. the
# id is what scripts say lines as (Dialog.say(&"fighter", ...)), and what a
# node resolves to (see CharacterRegistry.for_node): the lua class name of
# a scripted enemy or its gdscript class with the Enemy prefix dropped and
# snake cased, EnemyBossCompass -> boss_compass

@export var id: StringName = &""
@export var display_name := ""
# the face in the framed square at the left of the window, 32x32 pixel art
@export var icon: Texture2D
# tints the name and the icon frame
@export var color := Color.WHITE
# a Sound name for the talk blip under the typewriter, &"" for silent
@export var voice: StringName = &""
# typewriter speed in characters per second
@export var text_speed := 40.0

# a stand in for an id without a .tres, so a line from an unknown speaker
# still shows with its id as the name
static func placeholder(for_id: StringName) -> Character:
	var character := Character.new()
	character.id = for_id
	character.display_name = String(for_id).capitalize()
	return character
