extends Resource
class_name ItemProps

# one item kind at one size, the item_health_*, item_core_* and
# item_ability_* prefabs of the original. the texture draws at one texel
# per cell. sim units and seconds, damping is the per second fraction of
# velocity lost

enum Type { HEALTH, CORE, ENERGY }
enum Size { SMALL, MEDIUM, LARGE }

@export var type := Type.HEALTH
@export var size := Size.MEDIUM
@export var texture: Texture2D
@export var tint := Color.WHITE
# cells repaired on pickup, the original repairs one per item at any size
@export var heal_cells := 1

@export_group("Power")
# sand cells an energy item pours into the player's PowerTank, the
# ability_shield and ability_super_laser scripts' 25, 60 and 120 by size
@export var power_cells := 0
@export var power_color := Color8(60, 180, 230, 200)

@export_group("Pickup")
# a sink within this many units pulls the item in
@export var radius := 1.0
# seconds after spawning before a sink may pull it
@export var pickup_delay := 0.6
# seconds the pull takes to land
@export var collect_time := 1.0
# seconds a loose item lasts
@export var life := 15.0

@export_group("Motion")
@export var damping_min := 3.0
@export var damping_max := 10.0
# above zero replaces the spawn speed, keeping the direction (the core's 4..6)
@export var speed_min := 0.0
@export var speed_max := 0.0
# spawn spin up to this many radians per second either way
@export var spin := 40.0

func is_core() -> bool:
	return type == Type.CORE

func is_energy() -> bool:
	return type == Type.ENERGY
