extends WeaponProps
class_name HomingWeaponProps

# missiles and force bullets: they steer at a target, accelerate and go off
# in a burst of shrapnel bullets. sim units

@export_group("Flight")
@export var acceleration := 0.0
@export var max_speed := 0.0
@export var width := 0.125
@export var coast_time := 0.0
@export var spawn_grace := 0.0
@export var target_search_radius := 8.0

@export_group("Explosion")
@export var explosion_radius := 0.0
@export var shrapnel: WeaponProps
@export var shrapnel_count := 0
@export var shrapnel_long: WeaponProps
@export var shrapnel_long_count := 0
