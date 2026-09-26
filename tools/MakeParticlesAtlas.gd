extends SceneTree

# builds the particle sprite sheet the ParticleEffect node draws every
# effect from, one draw call for all of them. 4x2 cells of 32 px: frames 0-5
# are the six smoke puffs of the original game downscaled, frame 6 is a
# solid white square for sparks, casings and everything the original drew
# as plain quads, frame 7 is spare. rerun after changing the sources with
#   Godot_console.exe --headless --path . -s tools/MakeParticlesAtlas.gd
# then let the editor reimport (filter nearest, no mipmaps)

const SOURCE := "C:/dev/Source/Games/RegolithSim/SourceAssets/game/sprites/smoke%d.png"
const OUTPUT := "res://game/images/effects/particles_atlas.png"
const CELL := 32
const COLUMNS := 4
const ROWS := 2
const SMOKE_FRAMES := 6
const SQUARE_FRAME := 6

func cell_origin(frame: int) -> Vector2i:
	return Vector2i(frame % COLUMNS, frame / COLUMNS) * CELL

func _init() -> void:
	var atlas := Image.create(CELL * COLUMNS, CELL * ROWS, false, Image.FORMAT_RGBA8)

	for frame in SMOKE_FRAMES:
		var smoke := Image.load_from_file(SOURCE % (frame + 1))
		if smoke == null:
			push_error("missing " + SOURCE % (frame + 1))
			quit(1)
			return
		smoke.convert(Image.FORMAT_RGBA8)
		smoke.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(smoke, Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)), cell_origin(frame))

	atlas.fill_rect(Rect2i(cell_origin(SQUARE_FRAME), Vector2i(CELL, CELL)), Color.WHITE)

	var path := ProjectSettings.globalize_path(OUTPUT)
	var err := atlas.save_png(path)
	print("particles atlas %s -> %s" % [error_string(err), path])
	quit(0 if err == OK else 1)
