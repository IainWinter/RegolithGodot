extends GutTest

# the raster toggles of the debug spawn panel: lightning switches between
# the cell shader multimesh and the smooth line draw, bullets / effects and
# everything put a RasterView with a SubViewport in the tree that shares
# the root's canvas and tags what it draws with a visibility layer the
# root stops drawing, everything wins over effects, and turning them off
# takes the view out and restores every layer and the cull mask. the
# settings hold the choices. no scene reload anywhere

const LIGHTNING_MATERIAL := preload("res://game/shaders/regolith_lightning_material.tres")
const DEFAULT_LIGHTNING := preload("res://game/config/effects/default_lightning.tres")
const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")
const CANNON_PROPS := preload("res://game/config/weapons/default_cannon.tres")

var arena: Node2D
var world: RegolithWorld
var camera: Camera2D
var rock: RegolithSprite
var panel: DebugSpawnPanel
var settings: Node
var saved := {}

func make_texture() -> ImageTexture:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.4, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

func before_each() -> void:
	settings = RasterMode.settings_node(get_tree())
	saved = {"lightning": settings.raster_lightning, "effects": settings.raster_effects, "world": settings.raster_world}
	settings.raster_lightning = true
	settings.raster_effects = false
	settings.raster_world = false

	arena = Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena

	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)

	rock = RegolithSprite.new()
	rock.texture = make_texture()
	rock.material = SPRITE_MATERIAL
	rock.position = Vector2(300, 200)
	arena.add_child(rock)

	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = Vector2(320.0, -96.0)
	camera.zoom = Vector2.ONE * 2.0
	arena.add_child(camera)

	panel = DebugSpawnPanel.new()
	arena.add_child(panel)
	await wait_physics_frames(1)

func after_each() -> void:
	settings.raster_lightning = saved["lightning"]
	settings.raster_effects = saved["effects"]
	settings.raster_world = saved["world"]
	settings.save()
	RasterMode.apply(get_tree())
	get_tree().current_scene = null
	arena.free()
	Lightning.pixelated = true

func root_mask() -> int:
	return get_tree().root.canvas_cull_mask

func make_lightning() -> Lightning:
	var lightning := Lightning.new()
	lightning.props = DEFAULT_LIGHTNING
	lightning.material = LIGHTNING_MATERIAL
	arena.add_child(lightning)
	return lightning

func make_bullet() -> Bullet:
	var bullet := Bullet.new()
	bullet.setup(CANNON_PROPS, Vector2(10.0, 10.0), Vector2.RIGHT, Vector2.ZERO, null)
	arena.add_child(bullet)
	return bullet

func test_panel_has_the_three_checks_matching_the_settings() -> void:
	assert_not_null(panel.raster_lightning)
	assert_not_null(panel.raster_effects)
	assert_not_null(panel.raster_world)
	assert_true(panel.raster_lightning.button_pressed, "lightning follows the setting")
	assert_false(panel.raster_effects.button_pressed)
	assert_false(panel.raster_world.button_pressed)
	assert_null(RasterMode.active(get_tree()), "no view with both raster modes off")
	assert_eq(root_mask() & RasterView.RASTER_LAYER, RasterView.RASTER_LAYER, "root draws the raster layer while no view is up")

func test_lightning_toggle_switches_the_draw_path() -> void:
	var lightning := make_lightning()
	lightning.strike(Vector2(40, 40), Vector2(160, 120))
	await wait_process_frames(2)

	assert_true(lightning.instance.visible, "pixel path draws the multimesh")
	assert_false(lightning.smooth.visible)
	assert_gt(lightning.multimesh.visible_instance_count, 0, "instances uploaded")

	panel.raster_lightning.button_pressed = false
	assert_false(settings.raster_lightning, "setting follows the check")
	assert_false(Lightning.pixelated)

	lightning.strike(Vector2(40, 40), Vector2(160, 120))
	await wait_process_frames(2)

	assert_false(lightning.instance.visible, "smooth path hides the multimesh")
	assert_true(lightning.smooth.visible, "and shows the line draw")
	assert_eq(lightning.multimesh.visible_instance_count, 0, "no instances shown")
	assert_gt(lightning.get_segment_count(), 0, "segments still written for the lines")

	panel.raster_lightning.button_pressed = true
	lightning.strike(Vector2(40, 40), Vector2(160, 120))
	await wait_process_frames(2)

	assert_true(lightning.instance.visible, "pixel path is back")
	assert_false(lightning.smooth.visible)
	assert_null(RasterMode.active(get_tree()), "lightning alone never makes a view")

func test_effects_toggle_installs_a_view_that_tags_only_effects() -> void:
	var bullet := make_bullet()
	var lightning := make_lightning()
	await wait_process_frames(1)

	panel.raster_effects.button_pressed = true
	assert_true(settings.raster_effects)

	var view := RasterMode.active(get_tree())
	assert_not_null(view, "a RasterView went in")
	assert_eq(view.mode, RasterView.Mode.EFFECTS)
	assert_eq(view.get_parent(), arena, "under the current scene")
	assert_not_null(view.sub, "with a SubViewport")
	assert_eq(view.sub.world_2d, get_tree().root.world_2d, "sharing the root's canvas")
	assert_eq(view.sub.canvas_cull_mask, RasterView.RASTER_LAYER, "sub draws only the raster layer")
	assert_true(view.sub.transparent_bg, "effects composite over the native world")
	assert_eq(root_mask() & RasterView.RASTER_LAYER, 0, "root no longer draws the raster layer")
	assert_eq(view.display.texture, view.sub.get_texture(), "display shows the sub")
	assert_eq(view.display.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)

	assert_eq(bullet.visibility_layer, RasterView.RASTER_LAYER, "bullet tagged")
	assert_eq(bullet.trail.visibility_layer, RasterView.RASTER_LAYER, "its trail tagged")
	assert_eq(lightning.visibility_layer, RasterView.RASTER_LAYER, "lightning tagged")
	assert_eq(lightning.instance.visibility_layer, RasterView.RASTER_LAYER, "its multimesh tagged")
	assert_eq(world.get_child(0).visibility_layer, RasterView.RASTER_LAYER, "cell particles tagged")
	assert_eq(rock.visibility_layer, RasterView.DEFAULT_LAYER, "the rock stays native")
	assert_eq(arena.visibility_layer, RasterView.DEFAULT_LAYER, "the scene root stays native")
	assert_eq(panel.root.visibility_layer, RasterView.DEFAULT_LAYER, "the UI stays native")

	var late := make_bullet()
	await wait_process_frames(1)
	assert_eq(late.visibility_layer, RasterView.RASTER_LAYER, "a bullet spawned later is tagged")
	assert_eq(late.trail.visibility_layer, RasterView.RASTER_LAYER)

	panel.raster_effects.button_pressed = false
	await wait_process_frames(1)

	assert_null(RasterMode.active(get_tree()), "view removed")
	assert_eq(root_mask() & RasterView.RASTER_LAYER, RasterView.RASTER_LAYER, "root mask restored")
	assert_eq(bullet.visibility_layer, RasterView.DEFAULT_LAYER, "bullet layer restored")
	assert_eq(late.visibility_layer, RasterView.DEFAULT_LAYER)
	assert_eq(lightning.visibility_layer, RasterView.DEFAULT_LAYER, "lightning layer restored")
	assert_false(bullet.has_meta(RasterView.TAG), "no tag left behind")

func test_world_toggle_tags_the_whole_world_but_not_the_ui() -> void:
	panel.raster_world.button_pressed = true

	var view := RasterMode.active(get_tree())
	assert_not_null(view)
	assert_eq(view.mode, RasterView.Mode.WORLD)
	assert_false(view.sub.transparent_bg, "everything draws opaque")
	assert_eq(rock.visibility_layer, RasterView.RASTER_LAYER, "the rock goes through the sub")
	assert_eq(arena.visibility_layer, RasterView.RASTER_LAYER, "the scene root too")
	assert_eq(world.get_child(0).visibility_layer, RasterView.RASTER_LAYER, "cell particles too")
	assert_eq(panel.root.visibility_layer, RasterView.DEFAULT_LAYER, "the UI stays native")
	assert_eq(view.display.visibility_layer, RasterView.DEFAULT_LAYER, "the display quad stays native")

	var bullet := make_bullet()
	await wait_process_frames(1)
	assert_eq(bullet.visibility_layer, RasterView.RASTER_LAYER, "a later bullet is tagged")

	panel.raster_world.button_pressed = false
	await wait_process_frames(1)
	assert_null(RasterMode.active(get_tree()))
	assert_eq(rock.visibility_layer, RasterView.DEFAULT_LAYER, "rock restored")
	assert_eq(arena.visibility_layer, RasterView.DEFAULT_LAYER)
	assert_eq(bullet.visibility_layer, RasterView.DEFAULT_LAYER)

func test_world_wins_over_effects_and_falls_back_when_off() -> void:
	panel.raster_effects.button_pressed = true
	var effects_view := RasterMode.active(get_tree())
	assert_eq(effects_view.mode, RasterView.Mode.EFFECTS)

	panel.raster_world.button_pressed = true
	await wait_process_frames(1)
	var world_view := RasterMode.active(get_tree())
	assert_not_null(world_view)
	assert_eq(world_view.mode, RasterView.Mode.WORLD, "everything replaces effects")
	assert_ne(world_view, effects_view, "a new view")
	assert_false(is_instance_valid(effects_view), "the old one is gone")
	assert_eq(get_tree().get_nodes_in_group(RasterView.GROUP).size(), 1, "only one view in the tree")

	panel.raster_world.button_pressed = false
	await wait_process_frames(1)
	var back := RasterMode.active(get_tree())
	assert_not_null(back, "effects still on")
	assert_eq(back.mode, RasterView.Mode.EFFECTS, "back to effects")
	assert_eq(rock.visibility_layer, RasterView.DEFAULT_LAYER, "rock native again")

	panel.raster_effects.button_pressed = false
	assert_null(RasterMode.active(get_tree()))

func test_view_follows_the_camera_at_one_cell_per_pixel() -> void:
	panel.raster_world.button_pressed = true
	var view := RasterMode.active(get_tree())
	await wait_physics_frames(2)

	var cell := RegolithWorld.pixels_per_cell()
	var root := get_tree().root
	var screen_per_cell := root.canvas_transform.get_scale().y * cell
	assert_almost_eq(view.scale_by, screen_per_cell, 0.001, "sub pixels are cells at the camera zoom")

	var view_size := root.get_visible_rect().size
	var cells := (view_size / screen_per_cell).ceil()
	assert_gte(view.sub.size.x, int(cells.x), "sub covers the view width")
	assert_gte(view.sub.size.y, int(cells.y), "sub covers the view height")
	assert_eq(view.sub.size.x % RasterView.SIZE_STEP, 0, "stepped size")
	assert_almost_eq(view.display.size, Vector2(view.sub.size) * screen_per_cell, Vector2.ONE * 0.01, "display blows the sub back up")

	var expected := Transform2D.IDENTITY.scaled(Vector2.ONE / screen_per_cell) * root.canvas_transform
	assert_almost_eq(view.sub.canvas_transform.get_scale(), expected.get_scale(), Vector2.ONE * 0.001, "sub scale is the root's over cells")
	assert_almost_eq(view.sub.canvas_transform.origin, expected.origin.round(), Vector2.ONE * 0.001, "origin snapped to whole pixels")
	assert_eq(view.sub.canvas_transform.origin, view.sub.canvas_transform.origin.round())

	camera.zoom = Vector2.ONE * 4.0
	await wait_physics_frames(2)
	assert_almost_eq(view.scale_by, root.canvas_transform.get_scale().y * cell, 0.001, "follows a zoom change")

func test_settings_round_trip() -> void:
	panel.raster_effects.button_pressed = true
	panel.raster_lightning.button_pressed = false
	assert_eq(settings.save(), OK)

	settings.raster_effects = false
	settings.raster_lightning = true
	settings.load_settings()
	assert_true(settings.raster_effects, "effects came back from the file")
	assert_false(settings.raster_lightning, "lightning came back from the file")
	assert_false(settings.raster_world)

	var fresh := DebugSpawnPanel.new()
	arena.add_child(fresh)
	assert_true(fresh.raster_effects.button_pressed, "a fresh panel shows the saved choice")
	assert_false(fresh.raster_lightning.button_pressed)
	assert_false(Lightning.pixelated, "and applied it")
	assert_not_null(RasterMode.active(get_tree()))
	fresh.free()
