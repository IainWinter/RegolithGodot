extends SceneTree

# writes game/images/generated/pipes_sample.png: the python default strip
# (72x270, seed 3) next to a 200x270 menu border with the PipeBorderUI preset,
# on a dark background so the transparent parts read. run headless:
#   godot --headless --path . -s game/scripts/generation/RenderPipeSample.gd

const OUT := "res://game/images/generated/pipes_sample.png"

func _init() -> void:
	var start := Time.get_ticks_usec()
	var plate := PipeGenerator.generate_image(72, 270, 3)
	var plate_ms := (Time.get_ticks_usec() - start) / 1000.0

	start = Time.get_ticks_usec()
	var gen := PipeGenerator.new()
	gen.seed = PipeGenerator.MENU_SEED
	gen.erosion = PipeGenerator.MENU_EROSION
	gen.rust = PipeGenerator.MENU_RUST
	gen.tuning.merge(PipeGenerator.MENU_TUNING, true)
	var border := gen.make_border(Vector2i(200, 270), PipeGenerator.MENU_THICKNESS)
	var border_ms := (Time.get_ticks_usec() - start) / 1000.0

	var out := Image.create(72 + 8 + 200, 270, false, Image.FORMAT_RGBA8)
	out.fill(Color8(12, 10, 20))
	out.blend_rect(plate, Rect2i(0, 0, 72, 270), Vector2i(0, 0))
	out.blend_rect(border, Rect2i(0, 0, 200, 270), Vector2i(80, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := out.save_png(OUT)
	print("pipes_sample: %s (%d) plate %.1f ms, border %.1f ms" % [OUT, err, plate_ms, border_ms])
	quit()
