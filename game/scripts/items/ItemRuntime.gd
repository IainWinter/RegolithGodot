extends Node

# Items autoload: the item side of the game. one place makes item nodes: a
# SpawnRequest of Kind.ITEM on the SpawnBus lands here and the item goes
# under the world's parent at once, items are not sprites and never wait
# for room. it also watches every RegolithSprite's cores through their
# core_exploded signal: a core that goes on an enemy runs the explosion
# sequence of the original (sparks, then a burst of shrapnel, one health
# item per five cells of power and the enemy's drop table) and kills the
# enemy once its last core is gone; the player turning into a cloud throws
# out core items; a bullet through a player core cell knocks one loose; a destroyed
# sprite with a drop_table rolls it; damaged cores spark. port of
# ItemEventHandler, ItemDropTableSystem, SpriteCoreEventHandler, the item
# drops of ExplosionSequenceSystem and the item half of PlayerEventHandler.
# sim units, positions handed in as world pixels are converted at the edge

const ITEM_SCENE := preload("res://game/scenes/items/Item.tscn")
const HEALTH_PROPS := [
	preload("res://game/config/items/health_small.tres"),
	preload("res://game/config/items/health_medium.tres"),
	preload("res://game/config/items/health_large.tres"),
]
const ENERGY_PROPS := [
	preload("res://game/config/items/energy_small.tres"),
	preload("res://game/config/items/energy_medium.tres"),
	preload("res://game/config/items/energy_large.tres"),
]
const CORE_PROPS := preload("res://game/config/items/core.tres")
const CORE_SPARK := preload("res://game/config/items/core_spark.tres")
const SHRAPNEL := preload("res://game/config/weapons/explosion_shrapnel.tres")
const SHRAPNEL_LONG := preload("res://game/config/weapons/explosion_shrapnel_long.tres")

# the drop table of each enemy class, the ItemDropTable component the
# original's prefabs named. any sprite may override with a drop_table
# property or meta
const DROP_TABLES := {
	"EnemyFighter": preload("res://game/config/items/mixed_bad.tres"),
	"EnemyBomb": preload("res://game/config/items/mixed_bad.tres"),
	"EnemyStation": preload("res://game/config/items/mixed_ok.tres"),
	"EnemyBase": preload("res://game/config/items/mixed_good.tres"),
}

# health items per core cell of power, item_count = power / 5
const CELLS_PER_ITEM := 5
# core items thrown out when the player's core goes
const PLAYER_CORE_ITEMS := 3
# seconds of sparks between a core going and its burst
const SEQUENCE_DURATION := 1.2
# the sequence spits a burst of explosion sparks (and half the time smoke)
# this often, this far around the spot, the particle_timer of the
# original's ExplosionSequence
const SEQUENCE_PARTICLE_INTERVAL := 0.15
const SEQUENCE_SPARK_SPREAD := 0.4
# shrapnel of a core burst is at least this many, a weakpoint's 15
const CORE_SHRAPNEL_MIN := 20
const WEAKPOINT_SHRAPNEL_MIN := 15
# odds per second at full damage of a spark off a damaged core
const CORE_SPARK_RATE := 8.0
# items land within this many units of the drop spot with this much extra speed
const DROP_SCATTER := 0.1
const DROP_SPEED := 5.0

signal item_spawned(item: Item, request: SpawnRequest)
signal core_exploded(sprite: RegolithSprite, position: Vector2, power: int, type: int)
signal burst_finished(position: Vector2, power: int)

var rng := RandomNumberGenerator.new()
var watched: Array[RegolithSprite] = []
# DROP_TABLES plus whatever set_class_drop_table adds at runtime
var class_drop_tables := DROP_TABLES.duplicate()
# sprites whose Core type core has gone, they die with their last core
var lost_core := {}

func _ready() -> void:
	rng.randomize()
	SpawnBus.spawn_requested.connect(on_spawn_requested)
	get_tree().node_added.connect(on_node_added)

	for node in get_tree().get_nodes_in_group("regolith"):
		if node is RegolithSprite:
			watch(node)

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func health_props(size: ItemProps.Size) -> ItemProps:
	return HEALTH_PROPS[size]

func energy_props(size: ItemProps.Size) -> ItemProps:
	return ENERGY_PROPS[size]

# asks the bus for an item, units
func spawn(props: ItemProps, at: Vector2, velocity := Vector2.ZERO) -> SpawnRequest:
	return SpawnBus.send(SpawnRequest.item(props, at, velocity))

func on_node_added(node: Node) -> void:
	if node is RegolithSprite:
		watch(node)
	elif node is RegolithWorld:
		if not node.sprite_destroyed.is_connected(on_sprite_destroyed):
			node.sprite_destroyed.connect(on_sprite_destroyed)
	elif node is PlayerCloud:
		if not node.entered.is_connected(on_cloud_entered):
			node.entered.connect(on_cloud_entered.bind(node))
	elif node.has_signal("core_hit") and not node.core_hit.is_connected(on_core_hit):
		node.core_hit.connect(on_core_hit)

# the player's core is gone: the PlayerEventHandler threw three cores out of
# the ship for the cloud to chase
func on_cloud_entered(cloud: PlayerCloud) -> void:
	if cloud.player == null or not is_instance_valid(cloud.player):
		return

	var at := cloud.player.global_position / ppu()

	for i in PLAYER_CORE_ITEMS:
		spawn(CORE_PROPS, at, Steering.random_in_circle(10.0))

func watch(sprite: RegolithSprite) -> void:
	if sprite.core_exploded.is_connected(on_core_exploded):
		return

	sprite.core_exploded.connect(on_core_exploded.bind(sprite))
	watched.append(sprite)

func on_spawn_requested(request: SpawnRequest) -> void:
	if request.kind != SpawnRequest.Kind.ITEM:
		return

	var parent := Weapon.projectile_parent()

	if parent == null or request.item_props == null:
		request.expired.emit()
		return

	var item: Item = ITEM_SCENE.instantiate()
	item.setup(request.item_props, request.position, request.velocity)
	parent.add_child(item)
	request.item_spawned.emit(item)
	item_spawned.emit(item, request)

# the damaged effect of SpriteCoreUpdate: a core or weakpoint that has lost
# cells sparks now and then, more the worse it is
func _process(delta: float) -> void:
	Steering.prune_dead(watched)
	var effects := EffectSpawner.active()

	if effects == null:
		return

	for sprite in watched:
		if not sprite.is_inside_tree() or not sprite.is_loaded():
			continue

		for i in sprite.get_core_count():
			if not is_core_or_weakpoint(sprite.get_core_type(i)):
				continue

			var damage := sprite.get_core_damage(i)

			if damage > 0.0 and randf() < damage * CORE_SPARK_RATE * delta:
				effects.emit(CORE_SPARK, sprite.get_core_position(i))

static func is_core_or_weakpoint(type: int) -> bool:
	return type >= RegolithSprite.CELL_CORE and type <= RegolithSprite.CELL_WEAKPOINT4

func on_core_exploded(position: Vector2, power: int, type: int, sprite: RegolithSprite) -> void:
	if not is_instance_valid(sprite):
		return

	core_exploded.emit(sprite, position, power, type)

	# the player's core going is the cloud's business, its cores drop on
	# cloud entered
	if not sprite.is_in_group("enemy") or not is_core_or_weakpoint(type):
		return

	var is_core := type == RegolithSprite.CELL_CORE

	if is_core:
		lost_core[sprite.get_instance_id()] = true

	# the replace with rock of the original: the last core gone takes the ai
	# with it, the hull stays for the sequence and dies with the burst
	var kill := sprite.get_core_count() == 0 and lost_core.has(sprite.get_instance_id())

	if kill:
		lost_core.erase(sprite.get_instance_id())
		sprite.set_physics_process(false)

	var velocity_bias := Vector2.from_angle(randf() * TAU) + sprite.linear_velocity * 0.5
	# the sprite may be gone by the time the sequence ends, take its table now
	run_sequence(sprite, sprite.to_local(position), velocity_bias, power, is_core, kill, drop_table_for(sprite))

# the ExplosionSequence: sparks at the spot, riding along with the sprite,
# then the burst
func run_sequence(sprite: RegolithSprite, local: Vector2, velocity_bias: Vector2, power: int, is_core: bool, kill: bool, table: ItemDropTable) -> void:
	var position := sprite.to_global(local)
	var elapsed := 0.0
	var particle_timer := 0.0

	while elapsed < SEQUENCE_DURATION:
		await get_tree().process_frame

		if not is_inside_tree():
			return

		var delta := get_process_delta_time()
		elapsed += delta

		if is_instance_valid(sprite) and sprite.is_inside_tree():
			position = sprite.to_global(local)

		var effects := EffectSpawner.active()
		particle_timer += delta

		if effects and particle_timer >= SEQUENCE_PARTICLE_INTERVAL:
			particle_timer -= SEQUENCE_PARTICLE_INTERVAL
			var at := position + Steering.random_in_circle(SEQUENCE_SPARK_SPREAD) * ppu()
			effects.emit(effects.explosion_spark, at)

			if randf() < 0.5:
				effects.emit(effects.explosion_smoke, at)

	burst(position, velocity_bias, power, is_core, table)

	if kill and is_instance_valid(sprite):
		if sprite.has_method("die"):
			sprite.die()
		else:
			sprite.queue_free()

# the ExplosionEvent and item drops at the end of a sequence. shrapnel has
# no owner, it shreds the hull it came from too
func burst(position: Vector2, velocity_bias: Vector2, power: int, is_core: bool, table: ItemDropTable) -> void:
	var effects := EffectSpawner.active()

	if effects:
		effects.explosion(position)

	Explosion.spawn_shrapnel(SHRAPNEL, maxi(CORE_SHRAPNEL_MIN if is_core else WEAKPOINT_SHRAPNEL_MIN, power), position, null)

	if power > 15:
		Explosion.spawn_shrapnel(SHRAPNEL_LONG, int(sqrt(power)), position, null)

	if is_core:
		var at := position / ppu()

		for i in power / CELLS_PER_ITEM:
			drop(health_props(ItemProps.Size.MEDIUM), at, velocity_bias)

		drop_rolled(table, at, velocity_bias)

	burst_finished.emit(position, power)

func drop(props: ItemProps, at: Vector2, velocity_bias: Vector2) -> void:
	spawn(props, at + Steering.random_in_circle(DROP_SCATTER), velocity_bias + Steering.random_in_circle(DROP_SPEED))

func drop_from_table(source: Object, at: Vector2, velocity_bias: Vector2) -> int:
	return drop_rolled(drop_table_for(source), at, velocity_bias)

func drop_rolled(table: ItemDropTable, at: Vector2, velocity_bias: Vector2) -> int:
	if table == null:
		return 0

	var drops := table.roll(rng)

	for props in drops:
		drop(props, at, velocity_bias)

	return drops.size()

# the drop table of every sprite whose script, or a base of it, has this
# class_name, null clears it
func set_class_drop_table(class_key: String, table: ItemDropTable) -> void:
	if table == null:
		class_drop_tables.erase(class_key)
	else:
		class_drop_tables[class_key] = table

# a drop_table property, then meta, then the class table of the script or
# any base of it
func drop_table_for(sprite: Object) -> ItemDropTable:
	if sprite == null or not is_instance_valid(sprite):
		return null

	var table: Variant = sprite.get("drop_table")

	if table is ItemDropTable:
		return table

	if sprite.has_meta("drop_table"):
		table = sprite.get_meta("drop_table")

		if table is ItemDropTable:
			return table

	var script: Script = sprite.get_script()

	while script != null:
		var class_key := script.get_global_name()

		if class_drop_tables.has(class_key):
			return class_drop_tables[class_key]

		script = script.get_base_script()

	return null

# a bullet through a player core cell knocks a core loose, thrown on
# along the bullet's way
func on_core_hit(sprite: RegolithSprite, position: Vector2, direction: Vector2) -> void:
	if not is_instance_valid(sprite) or not sprite.is_in_group("player"):
		return

	spawn(CORE_PROPS, position / ppu(), direction.normalized() * Steering.random_in_circle(10.0))

# a sprite gone from the world with a drop table drops it where it was.
# enemies drop through their core instead
func on_sprite_destroyed(sprite: RegolithSprite) -> void:
	if not is_instance_valid(sprite) or sprite.is_in_group("enemy"):
		return

	var table := drop_table_for(sprite)

	if table == null:
		return

	var velocity_bias := Vector2.from_angle(randf() * TAU) + sprite.linear_velocity * 0.5
	drop_from_table(sprite, sprite.global_position / ppu(), velocity_bias)
