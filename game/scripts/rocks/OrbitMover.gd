extends Node
class_name OrbitMover

# port of OrbitMoverSystem: the parent sprite rides a circle around center
# at angular_speed, a kinematic rail that ignores what it bumps into. the
# sprite is made static so the node position drives its body. pieces that
# split off should go dynamic and fall out of the orbit: whoever puts
# sprites on orbit connects the world's sprite_split to release_piece
# once. sim units, radians

@export var center := Vector2.ZERO
@export var radius := 1.0
@export var angle := 0.0
@export var angular_speed := 0.0

var sprite: RegolithSprite
var ppu := 1.0

# puts a sprite on the orbit through where it stands now
static func attach(node: RegolithSprite, orbit_center: Vector2, speed: float) -> OrbitMover:
	var mover := OrbitMover.new()
	mover.name = "OrbitMover"
	var offset := node.global_position / RegolithWorld.pixels_per_unit() - orbit_center
	mover.center = orbit_center
	mover.radius = offset.length()
	mover.angle = offset.angle()
	mover.angular_speed = speed
	node.add_child(mover)
	return mover

# sprite_split handler: a piece off an orbiting sprite is free of the rail
static func release_piece(source: RegolithSprite, piece: RegolithSprite) -> void:
	if source.get_node_or_null("OrbitMover") is OrbitMover:
		piece.dynamic = true

func _ready() -> void:
	sprite = get_parent() as RegolithSprite
	ppu = RegolithWorld.pixels_per_unit()

	if sprite == null:
		push_warning("OrbitMover must be a child of a RegolithSprite")
		return

	sprite.dynamic = false
	sprite.linear_velocity = Vector2.ZERO
	sprite.angular_velocity = 0.0

func orbit_position() -> Vector2:
	return center + Vector2.from_angle(angle) * radius

func _physics_process(delta: float) -> void:
	if sprite == null:
		return

	angle += angular_speed * delta
	sprite.global_position = orbit_position() * ppu
	sprite.linear_velocity = Vector2.ZERO
