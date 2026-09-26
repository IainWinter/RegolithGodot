extends Resource
class_name WeaponProps

# sim units, one unit is one chunk of cells. what every weapon and the plain
# bullet read, homing shots and the laser add their own on top

@export var projectile_scene: PackedScene

@export var ammo := -1
@export var shots_per_ammo := 1
@export var delay_charge := 0.0
@export var delay_cooldown := 0.4
@export var inaccuracy_angle := 0.01
@export var inaccuracy_tangent := 0.01
# fans shots_per_ammo evenly across this angle on a trigger pull, the
# original spread_angle + spread_uniform of the boss arc cannon
@export var spread_angle := 0.0
# half angle of the aim assist fan in degrees, zero turns it off
@export var aim_assist_degrees := 0.0

@export_group("Projectile")
@export var speed := 16.0
@export var speed_random := 0.0
# the hit impulse is the bullet's momentum, velocity times this. kept tiny so
# a hit nudges a rock instead of launching it
@export var mass := 0.005
# a hit may change the target's speed (units/s) and spin (rad/s) by at most
# this much, so a small rock takes the same knock as a big one instead of
# flying off and spinning up. zero means no cap
@export var max_hit_speed := 1.5
@export var max_hit_spin := 1.5
@export var lifetime := 5.0
@export var lifetime_random := 0.0
@export var cell_life := 8
@export var trail_length := 0.8
@export var rotation_factor := 100.0
@export var speed_loss_per_cell := 0.0
# odds that a cell hit throws off a second bullet with half the remaining
# cell life, the original's spit
@export var spit_odds := 0.0
@export var color_front := Color(0.9, 0.9, 0.9, 1.0)
@export var color_back := Color(0.4, 0.4, 0.4, 0.0)
@export var texture: Texture2D
@export var texture_scale := 1.0
@export var muzzle_effects: Array[ParticleProps] = []

@export_group("Homing")
@export var turn_speed := 0.0
@export var target_range := 30.0

@export_group("Damage")
@export var burn_strength := 255
@export var scorch_strength := 110
@export var damage_ratio := 0.65
@export var damage := 1
