extends Node2D
class_name Background

# stars and dust clouds spread over a big area, each depth layer slides with the
# camera by a parallax factor so the field drifts behind the game. sizes and
# positions are in sim units like the original

@export var star_texture: Texture2D
@export var dust_texture: Texture2D
@export var star_count := 1000
@export var dust_count := 10
@export var layers := 10
@export var seed := 7
@export var space_color := Color(0.02, 0.02, 0.04, 1.0)

const AREA := Vector2(64.0, 36.0)
const STAR_PARALLAX := 2.0
const DUST_PARALLAX := 0.5

var star_layers: Array[MultiMeshInstance2D] = []
var dust_layers: Array[MultiMeshInstance2D] = []

func _ready() -> void:
	z_index = -100
	z_as_relative = false

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	dust_layers = build_layers(rng, dust_texture, dust_count, 4.0, func(r: RandomNumberGenerator) -> float: return r.randf_range(10.0, 20.0),
		func(r: RandomNumberGenerator) -> Color: return Color8(100, r.randi_range(0, 200), 200, 100))

	star_layers = build_layers(rng, star_texture, star_count, 3.0, func(r: RandomNumberGenerator) -> float: return r.randf_range(0.001, 0.01),
		func(r: RandomNumberGenerator) -> Color: return Color8(r.randi_range(64, 128), 140, 140, 255))

func build_layers(rng: RandomNumberGenerator, texture: Texture2D, count: int, base_depth: float, pick_scale: Callable, pick_color: Callable) -> Array[MultiMeshInstance2D]:
	var ppu := RegolithWorld.pixels_per_unit()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)

	var buckets: Array = []
	for i in range(layers):
		buckets.append([])

	for i in range(count):
		var depth := rng.randf()
		var layer := mini(int(depth * layers), layers - 1)
		var size := maxf(pick_scale.call(rng) * ppu, 0.75)
		var t := Transform2D(rng.randf_range(0.0, TAU), Vector2.ONE * size, 0.0, Vector2(rng.randf_range(-AREA.x, AREA.x), rng.randf_range(-AREA.y, AREA.y)) * ppu)
		buckets[layer].append([t, pick_color.call(rng)])

	var result: Array[MultiMeshInstance2D] = []

	for i in range(layers):
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = buckets[i].size()

		for j in range(buckets[i].size()):
			multimesh.set_instance_transform_2d(j, buckets[i][j][0])
			multimesh.set_instance_color(j, buckets[i][j][1])

		var instance := MultiMeshInstance2D.new()
		instance.multimesh = multimesh
		instance.texture = texture
		instance.set_meta("depth", base_depth + (float(i) + 0.5) / float(layers) * 10.0)
		add_child(instance)
		result.append(instance)

	return result

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	var origin := camera.get_screen_center_position() if camera else Vector2.ZERO

	queue_redraw()

	for layer in dust_layers:
		layer.position = origin * (DUST_PARALLAX / float(layer.get_meta("depth")))

	for layer in star_layers:
		layer.position = origin * (STAR_PARALLAX / float(layer.get_meta("depth")))

func _draw() -> void:
	var camera := get_viewport().get_camera_2d()
	var view := get_viewport_rect().size
	var extent := view / (camera.zoom if camera else Vector2.ONE)
	var center := camera.get_screen_center_position() if camera else Vector2.ZERO
	draw_rect(Rect2(to_local(center) - extent, extent * 2.0), space_color)
