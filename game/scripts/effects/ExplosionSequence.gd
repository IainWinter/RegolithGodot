extends Node2D
class_name ExplosionSequence

# port of ExplosionSequenceSystem: a cook off that rides along with a
# sprite for duration seconds, spitting sparks (and half the time smoke)
# every particle_interval and one to three short bolts every
# lightning_interval, then goes off as an explosion: shrapnel bullets of
# both kinds from the position, carrying velocity_bias, the burst from the
# EffectSpawner and the exploded signal. the item drops of the original
# are left to whoever listens on finished. all of it is render work, so it
# runs in _process. positions in world pixels, velocities in units

@export var duration := 1.2
@export var particle_interval := 0.15
@export var lightning_interval := 0.3
@export var spark: ParticleProps
@export var smoke: ParticleProps
@export var lightning_props: LightningProps
@export var lightning_material: Material
@export var shrapnel: WeaponProps
@export var shrapnel_long: WeaponProps

# a strike keeps its props and reads speed and lifetime while it animates,
# so the per bolt variations rotate through this many copies made once
# instead of a duplicate per strike. enough for the bolts alive at once
const BOLT_POOL := 12

var shrapnel_count := 0
var shrapnel_long_count := 0
var item_count := 0
var velocity_bias := Vector2.ZERO
var shooter: RegolithSprite

var attached: RegolithSprite
var attached_local := Vector2.ZERO

var particle_timer := 0.0
var lightning_timer := 0.0
var lightning: Lightning
var bolt_props: Array[LightningProps] = []
var next_bolt := 0
var done := false

signal exploded(position: Vector2)
signal finished(position: Vector2, item_count: int, velocity_bias: Vector2)

# rides on a sprite at a local pixel offset until it goes off
func attach_to(sprite: RegolithSprite, local: Vector2) -> void:
	attached = sprite
	attached_local = local

	if sprite != null and is_instance_valid(sprite):
		global_position = sprite.to_global(local)

func _ready() -> void:
	top_level = true

	if lightning_props != null:
		lightning = Lightning.attach(self, lightning_props, lightning_material)

		for i in BOLT_POOL:
			var bolt: LightningProps = lightning_props.duplicate()
			bolt.jitter_step_size = 5.0
			bolt_props.append(bolt)

func _process(delta: float) -> void:
	if done:
		return

	duration -= delta

	if attached != null:
		if Steering.alive(attached):
			global_position = attached.to_global(attached_local)
		else:
			attached = null

	particle_timer += delta

	if particle_timer >= particle_interval:
		particle_timer -= particle_interval
		spit_particles()

	lightning_timer += delta

	if lightning_timer >= lightning_interval:
		lightning_timer -= lightning_interval
		spit_bolts()

	if duration <= 0.0:
		go_off()

func spit_particles() -> void:
	var effects := EffectSpawner.active()

	if effects == null:
		return

	var at := global_position + Steering.random_in_circle(0.4) * RegolithWorld.pixels_per_unit()
	effects.emit(spark if spark != null else effects.explosion_spark, at)

	if randf() < 0.5:
		effects.emit(smoke if smoke != null else effects.explosion_smoke, at)

func spit_bolts() -> void:
	if lightning == null or bolt_props.is_empty():
		return

	var ppu := RegolithWorld.pixels_per_unit()

	for i in randi_range(1, 3):
		var bolt := bolt_props[next_bolt]
		next_bolt = (next_bolt + 1) % bolt_props.size()
		bolt.point_count = randi_range(5, 20)
		bolt.expected_splits_per_bolt = randf()
		bolt.speed = randf_range(4.0, 32.0)
		var reach := Vector2.from_angle(randf() * TAU) * randf_range(1.0, 2.5) * ppu
		lightning.strike(global_position, global_position + reach, shooter, bolt)

func go_off() -> void:
	done = true
	var at := global_position

	# the original handler never applied velocity_bias to the shrapnel either
	Explosion.spawn_shrapnel(shrapnel, shrapnel_count, at, shooter)
	Explosion.spawn_shrapnel(shrapnel_long, shrapnel_long_count, at, shooter)

	var effects := EffectSpawner.active()

	if effects:
		effects.explosion(at)

	exploded.emit(at)
	finished.emit(at, item_count, velocity_bias)

	if lightning != null and lightning_props != null:
		get_tree().create_timer(lightning_props.lifetime + 0.5).timeout.connect(queue_free)
	else:
		queue_free()
