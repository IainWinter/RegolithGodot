extends Node2D
class_name EffectSpawner

# where the gameplay visuals come from. owns the one ParticleEffect node
# every effect draws through. things ask for their own effects: a weapon
# reports each shot on fired (muzzle flash, and the burst when that shot
# later explodes), a missile trails exhaust and a bomb on its fuse puffs
# from their own _process, a bullet asks for its hit spark, a bomb or
# cook off asks for its explosion. port of the ExplosionEventHandler,
# MissileMove and AiBomb particle spawns and the lua effect_on_shot hooks
# of the original. lives under the parent of the world, positions in world
# pixels

@export var explosion_spark: ParticleProps
@export var explosion_smoke: ParticleProps
@export var hit_spark: ParticleProps
@export var missile_flame: ParticleProps
@export var missile_smoke: ParticleProps
@export var bomb_fuse_puff: ParticleProps
# the cook off a core or weakpoint death plays before its blast
@export var explosion_sequence_scene: PackedScene

var particles: ParticleEffect
# bursts so far, for tests
var explosions := 0
var sparks := 0
# the source color of the last spark, alpha below zero for none, for tests
var last_spark_color := Color(0.0, 0.0, 0.0, -1.0)

static func active() -> EffectSpawner:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group("effect_spawner") as EffectSpawner if tree else null

func _enter_tree() -> void:
	add_to_group("effect_spawner")

func _ready() -> void:
	for child in get_children():
		if child is ParticleEffect:
			particles = child
			break

	if particles == null:
		push_warning("EffectSpawner has no ParticleEffect child, effects draw nothing")

# speed is what caused the burst, sim units per second, below zero for
# none. only props with speed_from_source use it. color is the color of
# what caused it, alpha below zero for none, only props with
# color_from_source use it (see ParticleEffect.burst)
func emit(props: ParticleProps, position: Vector2, angle := 0.0, count := -1, speed := -1.0, color := Color(0.0, 0.0, 0.0, -1.0)) -> void:
	if particles != null and props != null:
		particles.burst(props, position, angle, count, Color(0.0, 0.0, 0.0, -1.0), speed, color)

# where a sprite's own effects come from, in world pixels: the middle of its
# Core cells while it has them, the center of what is left of it otherwise.
# never the node origin: that is the middle of the chunk padded grid, and the
# art sits in the grid's top left corner, so for anything that is not a whole
# number of chunks the origin lies off the shape (a 13 cell bomb in a 32 cell
# chunk has its origin 9 cells past its core). every fuse puff, burst, spark
# and cook off on an enemy, rock or thrown thing takes this spot
static func effect_origin(sprite: RegolithSprite) -> Vector2:
	if sprite == null or not is_instance_valid(sprite):
		return Vector2.ZERO

	if not sprite.is_loaded():
		return sprite.global_position

	for i in sprite.get_core_count():
		if sprite.get_core_type(i) == RegolithSprite.CELL_CORE:
			return sprite.get_core_position(i)

	if sprite.get_active_cell_count() > 0:
		return sprite.get_center_of_mass()

	return sprite.global_position

# the same spot as a local pixel offset, for what rides along with the sprite
static func effect_origin_local(sprite: RegolithSprite) -> Vector2:
	if sprite == null or not is_instance_valid(sprite):
		return Vector2.ZERO

	return sprite.to_local(effect_origin(sprite))

func explosion(position: Vector2) -> void:
	explosions += 1
	emit(explosion_spark, position)
	emit(explosion_smoke, position)

# a hit spark along a surface normal. speed is the projectile's, sim units
# per second: the fastest sparks leave at it. below zero keeps the props'
# own velocity range. color is the projectile's: the sparks fly in its hue,
# alpha below zero keeps the props' own ramp
func spark(position: Vector2, angle: float, speed := -1.0, color := Color(0.0, 0.0, 0.0, -1.0)) -> void:
	sparks += 1
	last_spark_color = color
	emit(hit_spark, position, angle, -1, speed, color)

# a weapon fired: its props' muzzle effects flash where the shot appeared,
# and a shot that explodes gets the burst when it does
func on_fired(bullet: Node2D) -> void:
	var props: Variant = bullet.get("props")
	var velocity: Variant = bullet.get("velocity")

	if props is WeaponProps:
		var angle: float = velocity.angle() if velocity is Vector2 else bullet.global_rotation

		for muzzle in props.muzzle_effects:
			emit(muzzle, bullet.global_position, angle)

	if bullet.has_signal("exploded"):
		bullet.exploded.connect(explosion)

# starts an ExplosionSequence riding on sprite at a local pixel offset, the
# SpriteCoreEventHandler's answer to a core blowing. null without a scene
func cook_off(sprite: RegolithSprite, local: Vector2, shrapnel_count: int, shrapnel_long_count := 0, item_count := 0, velocity_bias := Vector2.ZERO) -> ExplosionSequence:
	if explosion_sequence_scene == null:
		return null

	var sequence := explosion_sequence_scene.instantiate() as ExplosionSequence

	if sequence == null:
		return null

	sequence.shrapnel_count = shrapnel_count
	sequence.shrapnel_long_count = shrapnel_long_count
	sequence.item_count = item_count
	sequence.velocity_bias = velocity_bias
	sequence.shooter = sprite
	sequence.attach_to(sprite, local)
	get_parent().add_child(sequence)
	return sequence
