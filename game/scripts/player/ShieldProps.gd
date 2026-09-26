extends Resource
class_name ShieldProps

# the player's shield, the Shield component with the numbers of
# abilities/shield.lua. an arc of lightning around the ship that shoves
# rocks out and turns enemy bullets away. units, radians, seconds

@export var local_center := Vector2.ZERO
@export var radius := 2.5
@export var arc_min := -PI
@export var arc_max := PI

@export_group("Push")
@export var max_penetration := 1.0
@export var max_rock_penetration := 1.0
@export var rock_force := 20.0
@export var buffer_distance := 1.0

@export_group("Lightning")
@export var lightning: LightningProps
@export var lightning_material: Material
@export var strikes_per_second := 24.0
@export var segment_arc_min := 0.3
@export var segment_arc_max := 0.8
