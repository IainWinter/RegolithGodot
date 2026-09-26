extends SceneTree

# writes two look-at pngs into game/images/generated/, 3x nearest upscaled:
#   pipes_manual_sample.png      a hand PipeLayout (the PipeFrameDemo one)
#                                rendered MANUAL, then the same layout MIXED
#   pipes_horizontal_sample.png  a 270x72 plate with flow HORIZONTAL next to
#                                the same seed with flow VERTICAL
# run headless:
#   godot --headless --path . -s game/scripts/generation/RenderPipeLayoutSamples.gd

const OUT_DIR := "res://game/images/generated"
const SCALE := 3

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	write_manual()
	write_horizontal()
	quit()

func demo_layout() -> PipeLayout:
	var scene: PackedScene = load("res://game/editors/PipeFrameDemo.tscn")
	var root := scene.instantiate()
	var frame: PipeFrame = root.get_node("ManualZone")
	var layout: PipeLayout = frame.layout.duplicate()
	root.free()
	return layout

func frame_image(layout: PipeLayout, placement: int, flow: int, seed: int) -> Image:
	var frame := PipeFrame.new()
	frame.mode = PipeFrame.Mode.PLATE
	frame.size = Vector2(120, 72)
	frame.cell_size = 12
	frame.placement = placement
	frame.flow = flow
	frame.seed = seed
	frame.erosion = 0.1
	frame.rust = 0.6
	frame.layout = layout.duplicate()
	var image := frame.generate_image()
	frame.free()
	return image

func write_manual() -> void:
	var layout := demo_layout()
	var manual := frame_image(layout, PipeFrame.LayoutMode.MANUAL, PipeGenerator.Flow.AUTO, 11)
	var mixed := frame_image(layout, PipeFrame.LayoutMode.MIXED, PipeGenerator.Flow.HORIZONTAL, 5)
	var out := Image.create(120 * 2 + 8, 72, false, Image.FORMAT_RGBA8)
	out.fill(Color8(12, 10, 20))
	out.blend_rect(manual, Rect2i(0, 0, 120, 72), Vector2i(0, 0))
	out.blend_rect(mixed, Rect2i(0, 0, 120, 72), Vector2i(128, 0))
	save(out, "pipes_manual_sample.png")

func write_horizontal() -> void:
	var horizontal := PipeGenerator.generate_image(270, 72, 3, Vector3(-0.62, -0.66, 0.42), 0.25, 1.0, Color.WHITE, [], false,
		PipeGenerator.Flow.HORIZONTAL)
	var vertical := PipeGenerator.generate_image(270, 72, 3, Vector3(-0.62, -0.66, 0.42), 0.25, 1.0, Color.WHITE, [], false,
		PipeGenerator.Flow.VERTICAL)
	var out := Image.create(270, 72 * 2 + 8, false, Image.FORMAT_RGBA8)
	out.fill(Color8(12, 10, 20))
	out.blend_rect(horizontal, Rect2i(0, 0, 270, 72), Vector2i(0, 0))
	out.blend_rect(vertical, Rect2i(0, 0, 270, 72), Vector2i(0, 80))
	save(out, "pipes_horizontal_sample.png")

func save(image: Image, file: String) -> void:
	image.resize(image.get_width() * SCALE, image.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	var path := OUT_DIR.path_join(file)
	var err := image.save_png(path)
	print("%s (%d) %dx%d" % [path, err, image.get_width(), image.get_height()])
