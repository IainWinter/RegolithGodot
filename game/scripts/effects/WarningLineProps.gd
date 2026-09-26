extends Resource
class_name WarningLineProps

# the two line configs of the original warning line, lines/warning_glow and
# lines/warning_edge. widths in sim units, times in seconds

@export_group("Glow")
@export var glow_color := Color(1.0, 0.15, 0.15, 1.0)
@export var glow_width := 0.75
@export var glow_max_points := 64
@export var glow_fade_time := 0.5
@export var glow_base_alpha := 0.09
@export var glow_pulse_alpha := 0.12
@export var glow_pulse_speed := 11.25
@export var glow_pulse_length := 8.0

@export_group("Edge")
@export var edge_color := Color(1.0, 0.15, 0.15, 1.0)
@export var edge_width := 0.04
@export var edge_fade_time := 0.5
@export var edge_base_alpha := 0.5
