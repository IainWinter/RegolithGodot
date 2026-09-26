extends Node2D
class_name PlayerCloud

# the player's cloud state, port of PlayerCloudEffectSystem and the cloud
# half of PlayerEventHandler. losing the core turns the ship into a cloud:
# the hull is hidden and left to the physics to stand in for the cloud's
# collider, the player moves at cloud_speed, cannot shoot, and has
# death_time seconds to collect a core before dying. collecting one puts
# the hull back together from the cells recorded when the sprite loaded.
# once invincible_time has passed anything that takes a cell off the hidden
# hull (a bullet through the cloud) kills the player. the cloud starts the
# way the SpriteCoreExplodedEvent started it: when the player's core blows
# (core_exploded, a core damaged past core_explode_damage), when the last
# core cell goes (Player.core_destroyed), or when the whole hull goes at
# once (the ship shredded in one commit, which Player.check_core skips
# since no cell is left). every frame the cloud and the fire, which grows
# with the danger ratio, are drawn, and past a quarter of the timer bolts
# of lightning arc out of the cloud faster and faster. the cloud's
# particles draw through an own ParticleEffect node (particles_scene, the
# shared one) with additive_material on it, because the particle pass of
# the original blended One / One and the shared node blends premultiplied.
# the node sits under the world's parent and outlives the cloud so the dead
# burst keeps flying under the death menu. child of the player sprite. sim
# units and seconds, positions in world pixels

@export var cloud: ParticleProps
@export var fire: ParticleProps
@export var burst: ParticleProps
@export var lightning: LightningProps
@export var lightning_material: Material
# the ParticleEffect scene the cloud draws through and the additive canvas
# material put on it. without them the shared EffectSpawner node draws
@export var particles_scene: PackedScene
@export var additive_material: Material

@export var cloud_speed := 8.0
@export var death_time := 4.0
@export var invincible_time := 1.0
# extra fire particles per frame at full danger on top of the one a frame.
# zero: the danger shows as color, not as more fire
@export var fire_growth := 0.0
# the cloud and its fire lerp toward this as the death timer runs down, the
# low core alarm carries the timing
@export var danger_color := Color(1.0, 0.08, 0.05, 1.0)
@export var lightning_start_ratio := 0.25
@export var lightning_interval_max := 0.4
@export var lightning_interval_min := 0.06
@export var lightning_reach := 1.5
# seconds the particle node stays after the cloud is gone, the burst's life
@export var linger_time := 5.5

signal entered
signal left
signal died

var player: RegolithSprite
var is_cloud := false
var death_timer := 0.0
var invincible_timer := 0.0
var lightning_timer := 0.0
# held by whoever pulls a core in, the death timer waits while it flies
var collecting := false
var strikes := 0
var lightning_node: Lightning
var particles: ParticleEffect
var directional_burst: ParticleProps

# the loaded hull, cell by cell, put back when the cloud ends
var cell_positions: Array[Vector2i] = []
var cell_colors := PackedColorArray()
var cell_types := PackedInt32Array()
var cell_classes := PackedInt32Array()
# where the cloud sits on the ship, EffectSpawner.effect_origin taken while
# the core was there, as a local offset so it rides along after the core
# is gone. the node origin is the middle of the padded grid, off the core
var origin_local := Vector2.ZERO
var has_origin := false

func _enter_tree() -> void:
	add_to_group("player_cloud")

func _ready() -> void:
	player = get_parent() as RegolithSprite

	if player == null:
		push_warning("PlayerCloud must be a child of the player RegolithSprite")
		return

	if player.has_signal(&"core_destroyed"):
		player.connect(&"core_destroyed", enter)

	player.core_exploded.connect(on_core_exploded)

	var world := RegolithWorld.active()

	if world:
		world.cells_removed.connect(on_cells_removed)
		world.sprite_emptied.connect(on_sprite_emptied)

func _exit_tree() -> void:
	if lightning_node != null and is_instance_valid(lightning_node):
		lightning_node.queue_free()
		lightning_node = null

	release_particles()

func danger() -> float:
	return clampf(death_timer / death_time, 0.0, 1.0) if is_cloud else 0.0

# the cloud's color now: its own at the start, danger_color at the end
func cloud_color() -> Color:
	return cloud.color_begin.lerp(danger_color, danger()) if cloud else danger_color

func fire_color() -> Color:
	return fire.color_begin.lerp(danger_color, danger()) if fire else danger_color

# the cloud's spot in world pixels: the core centroid recorded on load,
# else whatever EffectSpawner.effect_origin makes of the hull now
func origin() -> Vector2:
	if player == null or not is_instance_valid(player):
		return global_position

	if has_origin:
		return player.to_global(origin_local)

	return EffectSpawner.effect_origin(player)

func _physics_process(delta: float) -> void:
	if player == null:
		return

	if cell_positions.is_empty() and player.is_loaded():
		snapshot()

	if not is_cloud:
		return

	invincible_timer = maxf(invincible_timer - delta, 0.0)

	if collecting:
		death_timer = 0.0
		return

	death_timer += delta

	if death_timer >= death_time:
		die()

func _process(delta: float) -> void:
	if not is_cloud or player == null:
		return

	var position := origin()
	var ratio := danger()

	emit(cloud, position, 0.0, -1, cloud_color())
	emit(fire, position, 0.0, 1 + int(ratio * fire_growth), fire_color())

	lightning_timer -= delta

	if ratio > lightning_start_ratio and lightning_timer <= 0.0:
		lightning_timer = lerpf(lightning_interval_max, lightning_interval_min, ratio)
		strike(position)

# the node effects go on: the world's parent, where the lightning and the
# particle node live
func effect_parent() -> Node:
	var world := RegolithWorld.active()
	return world.get_parent() if world else null

# the cloud's own particle node, made on first use. falls back to the
# shared EffectSpawner node without a scene
func emit(props: ParticleProps, position: Vector2, angle := 0.0, count := -1, tint := Color(0.0, 0.0, 0.0, -1.0)) -> void:
	if props == null:
		return

	if particles == null or not is_instance_valid(particles):
		particles = null

		if particles_scene != null:
			var parent := effect_parent()

			if parent != null:
				particles = particles_scene.instantiate() as ParticleEffect

				if particles != null:
					particles.name = "PlayerCloudParticles"
					# a game effect: it freezes with the pause menu like every
					# other world particle. the burst still flies on under the
					# death menu because DEAD does not pause the tree
					parent.add_child(particles)

					if additive_material != null:
						particles.material = additive_material

	if particles != null:
		particles.burst(props, position, angle, count, tint)
		return

	var effects := EffectSpawner.active()

	if effects:
		effects.emit(props, position, angle, count)

# the particle node stays behind to finish what it has, then goes
func release_particles() -> void:
	if particles == null or not is_instance_valid(particles):
		particles = null
		return

	var node := particles
	particles = null

	if not node.is_inside_tree():
		node.queue_free()
		return

	# a child timer goes away with the node, a scene tree timer holding the
	# node in a lambda would fire on a freed capture when the scene ends
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = linger_time
	timer.timeout.connect(node.queue_free)
	node.add_child(timer)
	timer.start()

func strike(position: Vector2) -> void:
	if lightning == null:
		return

	if lightning_node == null or not is_instance_valid(lightning_node):
		var parent := effect_parent()

		if parent == null:
			return

		lightning_node = Lightning.attach(parent, lightning, lightning_material, false)

	var reach := randf() * lightning_reach * RegolithWorld.pixels_per_unit()
	lightning_node.strike(position, position + Vector2.from_angle(randf() * TAU) * reach, player)
	strikes += 1

# the core is gone, the ship becomes a cloud
func enter() -> void:
	if is_cloud or player == null:
		return

	if cell_positions.is_empty() and player.is_loaded():
		snapshot()

	is_cloud = true
	death_timer = 0.0
	invincible_timer = invincible_time
	lightning_timer = 0.0
	collecting = false
	player.visible = false
	entered.emit()

# the player's core blew, the SpriteCoreExplodedEvent of the original
func on_core_exploded(_position: Vector2, _power: int, type: int) -> void:
	if type == RegolithSprite.CELL_CORE:
		enter()

# a core picked up: as a cloud it rebuilds the ship, otherwise it only
# resets the timer
func collect_core() -> void:
	death_timer = 0.0

	if is_cloud:
		leave()

func leave() -> void:
	is_cloud = false
	collecting = false
	restore_cells()
	player.visible = true
	spawn_burst()
	left.emit()

func die() -> void:
	if player == null:
		return

	spawn_burst()
	is_cloud = false
	died.emit()
	player.queue_free()

# cells off the player: as a cloud past its invincibility that is a hit on
# the hidden hull and kills. as a ship, the core going with the rest of
# the hull in one commit never reaches Player.check_core (no cell left to
# count), so the cloud starts here
func on_cells_removed(sprite: RegolithSprite, _count: int) -> void:
	if sprite != player:
		return

	if is_cloud:
		if invincible_timer <= 0.0:
			die()
	elif player.is_loaded() and player.count_cells_of_type(RegolithSprite.CELL_CORE) == 0:
		enter()

func on_sprite_emptied(sprite: RegolithSprite) -> void:
	if sprite == player and not is_cloud:
		enter()

func snapshot() -> void:
	cell_positions.clear()
	cell_colors.clear()
	cell_types.clear()
	cell_classes.clear()

	var count := player.get_cell_count()

	for y in count.y:
		for x in count.x:
			var cell := Vector2i(x, y)

			if not player.has_cell(cell):
				continue

			var type := player.get_cell_type(cell)

			if type == RegolithSprite.CELL_ROPE:
				continue

			cell_positions.append(cell)
			cell_colors.append(player.get_cell_color(cell))
			cell_types.append(type)
			cell_classes.append(player.get_cell_class(cell))

	if not has_origin and player.get_active_cell_count() > 0:
		origin_local = EffectSpawner.effect_origin_local(player)
		has_origin = true

# the repair_all_cells and repair_all_cores of the original first: the
# sprite keeps a list of every cell it lost for heals, and a cell put back
# through set_cell would stay on it and be regrown again by the next health
# item, doubling the count. the snapshot then fills what a split took away,
# which that list never held
func restore_cells() -> void:
	if not player.is_loaded():
		return

	player.repair_all_cells()
	player.repair_cores()

	for i in cell_positions.size():
		var cell := cell_positions[i]

		if not player.has_cell(cell):
			player.set_cell(cell, cell_colors[i], cell_types[i], cell_classes[i])

# the spawn_player_cloud_dead_effect of the original: one burst thrown along
# the player's velocity, spread by up to a radian either side, and one in
# every direction
func spawn_burst() -> void:
	if burst == null:
		return

	var position := origin()
	var velocity: Vector2 = player.linear_velocity
	var speed := velocity.length()

	if directional_burst == null:
		directional_burst = burst.duplicate()

	var spread_min := randf()
	var spread_max := randf()
	directional_burst.velocity_min = Vector2(1.0 + cos(spread_min), -sin(spread_min)) * speed
	directional_burst.velocity_max = Vector2(1.0 + cos(spread_max), sin(spread_max)) * speed

	emit(directional_burst, position, velocity.angle())
	emit(burst, position)
