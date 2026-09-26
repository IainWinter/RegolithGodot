extends Resource
class_name ParticleProps

# one particle look, the ParticleSpawn of the original engine. every
# particle is a colored quad off the particles atlas (frames 0-5 the smoke
# puffs, 6 a solid square): it flies off with a damped velocity, spins in
# three axes with a damped angular velocity, and lerps its scale and color
# on a powered life ratio. sim units and seconds. min/max pairs are sampled
# per particle, the spawn frame has x along the emit direction

@export var count_min := 1
@export var count_max := 1
@export var direction_offset := 0.0
@export var frame_min := 6
@export var frame_max := 6

@export_group("Spawn")
@export var offset_min := Vector2.ZERO
@export var offset_max := Vector2.ZERO
@export var velocity_min := Vector2.ZERO
@export var velocity_max := Vector2.ZERO
@export var damping_min := 1.0
@export var damping_max := 1.0
@export var life_min := 0.5
@export var life_max := 0.5
# a spark thrown off by a projectile's hit: with a source speed given to the
# burst, the velocity range is only the shape (spread and relative
# magnitude) and is scaled so its fastest corner leaves at that speed.
# damping still slows them. without a source speed, or with the flag off,
# the range is flown as is
@export var speed_from_source := false

@export_group("Spin")
@export var angle_min := 0.0
@export var angle_max := 0.0
@export var angle_xy_min := Vector2.ZERO
@export var angle_xy_max := Vector2.ZERO
@export var angular_velocity_min := 0.0
@export var angular_velocity_max := 0.0
@export var angular_velocity_xy_min := Vector2.ZERO
@export var angular_velocity_xy_max := Vector2.ZERO
@export var angular_damping := 1.0

@export_group("Scale")
@export var scale_begin_min := Vector2(0.05, 0.05)
@export var scale_begin_max := Vector2(0.05, 0.05)
@export var scale_end := Vector2.ZERO
@export var scale_factor := 1.0

@export_group("Color")
@export var color_begin := Color.WHITE
@export var color_end := Color(1.0, 1.0, 1.0, 0.0)
@export var color_factor := 1.0
@export var emissive := 0.0
# a spark thrown off by a projectile's hit: with a source color given to the
# burst, the ramp takes that color's hue in place of its own. the begin
# color is the source brightened toward white by as much as color_begin is
# whiter than color_end (the hot core), at color_begin's peak and alpha, the
# end color is the source at color_end's peak and alpha. color_factor and
# emissive stay, so the overbright core and the tonemap behave as before
# (see ParticleEffect.source_ramp). without a source color, or with the
# flag off, the props' own ramp is flown
@export var color_from_source := false

# the fastest velocity the range can sample, the length of its farthest
# corner, sim units per second
func top_speed() -> float:
	var x := maxf(absf(velocity_min.x), absf(velocity_max.x))
	var y := maxf(absf(velocity_min.y), absf(velocity_max.y))
	return Vector2(x, y).length()
