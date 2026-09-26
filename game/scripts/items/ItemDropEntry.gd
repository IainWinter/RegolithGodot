extends Resource
class_name ItemDropEntry

# one line of an ItemDropTable: the item, the odds it drops at all and how
# many drop when it does, the ItemDropTableEntry of the original

@export var item: ItemProps
@export_range(0.0, 1.0) var chance := 0.0
@export var count := 1
