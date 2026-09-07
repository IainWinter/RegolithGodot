extends Node

# SpawnBus autoload: the emitter between whatever wants a sprite spawned and
# the StableSpawner that places it. a requester sends a SpawnRequest here
# and listens on the request, it never knows who answers. spawn and
# spawn_rock build the usual requests

signal spawn_requested(request: SpawnRequest)

func send(request: SpawnRequest) -> SpawnRequest:
	if spawn_requested.get_connections().is_empty():
		push_warning("SpawnBus: nothing listens, add a StableSpawner to the scene")

	spawn_requested.emit(request)
	return request

# position and velocity in units
func spawn(kind: SpawnRequest.Kind, position: Vector2, velocity := Vector2.ZERO, offscreen_only := false, lifetime := 10.0) -> SpawnRequest:
	return send(SpawnRequest.enemy(kind, position, velocity, offscreen_only, lifetime))

func spawn_rock(props: RockProps, position: Vector2, velocity := Vector2.ZERO, offscreen_only := false, lifetime := 10.0) -> SpawnRequest:
	return send(SpawnRequest.rock(props, position, velocity, offscreen_only, lifetime))
