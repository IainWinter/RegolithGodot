extends Resource
class_name WeaponProps

# sim units, one unit is one chunk of cells. what every weapon and the plain
# bullet read, beams and homing shots add their own on top

@export var projectile_scene: PackedScene

@export var ammo := -1
@export var shots_per_ammo := 1
@export var delay_cooldown := 0.4
@export var inaccuracy_angle := 0.01
@export var inaccuracy_tangent := 0.01

@export_group("Projectile")
@export var speed := 16.0
@export var speed_random := 0.0
@export var mass := 0.02
@export var lifetime := 5.0
@export var cell_life := 8
@export var trail_length := 0.8
@export var rotation_factor := 100.0
@export var speed_loss_per_cell := 0.0
@export var color_front := Color(0.9, 0.9, 0.9, 1.0)
@export var color_back := Color(0.4, 0.4, 0.4, 0.0)

@export_group("Homing")
@export var turn_speed := 0.0
@export var target_range := 30.0

@export_group("Damage")
@export var burn_strength := 255
@export var scorch_strength := 110
@export var damage_ratio := 0.65
@export var damage := 1
