extends Node

# the Dialog autoload: voice lines from the ships to the player. say(id,
# text) queues a line for a Character (see CharacterRegistry), the window
# (DialogWindow, layer 15, under the menus at 20) shows one at a time in
# order: it slides in over FADE seconds, reveals the text at the speaker's
# text_speed with a soft blip on the character's voice sound (played on the
# Menu bus so it stays clear), holds for the line's duration (from its
# length when none is given), then moves to the next, and slides out when
# the queue is empty. higher priority lines go ahead of lower ones already
# waiting, never ahead of the one on screen. the same speaker repeating the
# same line within COALESCE seconds is dropped, as is a line already
# waiting. interrupt(id) drops that speaker's waiting lines and cuts their
# current one short, clear() drops everything.
#
# this node runs always so lines can be queued from anywhere, but the
# dialog is a game effect: advance() is skipped while the tree is paused,
# so the typewriter freezes under the pause menu and the window stays put
# under it. say_from(node, text) resolves the speaker from a node for the
# lua host and any gameplay script (a character property, a character_id
# meta, the ai_class, or the class name). the time driven steps live in
# advance(dt) so tests can run the whole thing without frames

signal line_started(character: Character, text: String)
signal line_finished(character: Character, text: String)
signal queue_empty

const WINDOW := preload("res://game/scenes/dialog/DialogWindow.tscn")

enum Phase { IDLE, OPENING, TYPING, HOLDING, CLOSING }

# slide in and out, seconds
const FADE := 0.15
# the hold after the reveal when say gets no duration: base plus per character
const HOLD_BASE := 1.2
const HOLD_PER_CHAR := 0.04
# the same speaker saying the same words again this soon is dropped
const COALESCE := 6.0
# blips come at most this often and this loud
const BLIP_INTERVAL := 0.06
const BLIP_VOLUME_DB := -10.0

var window: DialogWindow
var phase := Phase.IDLE
# the waiting lines, front first. each {character, text, duration, priority}
var queue: Array[Dictionary] = []
# the line on screen, empty when none
var current: Dictionary = {}
# typewriter progress in characters, fractional
var revealed := 0.0
var hold_left := 0.0
var blip_left := 0.0
# blips played for the line on screen, and the player of the last one
var blips := 0
var last_blip: AudioStreamPlayer
# game seconds, for the coalescing memory
var clock := 0.0
# "id\ntext" -> the clock when it was last said
var recent: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	window = WINDOW.instantiate()
	add_child(window)

func _process(delta: float) -> void:
	# a game effect: it freezes with the world under the pause menu
	if get_tree().paused:
		return

	advance(delta)

# api

# queues a line. false when it was dropped: coalesced with a recent or
# waiting copy, or empty
func say(speaker_id: StringName, text: String, duration := -1.0, priority := 0) -> bool:
	return say_as(CharacterRegistry.find_or_placeholder(speaker_id), text, duration, priority)

# the speaker resolved from a node, see CharacterRegistry.id_for_node
func say_from(node: Node, text: String, duration := -1.0, priority := 0) -> bool:
	var character := CharacterRegistry.for_node(node)

	if character == null:
		# no .tres for it, the node's name stands in
		character = Character.placeholder(StringName(node.name) if is_instance_valid(node) else &"unknown")

	return say_as(character, text, duration, priority)

func say_as(character: Character, text: String, duration := -1.0, priority := 0) -> bool:
	text = text.strip_edges()

	if character == null or text == "":
		return false

	if is_coalesced(character.id, text):
		return false

	recent[recent_key(character.id, text)] = clock
	var line := {"character": character, "text": text, "duration": duration, "priority": priority}
	queue.insert(insert_index(priority), line)

	if phase == Phase.IDLE or phase == Phase.CLOSING:
		begin_next()

	return true

# drops the speaker's waiting lines and ends their line on screen
func interrupt(speaker_id: StringName) -> void:
	var kept: Array[Dictionary] = []

	for line in queue:
		if line["character"].id != speaker_id:
			kept.append(line)

	queue = kept

	if not current.is_empty() and current["character"].id == speaker_id:
		finish_line()

# drops everything, the window slides out
func clear() -> void:
	queue.clear()

	if not current.is_empty():
		finish_line()

# forgets the recent lines so anything may be said again at once
func forget() -> void:
	recent.clear()

func is_showing() -> bool:
	return not current.is_empty()

func current_character() -> Character:
	return current.get("character")

func current_text() -> String:
	return current.get("text", "")

func queued_texts() -> Array[String]:
	var out: Array[String] = []
	for line in queue:
		out.append(line["text"])
	return out

# the hold after the reveal for a line, from its length when none was given
static func hold_for(text: String, duration: float) -> float:
	if duration >= 0.0:
		return duration
	return HOLD_BASE + HOLD_PER_CHAR * text.length()

# the time driven steps: the slide in, the typewriter, the hold, the slide out

func advance(delta: float) -> void:
	clock += delta

	match phase:
		Phase.OPENING:
			window.shown += delta / FADE
			if window.shown >= 1.0:
				phase = Phase.TYPING
		Phase.TYPING:
			advance_typewriter(delta)
		Phase.HOLDING:
			hold_left -= delta
			if hold_left <= 0.0:
				finish_line()
		Phase.CLOSING:
			window.shown -= delta / FADE
			if window.shown <= 0.0:
				phase = Phase.IDLE
				queue_empty.emit()

func advance_typewriter(delta: float) -> void:
	var character: Character = current["character"]
	var text: String = current["text"]
	var before := window.revealed()
	revealed += delta * maxf(character.text_speed, 1.0)
	var count := mini(int(revealed), text.length())
	window.set_revealed(count)
	blip_left -= delta

	if count > before and blip_left <= 0.0 and has_letters(text.substr(before, count - before)):
		blip(character)

	if count >= text.length():
		phase = Phase.HOLDING
		hold_left = hold_for(text, current["duration"])

static func has_letters(part: String) -> bool:
	return part.strip_edges() != ""

# the talk blip, soft, on the menu bus so the pause slide's low pass on
# the world bus never muffles it
func blip(character: Character) -> void:
	blip_left = BLIP_INTERVAL

	if character.voice == &"" or not Sound.has(character.voice):
		return

	blips += 1
	last_blip = Sound.play(character.voice, false, BLIP_VOLUME_DB)

	if last_blip != null:
		last_blip.bus = Sound.MENU_BUS

func begin_next() -> void:
	current = queue.pop_front()
	revealed = 0.0
	blip_left = 0.0
	blips = 0
	window.show_line(current["character"], current["text"])
	phase = Phase.TYPING if window.shown >= 1.0 else Phase.OPENING
	line_started.emit(current["character"], current["text"])

# the line on screen is done: the next one takes the window, or it slides out
func finish_line() -> void:
	if current.is_empty():
		return

	var done := current
	current = {}
	window.set_revealed(done["text"].length())
	line_finished.emit(done["character"], done["text"])

	if not queue.is_empty():
		begin_next()
	else:
		phase = Phase.CLOSING

# coalescing and ordering

static func recent_key(id: StringName, text: String) -> String:
	return "%s\n%s" % [id, text]

func is_coalesced(id: StringName, text: String) -> bool:
	if not current.is_empty() and current["character"].id == id and current["text"] == text:
		return true

	for line in queue:
		if line["character"].id == id and line["text"] == text:
			return true

	var key := recent_key(id, text)
	return recent.has(key) and clock - recent[key] < COALESCE

# after every waiting line of the same or higher priority
func insert_index(priority: int) -> int:
	var index := queue.size()

	while index > 0 and queue[index - 1]["priority"] < priority:
		index -= 1

	return index
