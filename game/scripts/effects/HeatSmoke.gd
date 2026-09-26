extends Node
class_name HeatSmoke

# super hot cells smoke. the original had no such effect, this is new: a few
# times a second the world is asked for its white hot cells (heat
# min_heat..15 of the 4 bit cell heat, the top of the glow ramp the sprite
# shader draws) and each one puffs with a chance per second that grows with
# how far past min_heat it is. puffs go through the EffectSpawner, capped
# per second so a big burn does not flood the particles. lives under Main
# next to the world, runs on the drawn frame

@export var props: ParticleProps
@export_range(0, 15) var min_heat := 12
# puffs per second of a cell at min_heat, one more of these for each heat
# level above it
@export var puffs_per_second_per_heat := 0.8
@export var polls_per_second := 15.0
@export var max_puffs_per_second := 60.0
# hot cells read per poll, the world samples a big burn down to this
@export var max_cells := 64

# puffs so far, for tests
var puffs := 0

var poll_time := 0.0
var budget := 0.0

func _process(delta: float) -> void:
	poll_time += delta
	var interval := 1.0 / polls_per_second
	if poll_time < interval:
		return

	var elapsed := poll_time
	poll_time = fmod(poll_time, interval)
	# the cap refills with time and never banks more than one poll's share
	budget = minf(budget + max_puffs_per_second * elapsed, max_puffs_per_second * interval + 1.0)
	poll(elapsed)

func poll(elapsed: float) -> void:
	var world := RegolithWorld.active()
	var effects := EffectSpawner.active()
	if world == null or effects == null or props == null:
		return

	var cells := world.get_hot_cells(min_heat, max_cells)
	for cell in cells:
		if budget < 1.0:
			return

		var rate := puffs_per_second_per_heat * (cell.z - min_heat + 1.0)
		if randf() >= rate * elapsed:
			continue

		budget -= 1.0
		puffs += 1
		# x of the props is along the emit direction, straight up here
		effects.emit(props, Vector2(cell.x, cell.y), -PI * 0.5, 1)
