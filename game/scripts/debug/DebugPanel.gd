extends CanvasLayer
class_name DebugPanel

# f3 panel over the game (Controls.DEBUG_PANEL): the world's monitors,
# pause and single step, the ai inspector and a folded list of every
# control. the debug line names, layers, colors and width are set
# from the editor's Debug Draw dock over the debugger, not from here. the
# ai section lists every scripted enemy with its state
# machine (state, time in state), the transition log of the one nearest
# the player, and floats a state label over each enemy in the world

const AI_REFRESH := 0.1
const AI_LOG_LINES := 6
const CONTROLS_HEIGHT := 320

var world: RegolithWorld

var stats: Label
var pause_check: CheckBox

var controls_fold: FoldableContainer
var controls_list: ControlsList

var ai_label: Label
var ai_labels: AiStateLabels
var ai_timer := 0.0

# draws the state and time in state over every scripted enemy, in the
# world's canvas so the camera carries it, at a fixed screen size
class AiStateLabels:
	extends Node2D

	const FONT_SIZE := 12
	const LIFT_PIXELS := 6.0

	func _ready() -> void:
		z_index = 4000

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var font := PixelTheme.font()
		var scale := get_viewport().get_canvas_transform().get_scale().x

		if scale <= 0.0:
			scale = 1.0

		for enemy in DebugPanel.scripted_enemies(get_tree()):
			var machine: AiStateMachine = enemy.state_machine
			var text := "%s %.1fs" % [machine.get_state(), machine.get_time_in_state()]
			var lift := Steering.sprite_radius_units(enemy) * Steering.ppu() + LIFT_PIXELS
			var at := to_local(enemy.global_position) + Vector2(0, -lift)

			draw_set_transform(at, 0.0, Vector2.ONE / scale)
			draw_string(font, Vector2(0, 0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, Color.WHITE)

		draw_set_transform(Vector2.ZERO)

static func scripted_enemies(tree: SceneTree) -> Array:
	var out := []

	for enemy in tree.get_nodes_in_group("enemy"):
		if enemy is EnemyScripted and Steering.alive(enemy) and not enemy.dead and enemy.state_machine != null:
			out.append(enemy)

	return out

func _init(target: RegolithWorld) -> void:
	world = target
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	build()

func _exit_tree() -> void:
	if is_instance_valid(ai_labels):
		ai_labels.queue_free()

func _process(delta: float) -> void:
	stats.text = "fps %d   sprites %d   joints %d   contacts %d   ropes %d\ncommit %.2f ms   physics %.2f ms" % [
		Engine.get_frames_per_second(),
		world.get_sprite_count(),
		world.get_joint_count(),
		world.get_contact_count(),
		world.get_rope_count(),
		world.get_commit_time_ms(),
		world.get_physics_time_ms(),
	]

	pause_check.set_pressed_no_signal(get_tree().paused)

	ai_timer -= delta

	if ai_timer <= 0.0:
		ai_timer = AI_REFRESH
		ai_label.text = ai_report()

func build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.theme = PixelTheme.theme()
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	stats = Label.new()
	box.add_child(stats)

	var tick := HBoxContainer.new()
	box.add_child(tick)

	pause_check = CheckBox.new()
	pause_check.text = "Pause"
	pause_check.toggled.connect(func(on: bool): get_tree().paused = on)
	tick.add_child(pause_check)

	var step := Button.new()
	step.text = "Step"
	step.pressed.connect(step_once)
	tick.add_child(step)

	box.add_child(HSeparator.new())
	build_ai_section(box)
	box.add_child(HSeparator.new())
	build_controls_section(box)

func build_ai_section(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)

	var title := Label.new()
	title.text = "AI"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	ai_labels = AiStateLabels.new()
	ai_labels.name = "AiStateLabels"
	world.add_child(ai_labels)

	var labels_check := CheckBox.new()
	labels_check.text = "State labels"
	labels_check.button_pressed = true
	labels_check.toggled.connect(func(on: bool): ai_labels.visible = on)
	row.add_child(labels_check)

	ai_label = Label.new()
	ai_label.text = ai_report()
	box.add_child(ai_label)

# every binding of the game and its tools (Controls.describe()), folded
# away until asked for
func build_controls_section(box: VBoxContainer) -> void:
	controls_fold = FoldableContainer.new()
	controls_fold.name = "ControlsFold"
	controls_fold.title = "Controls"
	controls_fold.folded = true
	box.add_child(controls_fold)

	controls_list = ControlsList.new()
	controls_list.custom_minimum_size = Vector2(0, CONTROLS_HEIGHT)
	controls_fold.add_child(controls_list)

# every scripted enemy with its state, then the nearest one's transitions
func ai_report() -> String:
	var enemies := scripted_enemies(get_tree())
	var lines := PackedStringArray()
	var runtime := get_node_or_null("/root/Ai")

	if runtime and runtime.lua:
		lines.append("scripted %d   lua instances %d   lua memory %d KB" % [enemies.size(), runtime.lua.get_instance_count(), runtime.lua.get_memory_used() / 1024])
	else:
		lines.append("scripted %d" % enemies.size())

	var player := Steering.find_player(get_tree())
	var nearest: EnemyScripted = null
	var nearest_distance := INF

	for enemy in enemies:
		var machine: AiStateMachine = enemy.state_machine
		var pending := machine.get_pending_state()
		lines.append("%s  %s  %s %.1fs%s" % [enemy.name, enemy.ai_class, machine.get_state(), machine.get_time_in_state(), "  -> " + pending if pending != "" else ""])

		if player:
			var distance: float = enemy.global_position.distance_squared_to(player.global_position)

			if distance < nearest_distance:
				nearest_distance = distance
				nearest = enemy

	if nearest == null and not enemies.is_empty():
		nearest = enemies[0]

	if nearest:
		var machine: AiStateMachine = nearest.state_machine
		lines.append("")
		lines.append("%s transitions (states: %s)" % [nearest.name, ", ".join(machine.get_states())])
		var entries := machine.get_transition_log()

		for i in range(maxi(entries.size() - AI_LOG_LINES, 0), entries.size()):
			var entry: Dictionary = entries[i]
			lines.append("  %6.1fs  %s -> %s" % [entry["at"], entry["from"] if entry["from"] != "" else "(none)", entry["to"]])

		if machine.get_last_error() != "":
			lines.append("  error: %s" % machine.get_last_error())

	return "
".join(lines)

func step_once() -> void:
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().paused = true
