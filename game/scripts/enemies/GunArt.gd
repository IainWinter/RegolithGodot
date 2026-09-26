extends RefCounted
class_name GunArt

# paints the two parts of a gun at any size and lays them out as a
# MultiSprite document: the mount, a hex ring plate size x size with a round
# well and six core pods sunk into its wall at the corners, the pivot at its
# center, and the barrel, a cannon on its own grid: a hub on the pivot, a
# breech block behind it and a long tube ahead that reaches well past the
# ring. the document pins the barrel's hub onto the ring's center with a
# joint that does not collide connected, so the overlapping parts never
# push each other. every measure is a fraction of size, the gun is 32
# across, the turret 96. game/images/multisprites/gun.json and turret.json
# are document(size, prefix) written out (write_document) next to the png
# pairs in game/images/sprites, the color as <name>.png and the mask as
# <name>_mask.png; EnemyGun rebuilds the pair in memory at a scenario's
# scale_cells

const MIN_SIZE := 24

# fractions of size, see layout
const RING_OUTER := 0.43
const WELL_RADIUS := 0.34
const POD_RADIUS := 0.045
const POD_DISTANCE := 0.42
const HUB_RADIUS := 0.10
const BREECH_BACK := 0.20
const BREECH_FRONT := 0.07
const BREECH_HALF_HEIGHT := 0.10
# the tube reaches this far past the pivot, the ring ends at RING_OUTER
const TUBE_TIP := 0.80
const TUBE_HALF_HEIGHT := 0.0625
const COLLAR_LENGTH := 0.06
const COLLAR_HALF_HEIGHT := 0.095
const COS30 := 0.8660254
const SIN30 := 0.5

const MOUNT_STEEL := Color8(110, 118, 128)
const MOUNT_BEVEL := Color8(150, 158, 168)
const MOUNT_RIM := Color8(68, 74, 82)
const MOUNT_CORE := Color8(232, 122, 40)
const BARREL_METAL := Color8(78, 82, 90)
const BARREL_LIGHT := Color8(122, 128, 136)
const BARREL_COLLAR := Color8(56, 58, 64)
const HUB_METAL := Color8(96, 100, 108)
const HUB_DARK := Color8(40, 42, 48)

const SPRITES_DIR := "res://game/images/sprites"
const MULTISPRITES_DIR := "res://game/images/multisprites"

# the measures of a gun size cells across, in cells. center is the pivot
# in the mount's continuous grid coordinates, tip_x the barrel's last cell
# past the pivot, muzzle_x where its shots leave, a cell past the tip.
# barrel_size is the barrel image, barrel_pivot the pivot in it
static func layout(size: int) -> Dictionary:
	var s := float(maxi(size, MIN_SIZE))
	var back := ceili(s * BREECH_BACK) + 1
	var front := ceili(s * TUBE_TIP) + 1
	var half := ceili(s * maxf(HUB_RADIUS, maxf(BREECH_HALF_HEIGHT, COLLAR_HALF_HEIGHT))) + 1
	return {
		"size": int(s),
		"center": Vector2(s * 0.5, s * 0.5),
		"ring_outer": s * RING_OUTER,
		"well_radius": s * WELL_RADIUS,
		"hub_radius": s * HUB_RADIUS,
		"tip_x": s * TUBE_TIP,
		"muzzle_x": s * TUBE_TIP + 1.0,
		"barrel_size": Vector2i(back + front, half * 2),
		"barrel_pivot": Vector2(back, half),
	}

static func padded(size: Vector2i) -> Vector2i:
	var chunk := RegolithWorld.CELLS_PER_CHUNK
	return Vector2i(ceili(float(size.x) / chunk) * chunk, ceili(float(size.y) / chunk) * chunk)

# where a sprite's node sits so the continuous art point lands on the
# origin, in cells: the node origin is the center of the chunk padded grid
# and the art sits at the grid's top left
static func node_offset(size: Vector2i, point: Vector2) -> Vector2:
	return Vector2(padded(size)) * 0.5 - point

static func pair(v: Vector2) -> Array:
	return [snappedf(v.x, 0.00001), snappedf(v.y, 0.00001)]

# the gun as a MultiSprite document, positions in sim units with the pivot
# at the origin: sprite 0 the mount (the enemy node itself, "root"), sprite
# 1 the barrel facing +x, a pin joint between them on the pivot that does
# not collide connected, and the muzzle point. with a prefix the textures
# point at the png pairs in SPRITES_DIR, without one they are left out and
# images carries the painted pairs by sprite name
static func document(size: int, prefix := "") -> Dictionary:
	var l := layout(size)
	var s: int = l["size"]
	var unit := float(RegolithWorld.CELLS_PER_CHUNK)
	var mount_at := node_offset(Vector2i(s, s), l["center"]) / unit
	var barrel_at := node_offset(l["barrel_size"], l["barrel_pivot"]) / unit
	var mount_entry := {"name": "mount", "position": pair(mount_at), "rotation": 0.0, "dynamic": true}
	var barrel_entry := {"name": "barrel", "position": pair(barrel_at), "rotation": 0.0, "dynamic": true}

	if prefix != "":
		mount_entry["texture"] = "%s/%s_mount.png" % [SPRITES_DIR, prefix]
		mount_entry["mask"] = "%s/%s_mount_mask.png" % [SPRITES_DIR, prefix]
		barrel_entry["texture"] = "%s/%s_barrel.png" % [SPRITES_DIR, prefix]
		barrel_entry["mask"] = "%s/%s_barrel_mask.png" % [SPRITES_DIR, prefix]

	var data := {
		"sprites": [mount_entry, barrel_entry],
		"joints": [{"a": 0, "b": 1, "type": "pin", "point": [0.0, 0.0], "collide": false}],
		"root": 0,
		"muzzle": pair(Vector2(l["muzzle_x"], 0.0) / unit),
	}

	return {"data": data, "images": {"mount": mount(s), "barrel": barrel(s)}}

# writes the png pairs and <MULTISPRITES_DIR>/<prefix>.json for one size
static func write_document(size: int, prefix: String) -> void:
	var doc := document(size, prefix)
	write_pair(doc["images"]["mount"], SPRITES_DIR, prefix + "_mount")
	write_pair(doc["images"]["barrel"], SPRITES_DIR, prefix + "_barrel")
	var file := FileAccess.open(ProjectSettings.globalize_path("%s/%s.json" % [MULTISPRITES_DIR, prefix]), FileAccess.WRITE)
	file.store_string(JSON.stringify(doc["data"], "  "))
	file.close()

# a continuous grid point of a size grid in the sprite's local pixels, the
# node origin sits at the center of the chunk padded grid
static func grid_to_local_pixels(point: Vector2, size: int) -> Vector2:
	var chunk := RegolithWorld.CELLS_PER_CHUNK
	var padded := ceili(float(size) / chunk) * chunk
	return (point - Vector2.ONE * padded * 0.5) * RegolithWorld.pixels_per_cell()

# flat topped hexagon with inradius a
static func in_hex(p: Vector2, a: float) -> bool:
	return absf(p.y) <= a and absf(p.x) * COS30 + absf(p.y) * SIN30 <= a

static func blank_pair(size: int) -> Dictionary:
	return blank_rect(Vector2i(size, size))

static func blank_rect(size: Vector2i) -> Dictionary:
	var color := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	color.fill(Color(0, 0, 0, 0))
	mask.fill(Color(0, 0, 0, 0))
	return {"color": color, "mask": mask}

static func shade(color: Color, rng: RandomNumberGenerator, amount := 0.06) -> Color:
	var k := 1.0 + rng.randf_range(-amount, amount)
	return Color(color.r * k, color.g * k, color.b * k, 1.0)

static func paint(images: Dictionary, x: int, y: int, color: Color, type: int, emissive := false) -> void:
	images["color"].set_pixel(x, y, color)
	images["mask"].set_pixel(x, y, SpriteDocument.encode_mask_pixel(type, 0, emissive))

# the ring plate: hex outside, round well inside, the outer cell darker, the
# cell on the well lighter, a core pod at each of the six corners
static func mount(size: int) -> Dictionary:
	var l := layout(size)
	var s: int = l["size"]
	var images := blank_pair(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + s
	var center: Vector2 = l["center"]
	var outer: float = l["ring_outer"]
	var well: float = l["well_radius"]
	var pods: Array[Vector2] = []

	for i in 6:
		pods.append(center + Vector2.from_angle(i * PI / 3.0) * s * POD_DISTANCE)

	var pod_radius := s * POD_RADIUS

	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var r := p.length()

			if not in_hex(p, outer) or r < well:
				continue

			var color := MOUNT_STEEL

			if not in_hex(p, outer - 1.0):
				color = MOUNT_RIM
			elif r < well + 1.0:
				color = MOUNT_BEVEL

			var type := RegolithSprite.CELL_FILLED
			var cell := Vector2(x + 0.5, y + 0.5)

			for pod in pods:
				if cell.distance_to(pod) <= pod_radius:
					type = RegolithSprite.CELL_CORE
					color = MOUNT_CORE

			paint(images, x, y, shade(color, rng), type, type == RegolithSprite.CELL_CORE)

	return images

# the barrel on its own grid (barrel_size, the pivot at barrel_pivot): a
# round hub on the pivot, a breech block behind it, the tube ahead with a
# lighter center line and a collar at the muzzle, well past the ring
static func barrel(size: int) -> Dictionary:
	var l := layout(size)
	var s: int = l["size"]
	var grid: Vector2i = l["barrel_size"]
	var images := blank_rect(grid)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23 + s
	var center: Vector2 = l["barrel_pivot"]
	var hub: float = l["hub_radius"]
	var tip: float = l["tip_x"]
	var breech_back := s * BREECH_BACK
	var breech_front := s * BREECH_FRONT
	var breech_half := s * BREECH_HALF_HEIGHT
	var tube_half := maxf(s * TUBE_HALF_HEIGHT, 1.0)
	var collar_start := tip - s * COLLAR_LENGTH
	var collar_half := s * COLLAR_HALF_HEIGHT

	for y in grid.y:
		for x in grid.x:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var color := Color(0, 0, 0, 0)

			if p.length() <= hub:
				color = HUB_DARK if p.length() <= hub * 0.35 else HUB_METAL
			elif p.x >= -breech_back and p.x <= -breech_front and absf(p.y) <= breech_half:
				color = BARREL_METAL if absf(p.y) < breech_half - 1.0 else BARREL_COLLAR
			elif p.x >= collar_start and p.x <= tip and absf(p.y) <= collar_half:
				color = BARREL_COLLAR
			elif p.x > 0.0 and p.x <= tip and absf(p.y) <= tube_half:
				color = BARREL_LIGHT if absf(p.y) < tube_half * 0.5 else BARREL_METAL

			if color.a > 0.0:
				paint(images, x, y, shade(color, rng), RegolithSprite.CELL_FILLED)

	return images

# writes <dir>/<name>.png and <dir>/<name>_mask.png for one part
static func write_pair(images: Dictionary, dir: String, name: String) -> void:
	images["color"].save_png("%s/%s.png" % [dir, name])
	images["mask"].save_png("%s/%s_mask.png" % [dir, name])
