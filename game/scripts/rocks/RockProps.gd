extends Resource
class_name RockProps

# generated asteroid settings, numbers from the original AsteroidGenerateConfig
# and SpawnGeneratedAsteroidEvent. sizes are cells, one chunk is 32 cells and
# one sim unit

@export var min_chunks := 1
@export var max_chunks := 3

@export var source_texture: Texture2D
var source_image_cache: Image
@export var uv_scale := 0.6

@export var shape_variants := true

@export_group("Shape")
@export var radius_scale := 0.45
@export var noise_frequency := 0.012
@export var noise_amplitude := 0.35
@export var noise_octaves := 4
@export var noise_persistence := 0.5

@export_group("Burn")
@export var burn_pixels := 8.0
@export var burn_strength := 0.85

@export_group("Ore")
@export var ore_chance := 0.0
@export var ore_colors: Array[Color] = [Color8(255, 90, 70), Color8(60, 140, 220)]
@export var ore_class := 1
@export var ore_cluster_count := 4
@export var ore_cluster_radius := 8.0
@export var ore_cluster_jitter := 3.0
@export var ore_shape_frequency := 0.10
@export var ore_shape_amount := 0.5
@export var ore_fill_frequency := 0.35
@export var ore_edge_noise := 0.8
@export var ore_core_hardness := 1.2
@export var ore_noise_threshold := 0.2
@export var ore_inset_pixels := 4.0

@export_group("Motion")
@export var min_speed := 0.15
@export var max_speed := 0.6
@export var max_spin := 0.4
@export var angular_damping := 1.0
