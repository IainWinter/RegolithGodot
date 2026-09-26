extends WeaponProps
class_name LightningWeaponProps

# lightning weapons on top of WeaponProps, sim units. three shapes share it:
# the zap gun (LightningZap, the player's lightning bolt) is an instant bolt
# from the muzzle to the first cell in range, the homing bolt (LightningBolt,
# the boss's shot) flies at its target and paints bolts from its tail to its
# head, the ball (LightningBall) drifts and zaps the cells around it

@export_group("Lightning")
@export var lightning: LightningProps
@export var lightning_hit: LightningProps
@export var lightning_material: ShaderMaterial

@export_group("Zap")
# reach of the muzzle ray, and how many pixels a held trigger eats per
# second on average: the odds a zap removes cells are derived from it and
# the fire rate, the rest of the zaps only scorch
@export var bolt_range := 3.0
@export var bolt_pixels_per_second := 20.0
# projectiles and items this close to the muzzle get arced at
@export var bolt_arc_radius := 2.4

@export_group("Bolt")
@export var segment_length := 2.0
@export var strikes_per_second := 30.0

@export_group("Ball")
@export var ball_radius := 2.0
@export var ball_emit_radius := 0.4
@export var ball_center_lightning: LightningProps
@export var ball_outside_lightning: LightningProps
@export var ball_segments := 6
@export var ball_delay_per_hit := 0.02
@export var ball_zaps_per_hit := 10
@export var ball_pixels_per_second := 80.0

func hit_props() -> LightningProps:
	return lightning_hit if lightning_hit != null else lightning
