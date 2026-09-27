extends Node
class_name BombBehavior

# a component under an AiScript bomb scene. subscribes to the parent's
# ai_event signal. when the lua fires ("start_fuse", {time = ...}) it runs
# a countdown, puffs fuse smoke each drawn frame, then bursts: blast rays,
# an impulse, shrapnel and the explosion effect. sends nothing back, the
# parent AiScript dies from the shared regolith world death path once the
# blast eats its core, or from die() called here at the end.
#
# lives on the bomb scene alongside AiScript, PlayerSensor, Throwable

@export var blast_radius := 1.5
@export var blast_rays := 16
@export var blast_cells_per_ray := 3
@export var blast_impulse := 4.0
@export var shrapnel_props: WeaponProps
@export var shrapnel_count := 24

signal exploded(position: Vector2)

var host: AiScript
var exploding := false
var fuse := 0.0

func _ready() -> void:
	host = get_parent() as AiScript

	if host == null:
		push_warning("BombBehavior: parent is not an AiScript")
		return

	host.ai_event.connect(on_ai_event)

func on_ai_event(name: StringName, args: Dictionary) -> void:
	if name == &"start_fuse":
		start_fuse(float(args.get("time", 0.0)))

func start_fuse(time: float) -> void:
	exploding = true
	fuse = time

func _physics_process(delta: float) -> void:
	if not exploding or host == null or host.dead:
		return

	fuse -= delta

	if fuse <= 0.0:
		explode()

# fuse puffs each drawn frame while it burns
func _process(_delta: float) -> void:
	if not exploding or host == null or host.dead:
		return

	var effects := EffectSpawner.active()

	if effects:
		effects.emit(effects.bomb_fuse_puff, EffectSpawner.effect_origin(host))

# the blast, its shrapnel and the burst all come from the core, where the
# fuse puffed
func explode() -> void:
	exploding = false
	var world := RegolithWorld.active()
	var center := EffectSpawner.effect_origin(host)

	if world:
		var r := blast_radius * Steering.ppu()

		for sprite in Steering.sprites_near(world, center / Steering.ppu(), blast_radius):
			if sprite == host:
				continue

			if Explosion.blast_rays(sprite, center, r, blast_rays, blast_cells_per_ray, true) and sprite.is_dynamic():
				var away: Vector2 = (sprite.global_position - center).normalized()
				sprite.apply_impulse(away * blast_impulse * sprite.get_mass(), sprite.global_position)

		Explosion.spawn_shrapnel(shrapnel_props, shrapnel_count, center, host)

	var effects := EffectSpawner.active()

	if effects:
		effects.explosion(center)

	exploded.emit(center)
	host.die()
