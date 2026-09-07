extends RefCounted
class_name RockGenerator

# port of the asteroid generator: a noise displaced disc cut from a source
# texture, edges darkened by a burn band, optional ore clusters. gives a color
# image and a mask image in the encoding RegolithSprite loads. the original's
# normal map has no use here and is dropped

const CELLS := RegolithWorld.CELLS_PER_CHUNK

const ORE_SEED := 0x51F2A37D
const ORE_SHAPE_SEED := 0x13C8B91
const ORE_FILL_SEED := 0x7A19F03

static func pick_chunks(rng: RandomNumberGenerator, props: RockProps) -> int:
	var min_chunks := maxi(props.min_chunks, 1)
	return rng.randi_range(min_chunks, maxi(props.max_chunks, min_chunks))

static func make_rock(rng: RandomNumberGenerator, props: RockProps, chunks := 0) -> Dictionary:
	if chunks <= 0:
		chunks = pick_chunks(rng, props)

	var config := props
	if props.shape_variants:
		config = props.duplicate()
		match rng.randi_range(0, 3):
			1:
				config.radius_scale = 0.48
				config.noise_amplitude = 0.15
			2:
				config.noise_amplitude = 0.55
				config.noise_frequency = 0.03
			3:
				config.burn_strength = 0.95
				config.noise_persistence = 0.7

	var ore := Color(0, 0, 0, 0)
	if not props.ore_colors.is_empty() and rng.randf() < props.ore_chance:
		ore = props.ore_colors[rng.randi_range(0, props.ore_colors.size() - 1)]

	var rock_seed := rng.randi()
	var images := generate(rock_seed, Vector2i.ONE * chunks * CELLS, config, ore)
	images["chunks"] = chunks
	images["seed"] = rock_seed
	return images

static func generate(rock_seed: int, size: Vector2i, props: RockProps, ore := Color(0, 0, 0, 0)) -> Dictionary:
	var width := maxi(size.x, 1)
	var height := maxi(size.y, 1)
	var count := width * height

	var color := PackedByteArray()
	color.resize(count * 4)
	var mask := PackedByteArray()
	mask.resize(count * 4)

	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed
	var uv_offset_x := rng.randf() * (1.0 - props.uv_scale)
	var uv_offset_y := rng.randf() * (1.0 - props.uv_scale)

	var source := source_image(props)
	var source_data: PackedByteArray = source.get_data()
	var source_width := source.get_width()
	var source_height := source.get_height()

	var perlin := FastNoiseLite.new()
	perlin.noise_type = FastNoiseLite.TYPE_PERLIN
	perlin.fractal_type = FastNoiseLite.FRACTAL_FBM
	perlin.seed = rock_seed
	perlin.fractal_octaves = props.noise_octaves
	perlin.frequency = 1.0
	perlin.fractal_gain = props.noise_persistence

	var cx := width * 0.5
	var cy := height * 0.5
	var radius_x := maxf(width * props.radius_scale, 0.001)
	var radius_y := maxf(height * props.radius_scale, 0.001)
	var base_radius := minf(radius_x, radius_y)
	var burn := maxf(props.burn_pixels, 0.001)
	var frequency := props.noise_frequency

	var filled := SpriteDocument.encode_mask_pixel(RegolithSprite.CELL_FILLED, 0)

	for y in height:
		for x in width:
			var dx := x - cx
			var dy := y - cy
			var ndx := dx / radius_x
			var ndy := dy / radius_y
			var ndist := sqrt(ndx * ndx + ndy * ndy)

			var n := perlin.get_noise_2d(x * frequency, y * frequency)
			var displaced := 1.0 + n * props.noise_amplitude
			var field := (displaced - ndist) * base_radius

			if field <= 0.0:
				continue

			var u := uv_offset_x + (x / float(width)) * props.uv_scale
			var v := uv_offset_y + (y / float(height)) * props.uv_scale
			var sx := clampi(int(u * source_width), 0, source_width - 1)
			var sy := clampi(int(v * source_height), 0, source_height - 1)
			var si := (sy * source_width + sx) * 4

			var burn_t := clampf(field / burn, 0.0, 1.0)
			var darkness := 1.0 - (1.0 - burn_t) * props.burn_strength

			var i := (y * width + x) * 4
			color[i] = int(source_data[si] * darkness)
			color[i + 1] = int(source_data[si + 1] * darkness)
			color[i + 2] = int(source_data[si + 2] * darkness)
			color[i + 3] = 255

			mask[i] = filled.r8
			mask[i + 1] = filled.g8
			mask[i + 2] = filled.b8
			mask[i + 3] = filled.a8

	if ore.a > 0.0 and props.ore_cluster_count > 0:
		paint_ore(rock_seed, width, height, props, ore, color, mask)

	return {
		"color": Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, color),
		"mask": Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, mask),
	}

static func paint_ore(rock_seed: int, width: int, height: int, props: RockProps, ore: Color, color: PackedByteArray, mask: PackedByteArray) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed ^ ORE_SEED

	var shape_noise := FastNoiseLite.new()
	shape_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	shape_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	shape_noise.seed = rock_seed ^ ORE_SHAPE_SEED
	shape_noise.frequency = 1.0

	var fill_noise := FastNoiseLite.new()
	fill_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fill_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	fill_noise.seed = rock_seed ^ ORE_FILL_SEED
	fill_noise.frequency = 1.0

	var inset := int(ceil(maxf(props.ore_inset_pixels, 0.0)))
	var base_radius := maxf(props.ore_cluster_radius, 0.001)
	var reach := int(ceil(base_radius * (1.0 + props.ore_shape_amount)))
	var ore_blue := SpriteDocument.encode_mask_pixel(RegolithSprite.CELL_FILLED, props.ore_class).b8

	for _cluster in props.ore_cluster_count:
		var sx := -1
		var sy := -1

		for _try in 128:
			var tx := int(rng.randf() * width)
			var ty := int(rng.randf() * height)

			if filled_inset(color, width, height, tx, ty, inset):
				sx = tx
				sy = ty
				break

		if sx < 0:
			continue

		var cxp := sx + rng.randf_range(-0.5, 0.5) * props.ore_cluster_jitter
		var cyp := sy + rng.randf_range(-0.5, 0.5) * props.ore_cluster_jitter

		for y in range(maxi(0, sy - reach), mini(height, sy + reach + 1)):
			for x in range(maxi(0, sx - reach), mini(width, sx + reach + 1)):
				var i := (y * width + x) * 4
				if color[i + 3] != 255:
					continue

				var dx := x - cxp
				var dy := y - cyp
				var d := sqrt(dx * dx + dy * dy)

				var shape_n := shape_noise.get_noise_2d(x * props.ore_shape_frequency, y * props.ore_shape_frequency)
				var boundary := base_radius * (1.0 + shape_n * props.ore_shape_amount)
				if d > boundary:
					continue

				var t := d / maxf(boundary, 0.001)
				var core := pow(1.0 - t, props.ore_core_hardness)

				var fill_n := fill_noise.get_noise_2d(x * props.ore_fill_frequency, y * props.ore_fill_frequency) * 0.5 + 0.5
				var jitter := (fill_n - 0.5) * props.ore_edge_noise * (1.0 - core)

				if core + jitter < props.ore_noise_threshold:
					continue

				color[i] = ore.r8
				color[i + 1] = ore.g8
				color[i + 2] = ore.b8
				mask[i + 2] = ore_blue

static func filled_inset(color: PackedByteArray, width: int, height: int, x: int, y: int, inset: int) -> bool:
	for dy in range(-inset, inset + 1):
		for dx in range(-inset, inset + 1):
			var sx := x + dx
			var sy := y + dy

			if sx < 0 or sx >= width or sy < 0 or sy >= height:
				return false

			if color[(sy * width + sx) * 4 + 3] != 255:
				return false

	return true

static func source_image(props: RockProps) -> Image:
	if props.source_image_cache != null:
		return props.source_image_cache

	var texture := props.source_texture
	var image: Image = texture.get_image() if texture else null

	if image == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_VALUE
		noise.frequency = 0.08
		image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var g := 0.45 + noise.get_noise_2d(x, y) * 0.2
				image.set_pixel(x, y, Color(g, g * 0.95, g * 0.9))
	elif image.get_format() != Image.FORMAT_RGBA8 or image.is_compressed():
		image = image.duplicate()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)

	props.source_image_cache = image
	return image

static func spawn_rock(parent: Node, world: RegolithWorld, position: Vector2, rng: RandomNumberGenerator, props: RockProps, material: Material, chunks := 0) -> RegolithSprite:
	if world == null or not world.is_inside_tree():
		return null

	var images := make_rock(rng, props, chunks)

	var rock := RegolithSprite.new()
	rock.material = material
	rock.dynamic = true
	rock.angular_damping = props.angular_damping
	rock.add_to_group("regolith")

	var placement := Transform2D(rng.randf_range(0.0, TAU), position)
	var parent_2d := parent as Node2D
	rock.transform = parent_2d.global_transform.affine_inverse() * placement if parent_2d else placement

	parent.add_child(rock)
	rock.load_from_images(images["color"], images["mask"])
	rock.reset_physics_interpolation()

	rock.linear_velocity = Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(props.min_speed, props.max_speed)
	rock.angular_velocity = rng.randf_range(-props.max_spin, props.max_spin)

	return rock
