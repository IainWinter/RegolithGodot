extends WeaponProps
class_name LightningWeaponProps

# lightning weapons on top of WeaponProps. the bolt homes on the first cell
# its muzzle ray finds and paints bolts from its tail to its head as it
# flies, the ball drifts and zaps the cells around it. sim units

@export_group("Lightning")
@export var lightning: LightningProps
@export var lightning_hit: LightningProps
@export var lightning_material: ShaderMaterial

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
