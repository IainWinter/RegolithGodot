extends WeaponProps
class_name BeamWeaponProps

# a beam weapon spawns one projectile that lives while the trigger is held
# and drains the charge instead of the ammo. sim units

@export_group("Beam")
@export var charge := 0.0
@export var charge_drain := 0.0
@export var width := 0.0625
@export var range := 40.0
