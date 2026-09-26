extends Node2D
class_name GravityAttractor

# port of GravityMoverSystem with its two components: each attractor pulls
# every sprite with a GravityMover child toward itself with
# mass * mover.strength / distance squared, applied at the mover's center
# of mass each physics step. sim units

@export var mass := 1.0

func _physics_process(delta: float) -> void:
	var ppu := RegolithWorld.pixels_per_unit()
	var here := global_position / ppu

	for node in get_tree().get_nodes_in_group("gravity_mover"):
		var mover := node as GravityMover
		var sprite := mover.sprite if mover else null

		if sprite == null or not sprite.is_loaded() or not sprite.is_dynamic():
			continue

		var com := sprite.get_center_of_mass()
		sprite.apply_impulse(pull_at(here, mass, com / ppu, mover.strength) * delta, com)

# the pull of one mass at source on a point, zero right on top of it
static func pull_at(source: Vector2, mass: float, at: Vector2, strength: float) -> Vector2:
	var diff := source - at
	var dist_sq := diff.length_squared()

	if dist_sq < 0.0001:
		return Vector2.ZERO

	return diff / sqrt(dist_sq) * (mass * strength / dist_sq)
