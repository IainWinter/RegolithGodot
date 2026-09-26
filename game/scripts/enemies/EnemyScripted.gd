extends Enemy
class_name EnemyScripted

# an enemy whose decisions live in a lua class from res://game/lua. the
# node keeps the mechanics (steering, weapons, death), the script gets
# messages and calls back into the node. sensor children feed messages
# each physics step, other scripted things send them through Ai, and the
# script sees them all through on_message(msg) before update(dt), then the
# state machine runs the current state's update. the machine is made here
# before the script so init can register states, and bound to the instance
# after so the first transition lands.
#
# the generic body parts every script may lean on: a weapon when
# weapon_props is set (fire(pull, direction)), an EnemyThrower child
# (get_thrower, its threw comes out as this node's threw), a drop_table
# for the Items autoload, and ai_config, a dictionary of tunables the
# script reads over its own defaults (self:config(DEFAULTS) in lua) so a
# scene or a test can change a number without touching the script

@export var ai_class := ""
@export var weapon_props: WeaponProps
@export var drop_table: ItemDropTable
@export var ai_config := {}

var ai_id := 0
var state_machine := AiStateMachine.new()
var inbox: Array[Dictionary] = []
var sensors: Array[Sensor] = []
var weapon: Weapon

func _ready() -> void:
	super()

	for child in get_children():
		if child is Sensor:
			sensors.append(child)
			child.message.connect(receive)

	if weapon_props:
		weapon = make_weapon(weapon_props, Vector2.ZERO)

	var thrower := get_thrower()

	if thrower:
		thrower.threw.connect(func(node: RegolithSprite): threw.emit(node))

	state_machine.label = "%s (%s)" % [name, ai_class]

	if ai_class != "":
		ai_id = Ai.create(ai_class, self)
		state_machine.bind(Ai.lua, ai_id)

func _exit_tree() -> void:
	state_machine.unbind()

	if ai_id != 0:
		Ai.destroy(ai_id)
		ai_id = 0

# anything with a receive can be a message target
func receive(message: Dictionary) -> void:
	inbox.append(message)

# changes tunables on the scene and, once the script runs, on its cfg
func configure(overrides: Dictionary) -> void:
	ai_config.merge(overrides, true)

	if ai_id != 0:
		Ai.invoke(ai_id, "configure", [overrides])

func update_ai(delta: float) -> void:
	for sensor in sensors:
		sensor.poll(delta)

	if ai_id == 0:
		return

	var pending := inbox
	inbox = []

	# transitions asked for in here wait for the tick
	state_machine.hold()

	for message in pending:
		Ai.invoke(ai_id, "on_message", [message])

	Ai.invoke(ai_id, "update", [delta])
	state_machine.release()
	state_machine.tick(delta)

func fire(pull_trigger: bool, direction: Vector2) -> void:
	if weapon:
		weapon.set_fire_state(pull_trigger, direction)

# the body as the script measures it: half extents and radius of the grid
# in units, and where effects come from (the core, else the center of mass)
func half_extent_units() -> Vector2:
	return Steering.half_extent_units(self)

func radius_units() -> float:
	return Steering.sprite_radius_units(self)

func effect_origin_units() -> Vector2:
	return EffectSpawner.effect_origin(self) / Steering.ppu()

func is_thrown() -> bool:
	var throwable := Throwable.of(self)
	return throwable != null and throwable.thrown
