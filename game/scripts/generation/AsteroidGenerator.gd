extends RefCounted
class_name AsteroidGenerator

# the old Generation/Asteroid/AsteroidGenerator.cpp. RockGenerator
# (game/scripts/rocks/RockGenerator.gd) already ports its albedo path one to
# one: the noise displaced disc cut from a source texture, the burn band on
# the edge, the ore clusters, and it encodes the cell mask a RegolithSprite
# loads. this adds the one output it dropped, the bulb normal map (dome from
# the centre perturbed by the noise gradient), for anything that wants to
# light a rock, and hands back the same dictionary with a "normal" entry

static func generate(rock_seed: int, size: Vector2i, props: RockProps, ore := Color(0, 0, 0, 0)) -> Dictionary:
	var images := RockGenerator.generate(rock_seed, size, props, ore)
	images["normal"] = normal_map(rock_seed, size, props, images["color"])
	return images

# normals for every pixel the colour image marks solid. the noise setup
# mirrors RockGenerator so the dome radius matches the silhouette it drew
static func normal_map(rock_seed: int, size: Vector2i, props: RockProps, color: Image) -> Image:
	var width := maxi(size.x, 1)
	var height := maxi(size.y, 1)
	var solid: PackedByteArray = color.get_data()
	var out := PackedByteArray()
	out.resize(width * height * 4)
	out.fill(0)

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
	var frequency := props.noise_frequency
	var amplitude := props.noise_amplitude
	var bump := 0.5 * amplitude
	const EPS := 1.5

	for y in height:
		for x in width:
			var i := (y * width + x) * 4
			if solid[i + 3] != 255:
				continue

			var dx := x - cx
			var dy := y - cy
			var n := perlin.get_noise_2d(x * frequency, y * frequency)
			var r := maxf(base_radius * (1.0 + n * amplitude), 0.001)
			var nx := dx / r
			var ny := dy / r
			var r2 := minf(nx * nx + ny * ny, 1.0)
			var nz := sqrt(1.0 - r2)

			var nxp := perlin.get_noise_2d((x + EPS) * frequency, y * frequency)
			var nxm := perlin.get_noise_2d((x - EPS) * frequency, y * frequency)
			var nyp := perlin.get_noise_2d(x * frequency, (y + EPS) * frequency)
			var nym := perlin.get_noise_2d(x * frequency, (y - EPS) * frequency)
			nx += (nxp - nxm) * bump
			ny += (nyp - nym) * bump

			var length := sqrt(nx * nx + ny * ny + nz * nz)
			if length < 0.0001:
				length = 1.0

			out[i] = clampi(int((nx / length * 0.5 + 0.5) * 255.0), 0, 255)
			out[i + 1] = clampi(int((ny / length * 0.5 + 0.5) * 255.0), 0, 255)
			out[i + 2] = clampi(int((nz / length * 0.5 + 0.5) * 255.0), 0, 255)
			out[i + 3] = 255

	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, out)
