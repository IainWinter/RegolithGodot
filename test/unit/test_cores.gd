extends GutTest

# sprite cores: found from the mask on load, watched each frame by the
# sprite, exploding once most of the core is shot away or once the hull
# around it is, moving over to the split that keeps most of their cells,
# repairable, and on an enemy the Items autoload runs the burst that drops
# health items and kills it

const BOMB := "res://game/images/sprites/bomb.png"
const BOMB_MASK := "res://game/images/sprites/bomb_mask.png"
const CELL_PARTICLES_MATERIAL := preload("res://game/shaders/regolith_cell_particles_material.tres")
const GUARANTEED := preload("res://game/config/items/guaranteed_health_item.tres")

const FILLED_PIXEL := Color8(0, 100, 255, 255)
const CORE_PIXEL := Color8(0, 200, 255, 255)

# an enemy for the Items autoload: in group enemy with a die
class FakeEnemy extends RegolithSprite:
	var died := false
	var drop_table: ItemDropTable

	func _ready() -> void:
		add_to_group("enemy")
		add_to_group("regolith")

	func die() -> void:
		died = true
		queue_free()

var arena: Node2D
var world: RegolithWorld

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
	await wait_physics_frames(1)

func after_each() -> void:
	get_tree().current_scene = null
	arena.free()

func ppu() -> float:
	return RegolithWorld.pixels_per_unit()

func add_bomb_sprite(units: Vector2) -> RegolithSprite:
	var sprite := RegolithSprite.new()
	sprite.texture = load(BOMB)
	sprite.mask_texture = load(BOMB_MASK)
	sprite.position = units * ppu()
	arena.add_child(sprite)
	return sprite

# a filled rectangle with core rectangles cut into it, built from images
# the way a png pair loads
static func build_images(size: Vector2i, filled: Array, cores: Array) -> Array:
	var color := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)

	for rect in filled:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				color.set_pixel(x, y, Color(0.6, 0.6, 0.6, 1.0))
				mask.set_pixel(x, y, FILLED_PIXEL)

	for rect in cores:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				color.set_pixel(x, y, Color(1.0, 0.6, 0.3, 1.0))
				mask.set_pixel(x, y, CORE_PIXEL)

	return [color, mask]

func add_built_sprite(sprite: RegolithSprite, size: Vector2i, filled: Array, cores: Array, units := Vector2.ZERO) -> RegolithSprite:
	sprite.position = units * ppu()
	arena.add_child(sprite)
	var images := build_images(size, filled, cores)
	sprite.load_from_images(images[0], images[1])
	return sprite

func cells_of_type(sprite: RegolithSprite, type: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var count := sprite.get_cell_count()

	for y in count.y:
		for x in count.x:
			if sprite.get_cell_type(Vector2i(x, y)) == type:
				cells.append(Vector2i(x, y))

	return cells

func remove_cells(sprite: RegolithSprite, cells: Array[Vector2i], count: int) -> void:
	for i in mini(count, cells.size()):
		sprite.remove_cell(cells[i])

func center_of(sprite: RegolithSprite, cells: Array[Vector2i]) -> Vector2:
	var sum := Vector2.ZERO

	for cell in cells:
		sum += sprite.cell_to_world(cell)

	return sum / cells.size()

func test_cores_are_found_from_the_mask() -> void:
	var sprite := add_bomb_sprite(Vector2.ZERO)
	await wait_physics_frames(2)

	var core_cells := cells_of_type(sprite, RegolithSprite.CELL_CORE)
	assert_gt(core_cells.size(), 0, "the bomb has core cells")
	assert_eq(sprite.get_core_count(), 1, "one core")
	assert_eq(sprite.get_core_type(0), RegolithSprite.CELL_CORE)
	assert_eq(sprite.get_core_initial_cells(0), core_cells.size())
	assert_eq(sprite.get_core_remaining_cells(0), core_cells.size())
	assert_almost_eq(sprite.get_core_damage(0), 0.0, 0.0001)
	assert_almost_eq(sprite.get_core_explode_damage(), 0.7, 0.0001, "the original explode_damage")
	assert_almost_eq(sprite.get_core_position(0), center_of(sprite, core_cells), Vector2.ONE * RegolithWorld.pixels_per_cell() * 2.0, "the core sits on its cells")

func test_blank_sprites_have_no_cores() -> void:
	var sprite := RegolithSprite.new()
	arena.add_child(sprite)
	sprite.create_blank(Vector2i(8, 8))
	sprite.fill_rect(Rect2i(0, 0, 8, 8), Color.WHITE, RegolithSprite.CELL_CORE, 0)
	await wait_physics_frames(1)

	assert_eq(sprite.get_core_count(), 0)
	assert_eq(sprite.get_core_type(0), RegolithSprite.CELL_EMPTY)
	assert_eq(sprite.get_core_damage(3), 0.0)

func test_core_explodes_once_most_of_it_is_gone() -> void:
	var sprite := add_bomb_sprite(Vector2.ZERO)
	await wait_physics_frames(2)
	watch_signals(sprite)

	var core_cells := cells_of_type(sprite, RegolithSprite.CELL_CORE)
	var initial := core_cells.size()
	var half := initial / 2
	remove_cells(sprite, core_cells, half)
	await wait_physics_frames(2)

	assert_almost_eq(sprite.get_core_damage(0), float(half) / initial, 0.001, "damage is the share of cells gone")
	assert_signal_not_emitted(sprite, "core_exploded", "half a core holds")
	assert_eq(sprite.get_core_count(), 1)

	var gone := ceili(initial * 0.7)
	remove_cells(sprite, core_cells, gone)
	await wait_physics_frames(2)

	assert_signal_emit_count(sprite, "core_exploded", 1, "seventy percent gone blows it")
	assert_eq(sprite.get_core_count(), 0, "the exploded core left the live set")

	var params: Array = get_signal_parameters(sprite, "core_exploded")
	assert_eq(params[2], RegolithSprite.CELL_CORE, "type")
	assert_eq(params[1], maxi(initial - gone, initial / 2), "power is the cells left or half the start, whichever is more")
	assert_true(params[0] is Vector2)

func test_core_explodes_when_the_hull_around_it_is_gone() -> void:
	var sprite := add_built_sprite(RegolithSprite.new(), Vector2i(16, 16), [Rect2i(0, 0, 16, 16)], [Rect2i(6, 13, 3, 3)])
	await wait_physics_frames(2)
	watch_signals(sprite)

	assert_eq(sprite.get_core_count(), 1)
	assert_eq(sprite.get_core_initial_cells(0), 9)

	# the top 14 rows go, 26 hull cells stay under a 9 cell core: more than a
	# fifth of what is left is core
	for y in 14:
		for x in 16:
			if sprite.get_cell_type(Vector2i(x, y)) == RegolithSprite.CELL_FILLED:
				sprite.remove_cell(Vector2i(x, y))

	await wait_physics_frames(2)

	assert_signal_emit_count(sprite, "core_exploded", 1)
	assert_eq(sprite.get_core_count(), 0)
	assert_eq(sprite.count_cells_of_type(RegolithSprite.CELL_CORE), 9, "the cells are still there, only the core record went")

func test_unstable_cores_explode_on_the_next_update() -> void:
	var sprite := add_bomb_sprite(Vector2.ZERO)
	await wait_physics_frames(2)
	watch_signals(sprite)

	sprite.set_cores_unstable()
	sprite.update_cores()

	assert_signal_emit_count(sprite, "core_exploded", 1)
	var params: Array = get_signal_parameters(sprite, "core_exploded")
	assert_eq(params[1], sprite.count_cells_of_type(RegolithSprite.CELL_CORE), "an untouched core's power is all its cells")

func test_repair_cores_brings_an_exploded_core_back() -> void:
	var sprite := add_bomb_sprite(Vector2.ZERO)
	await wait_physics_frames(2)

	sprite.set_cores_unstable()
	sprite.update_cores()
	assert_eq(sprite.get_core_count(), 0)

	sprite.repair_cores()
	assert_eq(sprite.get_core_count(), 1, "back in the live set")
	assert_eq(sprite.get_core_type(0), RegolithSprite.CELL_CORE)

	watch_signals(sprite)
	sprite.update_cores()
	assert_signal_not_emitted(sprite, "core_exploded", "repair clears unstable and the cells are all there")

func test_core_moves_to_the_split_holding_most_of_it() -> void:
	# two blobs on a bridge, the core sits in the right one
	var sprite := add_built_sprite(RegolithSprite.new(), Vector2i(48, 16),
		[Rect2i(0, 0, 20, 16), Rect2i(20, 7, 8, 2), Rect2i(28, 0, 20, 16)],
		[Rect2i(36, 6, 4, 4)])
	await wait_physics_frames(2)
	assert_eq(sprite.get_core_count(), 1)

	var seen := {"piece": null}
	world.sprite_split.connect(func(source: RegolithSprite, piece: RegolithSprite):
		if source == sprite:
			seen["piece"] = piece)

	sprite.clear_rect(Rect2i(22, 7, 4, 2))
	await wait_physics_frames(3)

	var piece: RegolithSprite = seen["piece"]
	assert_not_null(piece, "the bridge cut split the sprite")
	if piece == null:
		return

	var holder := piece if piece.count_cells_of_type(RegolithSprite.CELL_CORE) == 16 else sprite
	var other := sprite if holder == piece else piece
	assert_eq(holder.count_cells_of_type(RegolithSprite.CELL_CORE), 16, "one side has every core cell")
	assert_eq(holder.get_core_count(), 1, "the core record went with the cells")
	assert_eq(other.get_core_count(), 0, "the other side has no core")
	assert_eq(holder.get_core_remaining_cells(0), 16)
	assert_eq(holder.get_core_initial_cells(0), 16)
	assert_almost_eq(holder.get_core_damage(0), 0.0, 0.0001)
	assert_almost_eq(holder.get_core_position(0), center_of(holder, cells_of_type(holder, RegolithSprite.CELL_CORE)), Vector2.ONE * RegolithWorld.pixels_per_cell(), "the offset moved onto the new grid")

func test_enemy_core_explosion_bursts_drops_items_and_kills_it() -> void:
	var enemy := FakeEnemy.new()
	enemy.drop_table = GUARANTEED
	add_built_sprite(enemy, Vector2i(24, 24), [Rect2i(0, 0, 24, 24)], [Rect2i(10, 10, 5, 5)], Vector2(4.0, 4.0))
	await wait_physics_frames(2)
	assert_eq(enemy.get_core_count(), 1)
	watch_signals(Items)

	# 18 of 25 gone: power is max(7, 12) = 12, two health items plus the table's one
	remove_cells(enemy, cells_of_type(enemy, RegolithSprite.CELL_CORE), 18)
	await wait_physics_frames(2)

	assert_signal_emit_count(Items, "core_exploded", 1)
	assert_true(is_instance_valid(enemy) and not enemy.died, "the hull stays for the sequence")
	assert_false(enemy.is_physics_processing(), "the ai stopped at once")

	await wait_seconds(Items.SEQUENCE_DURATION + 0.4)

	assert_signal_emit_count(Items, "burst_finished", 1)
	var params: Array = get_signal_parameters(Items, "burst_finished")
	assert_eq(params[1], 12, "power")
	assert_eq(get_tree().get_nodes_in_group("item").size(), 3, "12 / 5 health items plus the guaranteed drop")
	assert_false(is_instance_valid(enemy), "died with the burst")

	for item in get_tree().get_nodes_in_group("item"):
		assert_eq(item.props.type, ItemProps.Type.HEALTH)
		assert_lt(item.global_position.distance_to(Vector2(4.0, 4.0) * ppu()), 2.0 * ppu(), "dropped around the core")

func test_weakpoint_explosion_bursts_without_items_or_a_kill() -> void:
	var enemy := FakeEnemy.new()
	var images := build_images(Vector2i(16, 16), [Rect2i(0, 0, 16, 16)], [Rect2i(2, 2, 3, 3)])
	var mask: Image = images[1]
	for y in range(2, 5):
		for x in range(2, 5):
			mask.set_pixel(x, y, Color8(0, 250, 255, 255))
	enemy.position = Vector2.ZERO
	arena.add_child(enemy)
	enemy.load_from_images(images[0], mask)
	await wait_physics_frames(2)

	assert_eq(enemy.get_core_count(), 1)
	assert_eq(enemy.get_core_type(0), RegolithSprite.CELL_WEAKPOINT1)
	watch_signals(Items)

	enemy.set_cores_unstable()
	await wait_physics_frames(2)
	await wait_seconds(Items.SEQUENCE_DURATION + 0.4)

	assert_signal_emit_count(Items, "burst_finished", 1)
	assert_eq(get_tree().get_nodes_in_group("item").size(), 0, "weakpoints drop nothing")
	assert_true(is_instance_valid(enemy) and not enemy.died, "no Core type core was lost, the enemy lives")
