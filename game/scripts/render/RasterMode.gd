extends RefCounted
class_name RasterMode

# the three raster toggles of the debug menu applied to a running tree,
# read from the GameSettings autoload so they survive restarts. lightning
# is a switch on the Lightning node between its cell snapping shader and a
# smooth antialiased polyline. bullets / effects and everything both put a
# RasterView in the tree (under the current scene, else under the root),
# everything wins when both are on. apply() at any time reconciles the tree
# with the settings, no scene reload

static func apply(tree: SceneTree) -> RasterView:
	var settings := settings_node(tree)

	Lightning.pixelated = settings.raster_lightning if settings else true

	var wanted := wanted_mode(settings)
	var view := active(tree)

	if wanted < 0:
		if view != null:
			remove(view)
		return null

	if view != null and view.mode == wanted:
		return view

	if view != null:
		remove(view)

	view = RasterView.new(wanted as RasterView.Mode)
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(view)
	return view

# -1 for none, else the RasterView.Mode the settings ask for
static func wanted_mode(settings: Node) -> int:
	if settings == null:
		return -1

	if settings.raster_world:
		return RasterView.Mode.WORLD

	if settings.raster_effects:
		return RasterView.Mode.EFFECTS

	return -1

static func active(tree: SceneTree) -> RasterView:
	for node in tree.get_nodes_in_group(RasterView.GROUP):
		if node is RasterView and not node.is_queued_for_deletion():
			return node

	return null

# out of the tree at once so the layers are restored before anything else
# looks, and freed there and then, nothing of it lingers a frame
static func remove(view: RasterView) -> void:
	var parent := view.get_parent()

	if parent != null:
		parent.remove_child(view)

	view.free()

static func settings_node(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("GameSettings")

static func set_lightning(tree: SceneTree, on: bool) -> void:
	var settings := settings_node(tree)

	if settings != null:
		settings.raster_lightning = on
		settings.save()

	apply(tree)

static func set_effects(tree: SceneTree, on: bool) -> void:
	var settings := settings_node(tree)

	if settings != null:
		settings.raster_effects = on
		settings.save()

	apply(tree)

static func set_world(tree: SceneTree, on: bool) -> void:
	var settings := settings_node(tree)

	if settings != null:
		settings.raster_world = on
		settings.save()

	apply(tree)
