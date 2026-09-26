extends WeaponProps
class_name BeamWeaponProps

# the super laser: a dense stream of fast bullets with full length trails
# that drains a charge for as long as it fires instead of spending ammo, the
# way the original's special ability fed its weapon. sim units

@export_group("Charge")
@export var charge := 0.0
@export var charge_drain := 0.0
