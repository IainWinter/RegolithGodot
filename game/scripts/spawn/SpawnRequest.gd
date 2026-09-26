extends RefCounted
class_name SpawnRequest

# one thing to spawn: a Kind, a spot and a velocity, sent over the SpawnBus
# for the StableSpawner to place once the sprite tree has room. position and
# velocity are sim units, the lifetime is seconds. the spawner answers on
# spawned with the node, or on expired when the lifetime ran out with no
# room. fields may still be set until the step it spawns on. anything the
# requester wants done to the node once placed (a courier's payload, a
# belt rock's orbit) it does itself in its spawned handler

enum Kind { FIGHTER, BOMB, STATION, BASE, BOSS_COMPASS, BOSS_STINGRAY, ROCK, MESSAGE, ITEM, GUN, TURRET }

signal spawned(node: RegolithSprite)
signal expired
# items are not sprites, the Items autoload answers on this one instead
signal item_spawned(item: Node2D)

var kind := Kind.FIGHTER
var position := Vector2.ZERO
var velocity := Vector2.ZERO
var rotation := 0.0
# seconds to keep trying before the request is dropped
var lifetime := 10.0
# hold while the camera can see the sprite's bounds at the spot
var offscreen_only := false
# hold while other sprites touch the spot, off places it at once
var wait_for_room := true
# extra clear space around the sprite's bounds, units
var clearance := 0.25
# sprites allowed to touch the spot, the requester itself as a rule
var ignore: Array = []

# rocks: generated from the props, chunks zero picks from the props. drift
# gives the props' random drift and spin instead of the velocity
var rock_props: RockProps
var chunks := 0
var drift := false
var rng: RandomNumberGenerator

# items: the props of the item to drop. the Items autoload places it at
# once, it never waits for room
var item_props: ItemProps

static func enemy(of_kind: Kind, at: Vector2, with_velocity := Vector2.ZERO, only_offscreen := false, for_seconds := 10.0) -> SpawnRequest:
	var request := SpawnRequest.new()
	request.kind = of_kind
	request.position = at
	request.velocity = with_velocity
	request.offscreen_only = only_offscreen
	request.lifetime = for_seconds
	return request

static func rock(props: RockProps, at: Vector2, with_velocity := Vector2.ZERO, only_offscreen := false, for_seconds := 10.0) -> SpawnRequest:
	var request := enemy(Kind.ROCK, at, with_velocity, only_offscreen, for_seconds)
	request.rock_props = props
	return request

# a courier, placed at once: a message never waits for room. the sender
# sets it up on spawned
static func message(at: Vector2) -> SpawnRequest:
	var request := enemy(Kind.MESSAGE, at, Vector2.ZERO, false, 2.0)
	request.wait_for_room = false
	return request

static func item(props: ItemProps, at: Vector2, with_velocity := Vector2.ZERO) -> SpawnRequest:
	var request := enemy(Kind.ITEM, at, with_velocity, false, 2.0)
	request.item_props = props
	request.wait_for_room = false
	return request

func is_rock() -> bool:
	return kind == Kind.ROCK

func is_item() -> bool:
	return kind == Kind.ITEM
