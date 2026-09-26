extends Resource
class_name ItemDropTable

# what a sprite leaves behind when its core goes or it is destroyed, the
# ItemDropTableAsset of the original. each entry rolls on its own. tables
# live in res://game/config/items, the Items autoload maps them onto enemy
# classes and reads a drop_table property or meta off any sprite

@export var entries: Array[ItemDropEntry] = []

# the props of every item this roll drops, an entry's count copies of it
# when its chance comes up
func roll(rng: RandomNumberGenerator = null) -> Array[ItemProps]:
	var drops: Array[ItemProps] = []

	for entry in entries:
		if entry == null or entry.item == null:
			continue

		var pick := rng.randf() if rng else randf()

		if pick >= entry.chance:
			continue

		for i in entry.count:
			drops.append(entry.item)

	return drops
