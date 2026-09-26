class_name AiStateMachine
extends RefCounted

# the state machine behind one scripted enemy. the lua class registers its
# states (self:register_state(name, {enter, update, exit})) and asks for
# transitions (self:transition(name)); the functions stay in lua on the
# instance, this side keeps the names, the current state, how long it has
# been there, the previous one and a log of the last transitions, so the
# debug panel and tests can look at it. each ai tick the host calls tick(dt)
# and the machine runs the current state's update through the instance's
# __state_call(phase, name, dt), which names the state in any error.
#
# a transition asked for while a lua call is running (from enter, update,
# exit, or from on_message/update while the host holds the machine) is
# pending and applies right after that call returns, so update finishes
# before exit runs. asked for while idle it applies at once. asked for
# before bind() it waits for the bind. a transition to the current state
# is a no-op

signal state_changed(from: String, to: String)

const LOG_SIZE := 16
const MAX_CHAIN := 8

var lua: RegolithLua
var ai_id := 0
# for messages, the host's name and class
var label := ""

var states := PackedStringArray()
var current := ""
var previous := ""
var pending := ""
var time_in_state := 0.0
# seconds of ticks so far, what the log stamps
var clock := 0.0
var ticks := 0
var last_error := ""

# {from, to, at, tick}, oldest first
var transitions: Array[Dictionary] = []

var hold_count := 0
var flushing := false

# the lua state and instance the states live on. applies whatever was
# asked for before
func bind(state: RegolithLua, id: int) -> void:
	lua = state
	ai_id = id
	flush()

func unbind() -> void:
	lua = null
	ai_id = 0

func bound() -> bool:
	return lua != null and ai_id != 0

# states

func register_state(name: String) -> bool:
	if name == "":
		last_error = "register_state: empty name"
		return false

	if not states.has(name):
		states.append(name)

	return true

func has_state(name: String) -> bool:
	return states.has(name)

func get_state() -> String:
	return current

func get_previous_state() -> String:
	return previous

func get_pending_state() -> String:
	return pending

func get_states() -> PackedStringArray:
	return states.duplicate()

func get_time_in_state() -> float:
	return time_in_state

func get_transition_log() -> Array[Dictionary]:
	return transitions.duplicate()

func get_last_error() -> String:
	return last_error

# false when the state was never registered, the lua side raises on that
func transition(to: String) -> bool:
	if not states.has(to):
		last_error = "transition to unregistered state '%s'" % to
		return false

	pending = to

	if hold_count == 0 and bound():
		flush()

	return true

# the host wraps its own lua calls in hold/release so transitions asked
# for from on_message or update wait for the call to return
func hold() -> void:
	hold_count += 1

func release() -> void:
	hold_count = maxi(hold_count - 1, 0)

	if hold_count == 0 and bound():
		flush()

func tick(delta: float) -> void:
	ticks += 1
	clock += delta

	if not bound():
		return

	flush()

	if current == "":
		return

	time_in_state += delta
	call_state("update", current, delta)
	flush()

# applies pending transitions, and the ones they ask for in turn, up to
# MAX_CHAIN deep
func flush() -> void:
	if flushing or not bound():
		return

	flushing = true
	var chain := 0

	while pending != "":
		var to := pending
		pending = ""

		if to == current:
			continue

		chain += 1

		if chain > MAX_CHAIN:
			last_error = "transition chain longer than %d, stopped before '%s'" % [MAX_CHAIN, to]
			break

		apply(to)

	flushing = false

func apply(to: String) -> void:
	var from := current

	if from != "":
		call_state("exit", from, 0.0)

	previous = from
	current = to
	time_in_state = 0.0
	transitions.append({"from": from, "to": to, "at": clock, "tick": ticks})

	if transitions.size() > LOG_SIZE:
		transitions.pop_front()

	state_changed.emit(from, to)
	call_state("enter", to, 0.0)

# __state_call returns true, or raises (reported through the lua state's
# script_error) after leaving the message on the instance for us
func call_state(phase: String, name: String, delta: float) -> void:
	hold_count += 1
	var ok: Variant = lua.call(ai_id, "__state_call", [phase, name, delta])
	hold_count -= 1

	if ok != true:
		var message: Variant = lua.call(ai_id, "__take_state_error", [])
		last_error = String(message) if message is String else "state '%s' %s failed" % [name, phase]

func describe() -> String:
	return "%s %s %.1fs" % [label, current if current != "" else "(no state)", time_in_state]
