extends GutTest

# DebugSpawnPanel: the backtick action opens and closes it, escape closes it,
# it lists every spawnable kind but messages plus every RockProps in the
# config folder, and a drag from a card to a screen point sends a
# SpawnRequest of that kind at the matching world spot with the ghost's
# facing, placed at once. the gun and the turret carry a size that rides on
# the request as scale_cells meta. a plain click spawns at the click spot or
# under the cursor with the toggle on, escape drops a drag, the ghost draws
# at the camera's zoom

const SCENES := {
	SpawnRequest.Kind.FIGHTER: "res://game/scenes/enemies/EnemyFighter.tscn",
	SpawnRequest.Kind.BOMB: "res://game/scenes/enemies/EnemyBomb.tscn",
	SpawnRequest.Kind.STATION: "res://game/scenes/enemies/EnemyStation.tscn",
	SpawnRequest.Kind.BASE: "res://game/scenes/enemies/EnemyBase.tscn",
	SpawnRequest.Kind.BOSS_COMPASS: "res://game/scenes/enemies/EnemyBossCompass.tscn",
	SpawnRequest.Kind.BOSS_STINGRAY: "res://game/scenes/enemies/EnemyBossStingray.tscn",
	SpawnRequest.Kind.GUN: "res://game/scenes/enemies/EnemyGun.tscn",
	SpawnRequest.Kind.TURRET: "res://game/scenes/enemies/EnemyTurret.tscn",
}
const MESSAGE_SCENE := "res://game/scenes/ai/AiMessage.tscn"
const ROCK_PROPS_DIR := "res://game/config/rocks"
const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const SPRITE_MATERIAL := preload("res://game/shaders/regolith_sprite_material.tres")
const ROPE_MATERIAL := preload("res://game/shaders/regolith_rope_material.tres")

const CAMERA_AT := Vector2(320.0, -96.0)
const CAMERA_ZOOM := 2.0

var arena: Node2D
var world: RegolithWorld
var spawner: StableSpawner
var camera: Camera2D
var panel: DebugSpawnPanel

func before_each() -> void:
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena

	world = RegolithWorld.new()
	world.pixels_per_cell = 2
	var particles := GPUParticles2D.new()
	particles.process_material = CELL_PARTICLES_MATERIAL
	world.add_child(particles)
	arena.add_child(world)

	spawner = StableSpawner.new()
	spawner.fighter_scene = load(SCENES[SpawnRequest.Kind.FIGHTER])
	spawner.bomb_scene = load(SCENES[SpawnRequest.Kind.BOMB])
	spawner.station_scene = load(SCENES[SpawnRequest.Kind.STATION])
	spawner.base_scene = load(SCENES[SpawnRequest.Kind.BASE])
	spawner.boss_compass_scene = load(SCENES[SpawnRequest.Kind.BOSS_COMPASS])
	spawner.boss_stingray_scene = load(SCENES[SpawnRequest.Kind.BOSS_STINGRAY])
	spawner.gun_scene = load(SCENES[SpawnRequest.Kind.GUN])
	spawner.turret_scene = load(SCENES[SpawnRequest.Kind.TURRET])
	spawner.message_scene = load(MESSAGE_SCENE)
	spawner.sprite_material = SPRITE_MATERIAL
	spawner.rope_material = ROPE_MATERIAL
	arena.add_child(spawner)

	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = CAMERA_AT
	camera.zoom = Vector2.ONE * CAMERA_ZOOM
	arena.add_child(camera)

	panel = DebugSpawnPanel.new()
	arena.add_child(panel)
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()
	Dialog.clear()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	return event

func mouse_button(index: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event

func mouse_motion(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	return event

func press_toggle() -> void:
	panel._unhandled_input(key(KEY_QUOTELEFT))

# a screen point in the card's own coordinates, what its _gui_input sees
func entry_local(entry: DebugSpawnPanel.Entry, screen: Vector2) -> Vector2:
	return entry.get_global_transform_with_canvas().affine_inverse() * screen

func entry_center(entry: DebugSpawnPanel.Entry) -> Vector2:
	return entry.get_global_rect().get_center()

# where a screen point lands in units, the camera's view at its zoom
func expected_units(screen: Vector2) -> Vector2:
	var view := panel.get_viewport().get_visible_rect().size
	return (CAMERA_AT + (screen - view * 0.5) / CAMERA_ZOOM) / ppu()

func rock_props_count() -> int:
	var count := 0
	for file in DirAccess.get_files_at(ROCK_PROPS_DIR):
		if file.get_extension() == "tres":
			count += 1
	return count

func watch(request: SpawnRequest) -> Dictionary:
	var seen := {"node": null, "expired": false}
	request.spawned.connect(func(node):
		seen["node"] = node
		seen["position"] = node.global_position
		seen["rotation"] = node.global_rotation)
	request.expired.connect(func(): seen["expired"] = true)
	return seen

# a full drag through the panel's own methods
func drag(kind: SpawnRequest.Kind, from: Vector2, to: Vector2, turns := 0) -> SpawnRequest:
	assert_true(panel.begin_drag(kind, from), "drag of %s started" % SpawnRequest.Kind.keys()[kind])
	panel.update_drag(to)
	for i in turns:
		panel.rotate_drag(DebugSpawnPanel.ROTATE_STEP)
	return panel.end_drag(to)

func test_action_is_bound_to_backtick() -> void:
	assert_true(InputMap.has_action(DebugSpawnPanel.ACTION), "spawn_panel action in the input map")
	assert_true(InputMap.event_is_action(key(KEY_QUOTELEFT), DebugSpawnPanel.ACTION), "backtick fires it")

func test_toggles_with_the_action_and_escape_closes() -> void:
	assert_false(panel.is_open(), "starts closed")
	assert_false(panel.root.visible)

	press_toggle()
	assert_true(panel.is_open(), "backtick opens")
	assert_true(panel.root.visible)

	press_toggle()
	assert_false(panel.is_open(), "backtick again closes")

	press_toggle()
	panel._unhandled_input(key(KEY_ESCAPE))
	assert_false(panel.is_open(), "escape closes")

	panel._unhandled_input(key(KEY_ESCAPE))
	assert_false(panel.is_open(), "escape while closed stays closed")
	assert_false(get_tree().paused, "the game never pauses")

func test_lists_every_kind_but_message_plus_the_rock_props() -> void:
	var kinds := {}
	for entry in panel.entries:
		if not entry.is_rock():
			kinds[entry.kind] = true

	for kind in SpawnRequest.Kind.values():
		if kind == SpawnRequest.Kind.MESSAGE or kind == SpawnRequest.Kind.ROCK:
			assert_false(kinds.has(kind), "%s is not listed" % SpawnRequest.Kind.keys()[kind])
		else:
			assert_true(kinds.has(kind), "%s is listed" % SpawnRequest.Kind.keys()[kind])

	var rocks := panel.rock_entries()
	assert_gt(rock_props_count(), 0, "there is at least one RockProps to find")
	assert_eq(rocks.size(), rock_props_count(), "one entry per RockProps resource")

	for rock in rocks:
		assert_true(rock.rock_props is RockProps, "%s carries RockProps" % rock.label)
		assert_eq(rock.drag_data()["rock_props"], rock.rock_props, "the drag data carries the props")
		assert_not_null(rock.preview, "%s has a generated preview" % rock.label)
		assert_eq(rock.art, rock.preview, "the rock's art is its preview")

	var fighter := panel.entry_for(SpawnRequest.Kind.FIGHTER)
	assert_not_null(fighter)
	assert_true(fighter.enabled, "kinds with a scene can be dragged")
	assert_eq(fighter.label, "fighter")
	var sample: RegolithSprite = load(SCENES[SpawnRequest.Kind.FIGHTER]).instantiate()
	assert_eq(fighter.preview, sample.texture, "preview is the scene's texture")
	assert_eq(fighter.art, sample.texture)
	sample.free()
	assert_eq(fighter.drag_data()["spawn_kind"], SpawnRequest.Kind.FIGHTER)
	assert_eq(fighter.scale_cells, 0, "the fighter has no size")
	assert_null(fighter.size_field)

	var item := panel.entry_for(SpawnRequest.Kind.ITEM)
	assert_not_null(item)
	assert_false(item.enabled, "no scene, cannot be dragged")
	assert_null(item.art, "no art")
	assert_not_null(item.preview, "the placeholder icon")
	assert_eq(spawner.pending(), 0, "listing spawns nothing")

func test_gun_and_turret_carry_a_size_field_with_their_defaults() -> void:
	var gun := panel.entry_for(SpawnRequest.Kind.GUN)
	var turret := panel.entry_for(SpawnRequest.Kind.TURRET)
	assert_true(gun.enabled)
	assert_true(turret.enabled)
	assert_true(gun.is_sized())
	assert_true(turret.is_sized())
	assert_eq(gun.scale_cells, 32, "the gun's art size")
	assert_eq(turret.scale_cells, 96, "the large turret")
	assert_not_null(gun.size_field)
	assert_eq(gun.size_field.value, 32.0)
	assert_eq(turret.size_field.value, 96.0)
	assert_eq(gun.art_cells(), Vector2(32.0, 32.0))
	assert_eq(turret.art_cells(), Vector2(96.0, 96.0))

	turret.size_field.value = 128
	assert_eq(turret.scale_cells, 128, "the field sets the size")
	assert_eq(turret.drag_data()["scale_cells"], 128)
	assert_eq(turret.art_cells(), Vector2(128.0, 128.0), "the ghost grows with it")

func test_drag_sends_the_kind_at_the_world_spot() -> void:
	press_toggle()
	var screen := Vector2(200.0, 150.0)
	var fighter := panel.entry_for(SpawnRequest.Kind.FIGHTER)
	watch_signals(panel)

	var request := drag(SpawnRequest.Kind.FIGHTER, entry_center(fighter), screen)

	assert_not_null(request, "a request was sent")
	assert_eq(request, panel.last_request)
	assert_signal_emitted_with_parameters(panel, "dropped", [request])
	assert_signal_emitted(panel, "drag_started")
	assert_signal_emitted(panel, "drag_ended")
	assert_false(panel.is_dragging(), "the drag is over")
	assert_false(panel.ghost.visible, "the ghost is gone")
	assert_eq(request.kind, SpawnRequest.Kind.FIGHTER)
	assert_false(request.wait_for_room, "placed at once")
	assert_false(request.offscreen_only)
	assert_eq(request.rotation, 0.0, "not turned")
	assert_almost_eq(request.position, expected_units(screen), Vector2.ONE * 0.01, "screen point through the camera to units")
	assert_eq(spawner.pending(), 1, "queued on the StableSpawner")

	var seen := watch(request)
	await wait_physics_frames(2)

	assert_not_null(seen["node"], "spawned by the StableSpawner")
	assert_true(seen["node"] is RegolithSprite)
	assert_almost_eq(seen["position"], expected_units(screen) * ppu(), Vector2.ONE * 0.5, "lands at the drop spot")
	assert_true(seen["node"].is_in_group("regolith"))

func test_gun_drag_spawns_an_enemy_gun_at_the_spot_with_the_ghosts_facing() -> void:
	press_toggle()
	var screen := Vector2(240.0, 200.0)
	var gun := panel.entry_for(SpawnRequest.Kind.GUN)

	var request := drag(SpawnRequest.Kind.GUN, entry_center(gun), screen, 3)

	assert_not_null(request)
	assert_eq(request.kind, SpawnRequest.Kind.GUN)
	assert_almost_eq(request.rotation, DebugSpawnPanel.ROTATE_STEP * 3.0, 0.0001, "three notches of turn")
	assert_eq(request.get_meta(EnemyGun.META_SCALE_CELLS), 32, "the size rides as meta")
	assert_almost_eq(request.position, expected_units(screen), Vector2.ONE * 0.01)

	var seen := watch(request)
	await wait_physics_frames(2)

	var node: RegolithSprite = seen["node"]
	assert_not_null(node, "the gun spawned")
	if node == null:
		return

	assert_true(node is EnemyGun, "an EnemyGun")
	assert_true(node.is_in_group("gun"))
	assert_false(node.is_in_group("turret"))
	assert_almost_eq(seen["position"], expected_units(screen) * ppu(), Vector2.ONE * 0.5, "at the drop spot")
	assert_almost_eq(seen["rotation"], DebugSpawnPanel.ROTATE_STEP * 3.0, 0.02, "facing the ghost's way")
	assert_eq(node.art_cells, 32, "built at the field's size")
	assert_true(node.has_barrel(), "mount and barrel")
	assert_eq(get_tree().get_nodes_in_group("gun").filter(func(n): return n is EnemyGun).size(), 1, "one gun")

func test_turret_drag_passes_scale_cells_and_spawns_the_large_turret() -> void:
	press_toggle()
	var screen := Vector2(300.0, 260.0)
	var turret := panel.entry_for(SpawnRequest.Kind.TURRET)

	var request := drag(SpawnRequest.Kind.TURRET, entry_center(turret), screen)

	assert_not_null(request)
	assert_eq(request.kind, SpawnRequest.Kind.TURRET)
	assert_true(request.has_meta(EnemyGun.META_SCALE_CELLS))
	assert_eq(request.get_meta(EnemyGun.META_SCALE_CELLS), 96, "the default size")

	var seen := watch(request)
	await wait_physics_frames(2)

	var node: RegolithSprite = seen["node"]
	assert_not_null(node, "the turret spawned")
	if node == null:
		return

	assert_true(node is EnemyGun)
	assert_true(node.is_in_group("turret"))
	assert_eq(node.get_meta(EnemyGun.META_SCALE_CELLS), 96, "the meta rode onto the node")
	assert_eq(node.art_cells, 96, "built large")
	assert_gt(node.get_cell_count().x, int(96 * 0.9), "cells across follow the size")
	assert_almost_eq(seen["position"], expected_units(screen) * ppu(), Vector2.ONE * 0.5)

func test_size_field_changes_the_meta_on_the_next_drag() -> void:
	press_toggle()
	var turret := panel.entry_for(SpawnRequest.Kind.TURRET)
	turret.size_field.value = 64

	var request := drag(SpawnRequest.Kind.TURRET, entry_center(turret), Vector2(300.0, 260.0))

	assert_eq(request.get_meta(EnemyGun.META_SCALE_CELLS), 64, "the field's value")

func test_drag_of_a_rock_entry_spawns_a_rock_with_its_props() -> void:
	press_toggle()
	var rock := panel.rock_entries()[0]
	var screen := Vector2(600.0, 400.0)

	assert_true(panel.begin_entry_drag(rock, entry_center(rock)))
	panel.update_drag(screen)
	var request := panel.end_drag(screen)

	assert_eq(request.kind, SpawnRequest.Kind.ROCK)
	assert_eq(request.rock_props, rock.rock_props, "the entry's props ride on the request")
	assert_false(request.wait_for_room)
	assert_almost_eq(request.position, expected_units(screen), Vector2.ONE * 0.01)

	var seen := watch(request)
	await wait_physics_frames(2)

	assert_not_null(seen["node"], "rock spawned")
	assert_gt(seen["node"].get_active_cell_count(), 0, "rock has cells")
	assert_almost_eq(seen["position"], expected_units(screen) * ppu(), Vector2.ONE * 0.5)

func test_mouse_events_on_the_entry_drive_the_drag() -> void:
	press_toggle()
	var gun := panel.entry_for(SpawnRequest.Kind.GUN)
	var start := entry_center(gun)
	var screen := Vector2(220.0, 180.0)

	gun._gui_input(mouse_button(MOUSE_BUTTON_LEFT, true, entry_local(gun, start)))
	assert_eq(panel.drag_entry, gun, "the press arms the card")
	assert_false(panel.is_dragging(), "not dragging yet")

	gun._gui_input(mouse_motion(entry_local(gun, start + Vector2(2.0, 0.0))))
	assert_false(panel.is_dragging(), "a wobble under the threshold is still a click")

	gun._gui_input(mouse_motion(entry_local(gun, start + Vector2(-DebugSpawnPanel.DRAG_THRESHOLD * 2.0, 0.0))))
	assert_true(panel.is_dragging(), "pulling away starts the drag")
	assert_true(panel.ghost.visible)
	assert_eq(panel.ghost.texture, gun.art, "the ghost shows the gun")

	# off the card the panel takes the events itself
	panel._input(mouse_motion(screen))
	assert_eq(panel.ghost.screen, screen, "the ghost follows")
	panel._input(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, screen))
	panel._input(mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, screen))
	assert_almost_eq(panel.drag_rotation, DebugSpawnPanel.ROTATE_STEP * 2.0, 0.0001, "the wheel turns it")
	panel._input(mouse_button(MOUSE_BUTTON_WHEEL_UP, true, screen))
	assert_almost_eq(panel.drag_rotation, DebugSpawnPanel.ROTATE_STEP, 0.0001, "back one notch")
	panel._input(key(KEY_E))
	panel._input(key(KEY_E))
	assert_almost_eq(panel.drag_rotation, DebugSpawnPanel.ROTATE_STEP * 3.0, 0.0001, "E turns clockwise")
	panel._input(key(KEY_Q))
	assert_almost_eq(panel.drag_rotation, DebugSpawnPanel.ROTATE_STEP * 2.0, 0.0001, "Q turns back")
	assert_almost_eq(panel.ghost.angle, DebugSpawnPanel.ROTATE_STEP * 2.0, 0.0001, "the ghost shows the turn")

	panel._input(mouse_button(MOUSE_BUTTON_LEFT, false, screen))
	assert_false(panel.is_dragging(), "the release ends it")
	assert_null(panel.drag_entry)

	var request := panel.last_request
	assert_not_null(request)
	assert_eq(request.kind, SpawnRequest.Kind.GUN)
	assert_almost_eq(request.rotation, DebugSpawnPanel.ROTATE_STEP * 2.0, 0.0001)
	assert_almost_eq(request.position, expected_units(screen), Vector2.ONE * 0.01)
	assert_eq(request.get_meta(EnemyGun.META_SCALE_CELLS), 32)
	assert_eq(spawner.pending(), 1)

func test_escape_cancels_the_drag_and_spawns_nothing() -> void:
	press_toggle()
	var gun := panel.entry_for(SpawnRequest.Kind.GUN)
	watch_signals(panel)

	assert_true(panel.begin_drag(SpawnRequest.Kind.GUN, entry_center(gun)))
	panel.update_drag(Vector2(200.0, 200.0))
	panel.rotate_drag(DebugSpawnPanel.ROTATE_STEP)
	panel._input(key(KEY_ESCAPE))

	assert_false(panel.is_dragging(), "dropped")
	assert_null(panel.drag_entry)
	assert_false(panel.ghost.visible, "the ghost is gone")
	assert_eq(panel.drag_rotation, 0.0, "the turn is forgotten")
	assert_true(panel.is_open(), "escape during a drag leaves the panel open")
	assert_signal_emitted(panel, "drag_ended")
	assert_signal_not_emitted(panel, "dropped")
	assert_null(panel.last_request, "nothing sent")
	assert_eq(spawner.pending(), 0, "nothing queued")

	# a release with nothing held does nothing either
	panel._input(mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(200.0, 200.0)))
	assert_eq(spawner.pending(), 0)

	await wait_physics_frames(2)
	assert_eq(get_tree().get_nodes_in_group("gun").size(), 0, "no gun in the world")

func test_release_over_the_panel_spawns_nothing() -> void:
	press_toggle()
	var fighter := panel.entry_for(SpawnRequest.Kind.FIGHTER)
	var over_panel := entry_center(fighter) + Vector2(0.0, 60.0)
	assert_true(panel.over_window(over_panel))

	assert_true(panel.begin_drag(SpawnRequest.Kind.FIGHTER, entry_center(fighter)))
	panel.update_drag(Vector2(200.0, 200.0))
	panel.update_drag(over_panel)
	var request := panel.end_drag(over_panel)

	assert_null(request, "dropped back on the panel")
	assert_false(panel.is_dragging())
	assert_null(panel.last_request)
	assert_eq(spawner.pending(), 0)

func test_closing_the_panel_cancels_the_drag() -> void:
	press_toggle()
	assert_true(panel.begin_drag(SpawnRequest.Kind.FIGHTER, Vector2(700.0, 100.0)))
	press_toggle()
	assert_false(panel.is_open())
	assert_false(panel.is_dragging())
	assert_false(panel.ghost.visible)
	assert_eq(spawner.pending(), 0)

func test_a_disabled_entry_cannot_be_dragged() -> void:
	press_toggle()
	assert_false(panel.begin_drag(SpawnRequest.Kind.ITEM, Vector2(700.0, 100.0)), "no scene, no drag")
	assert_false(panel.is_dragging())
	var item := panel.entry_for(SpawnRequest.Kind.ITEM)
	item._gui_input(mouse_button(MOUSE_BUTTON_LEFT, true, Vector2.ZERO))
	assert_null(panel.drag_entry, "a press on it arms nothing")

func test_plain_click_spawns_at_the_click_spot() -> void:
	press_toggle()
	var fighter := panel.entry_for(SpawnRequest.Kind.FIGHTER)
	var at := entry_center(fighter)
	watch_signals(panel)

	fighter._gui_input(mouse_button(MOUSE_BUTTON_LEFT, true, entry_local(fighter, at)))
	fighter._gui_input(mouse_button(MOUSE_BUTTON_LEFT, false, entry_local(fighter, at)))

	assert_signal_not_emitted(panel, "drag_started", "a click is not a drag")
	assert_false(panel.ghost.visible)
	assert_null(panel.drag_entry)

	var request := panel.last_request
	assert_not_null(request, "a click spawns")
	assert_signal_emitted_with_parameters(panel, "dropped", [request])
	assert_eq(request.kind, SpawnRequest.Kind.FIGHTER)
	assert_false(request.wait_for_room)
	assert_eq(request.rotation, 0.0)
	var view := panel.get_viewport().get_visible_rect().size
	assert_eq(panel.click_spot(), view * 0.5 + view * DebugSpawnPanel.CLICK_SPOT, "left of the view center, away from the panel")
	assert_almost_eq(request.position, expected_units(panel.click_spot()), Vector2.ONE * 0.01, "at the click spot")
	assert_eq(spawner.pending(), 1)

	var seen := watch(request)
	await wait_physics_frames(2)
	assert_not_null(seen["node"], "spawned as before")

func test_spawn_at_cursor_toggle_moves_the_click_spawn_under_the_mouse() -> void:
	press_toggle()
	assert_false(panel.spawn_at_cursor, "off by default")
	assert_not_null(panel.cursor_check)
	assert_false(panel.cursor_check.button_pressed)

	panel.cursor_check.button_pressed = true
	assert_true(panel.spawn_at_cursor, "the check box sets it")

	panel.set_spawn_at_cursor(false)
	assert_false(panel.cursor_check.button_pressed, "and follows it")
	panel.set_spawn_at_cursor(true)

	var gun := panel.entry_for(SpawnRequest.Kind.GUN)
	var request := panel.click_entry(gun)
	var mouse := panel.get_viewport().get_mouse_position()

	assert_not_null(request)
	assert_eq(request.kind, SpawnRequest.Kind.GUN)
	assert_almost_eq(request.position, panel.screen_to_units(mouse), Vector2.ONE * 0.01, "under the cursor")
	assert_eq(request.get_meta(EnemyGun.META_SCALE_CELLS), 32, "the size still rides along")

	panel.set_spawn_at_cursor(false)
	var plain := panel.click_entry(gun)
	assert_almost_eq(plain.position, expected_units(panel.click_spot()), Vector2.ONE * 0.01, "off again, the click spot")

func test_ghost_scales_with_the_camera_zoom_and_shows_the_size() -> void:
	press_toggle()
	var screen := Vector2(300.0, 300.0)
	var cell := RegolithWorld.pixels_per_cell()

	assert_true(panel.begin_drag(SpawnRequest.Kind.FIGHTER, screen))
	assert_true(panel.ghost.visible)
	assert_eq(panel.ghost.screen, screen)
	assert_almost_eq(panel.ghost.scale_by, cell * CAMERA_ZOOM, 0.0001, "screen pixels per cell at the camera's zoom")
	assert_eq(DebugSpawnPanel.world_scale(panel.get_viewport()), panel.ghost.scale_by)
	var fighter := panel.entry_for(SpawnRequest.Kind.FIGHTER)
	assert_eq(panel.ghost.cells, Vector2(fighter.art.get_size()), "the art's cells")
	var rect := panel.ghost.rect()
	assert_eq(rect.size, panel.ghost.padded() * cell * CAMERA_ZOOM, "the padded grid at world scale")
	assert_eq(rect.get_center(), screen, "centered on the cursor")

	camera.zoom = Vector2.ONE * CAMERA_ZOOM * 2.0
	panel.update_drag(screen)
	assert_almost_eq(panel.ghost.scale_by, cell * CAMERA_ZOOM * 2.0, 0.0001, "zooming in doubles it")
	assert_eq(panel.ghost.rect().size, rect.size * 2.0)

	camera.zoom = Vector2.ONE * CAMERA_ZOOM
	panel.cancel_drag()

	assert_true(panel.begin_drag(SpawnRequest.Kind.TURRET, screen))
	assert_eq(panel.ghost.cells, Vector2(96.0, 96.0), "the turret's size")
	assert_eq(panel.ghost.padded(), Vector2(96.0, 96.0), "three chunks")
	assert_eq(panel.ghost.rect().size, Vector2(96.0, 96.0) * cell * CAMERA_ZOOM)
	panel.cancel_drag()

	assert_true(panel.begin_drag(SpawnRequest.Kind.BOMB, screen))
	var bomb := panel.entry_for(SpawnRequest.Kind.BOMB)
	assert_eq(panel.ghost.cells, Vector2(bomb.art.get_size()))
	assert_eq(panel.ghost.padded(), Vector2(32.0, 32.0), "small art still sits in a whole chunk")
	panel.cancel_drag()

func test_screen_to_units_without_a_camera_is_plain_pixels() -> void:
	camera.enabled = false
	assert_null(panel.get_viewport().get_camera_2d())
	assert_eq(panel.screen_to_units(Vector2(64.0, 32.0)), Vector2(64.0, 32.0) / ppu())
	assert_eq(DebugSpawnPanel.world_scale(panel.get_viewport()), RegolithWorld.pixels_per_cell(), "one cell's pixels with no camera")

func test_grab_pulls_a_dynamic_sprite_and_release_stops_it() -> void:
	press_toggle()
	var screen := Vector2(200.0, 150.0)
	var fighter := panel.entry_for(SpawnRequest.Kind.FIGHTER)
	drag(SpawnRequest.Kind.FIGHTER, entry_center(fighter), screen)
	var seen := watch(panel.last_request)
	await wait_physics_frames(3)
	var sprite: RegolithSprite = seen["node"]
	assert_not_null(sprite)

	assert_false(panel.grab(Vector2(2.0, 2.0)), "nothing at the corner")
	assert_true(panel.grab(screen), "the sprite under the point")
	assert_eq(panel.grabbed, sprite)

	var away := screen + Vector2(120.0, 0.0)
	var target := panel.screen_to_units(away)
	var at := sprite.global_position / ppu()
	sprite.linear_velocity = (target - at) * DebugSpawnPanel.GRAB_GAIN
	assert_gt(sprite.linear_velocity.x, 0.0, "pulled toward the cursor")

	assert_true(panel.release())
	assert_null(panel.grabbed)
	assert_eq(sprite.linear_velocity, Vector2.ZERO, "let go")
	assert_false(panel.release(), "nothing held")
