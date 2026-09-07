@tool
extends EditorDebuggerPlugin

# editor side of the "regolith" debugger channel. answers the game's ready
# message with the dock's settings and pushes changes to live sessions

var dock: Control

func _has_capture(prefix: String) -> bool:
	return prefix == "regolith"

func _capture(message: String, _data: Array, session_id: int) -> bool:
	if message == "regolith:ready":
		push(get_session(session_id), dock.settings)
		return true

	return false

func push_all(settings: Dictionary) -> void:
	for session in get_sessions():
		if session.is_active():
			push(session, settings)

func push(session: EditorDebuggerSession, settings: Dictionary) -> void:
	session.send_message("regolith:settings", [settings])
