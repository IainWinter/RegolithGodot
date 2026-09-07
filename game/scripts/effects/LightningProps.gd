extends Resource
class_name LightningProps

# the engine's LightningSpawn. lengths in sim units, angles in radians, the
# angle ranges are sampled once per strike

@export var begin_offset := Vector2.ZERO
@export var end_offset := Vector2.ZERO

@export_group("Shape")
@export var point_count := 32
@export var expected_splits_per_bolt := 2.5
@export var head_takeover_chance := 0.25
@export var jitter_step_size := 2.5
@export var branch_scale := 0.45
@export var start_angle_min := 0.0
@export var start_angle_max := 0.0
@export var bias_angle_min := 0.0
@export var bias_angle_max := 0.0

@export_group("Timing")
@export var speed := 45.0
@export var lifetime := 0.5

@export_group("Color")
@export var color := Color(180.0 / 255.0, 200.0 / 255.0, 1.0, 200.0 / 255.0)
@export var fade_color := Color(90.0 / 255.0, 40.0 / 255.0, 180.0 / 255.0, 0.0)
@export var emission := 0.25

@export_group("Sparks")
@export var emit_spark := false
@export var particle_density := 50.0
@export var spark_color := Color(0.6, 0.7, 1.0, 0.9)
@export var spark_speed := 3.0

@export_group("Burn")
@export var burn_strength := 110
@export var burn_damage := 0
