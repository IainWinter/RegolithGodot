extends Node
class_name BossCompassPhase

# a component under the boss compass's AiScript scene. owns the boss's
# scene-specific parts (shield, trap, rock props, fire points) that
# boss_compass.lua reaches for by name, ticks the shield/trap each step,
# and listens on the host's ai_event(detach_final_phase) to rip the
# stingray out of the shell.
#
# the lua reads self.node:get_node("BossCompassPhase") into self.phase in
# init and calls .shield, .trap, .rock_props, .fire_points and
# .fire_cooldown on it. this keeps the boss-specific api off AiScript
# without hiding what the script needs

@export var shield: EnemyBossShield
@export var trap: EnemyBossTrap
@export var rock_props: RockProps
# prefab hull points, -1..1 with y up
@export var fire_points: Array[Vector2] = [Vector2(0.85, -0.3), Vector2(-0.05, -0.55), Vector2(0.25, -0.55), Vector2(-0.45, -0.85)]
@export var fire_cooldown := 4.0
@export var detach_class := 4
@export var detach_local_position := Vector2(0.08, -0.35)

signal detached(final_phase: Node)

var host: AiScript

func _ready() -> void:
	host = get_parent() as AiScript

	if host == null:
		push_warning("BossCompassPhase: parent is not an AiScript")
		return

	host.ai_event.connect(on_ai_event)

func _physics_process(delta: float) -> void:
	if host == null or host.dead or not host.is_loaded():
		return

	if shield:
		shield.update(host, delta)

	if trap:
		trap.set_hull_box(host)
		trap.update(host, delta)

func on_ai_event(event: StringName, _args: Dictionary) -> void:
	if event == &"detach_final_phase":
		detach_final_phase()

# the final phase leaves: its cells come out of the hull and the stingray
# is placed there (a forced spawn inside the shell), the parts let go and
# the shell is a rock from here on
func detach_final_phase() -> void:
	if host == null or host.dead:
		return

	var count := host.get_cell_count()

	for y in count.y:
		for x in count.x:
			var cell := Vector2i(x, y)

			if host.has_cell(cell) and host.get_cell_class(cell) == detach_class:
				host.remove_cell(cell)

	var request := host.spawn(SpawnRequest.Kind.BOSS_STINGRAY, host.local_point_units(detach_local_position), Vector2.ZERO)
	request.rotation = host.global_rotation
	request.wait_for_room = false
	request.spawned.connect(func(final_phase: RegolithSprite): detached.emit(final_phase))

	var thrower := host.get_thrower()

	if thrower:
		thrower.active = false
		thrower.step(0.0, host.pos)

	if trap:
		trap.active = false

	if shield:
		shield.active = false

	host.fire(false, Vector2.RIGHT)
	host.dead = true
	host.remove_from_group("enemy")
	host.remove_from_group("thrower")
