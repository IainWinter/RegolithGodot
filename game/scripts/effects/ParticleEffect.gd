@tool
extends GPUParticles2D
class_name ParticleEffect

# the one particle node every effect draws through: a single draw call off
# the particles atlas (game/images/effects/particles_atlas.png, made by
# tools/MakeParticlesAtlas.gd). port of the particle pass of the original
# engine. the node never emits on its own, burst() pushes a handful of quads
# out with emit_particle and the shader flies them (see
# regolith_particles.gdshader). every ParticleProps seen gets a slot in the
# uniform arrays of an own copy of the process material, MAX_SLOTS of them,
# and the slot rides along in CUSTOM.w with the burst seed. the canvas
# material picks the atlas frame from CUSTOM.z and adds the quads onto the
# scene, One / One like the particle pass of the original (see
# regolith_particles_canvas.gdshader). the script samples only
# what the emit angle turns, the spawn offset and velocity. positions in
# world pixels, props in sim units.
#
# a burst in its own colors (a hit spark in its projectile's hue, the player
# cloud's tint) gets a slot of its own: the props' numbers with the derived
# ramp, cached by props and the color rounded to COLOR_STEPS per channel.
# particles carry nothing per burst but CUSTOM, and every channel of it is
# taken (age, emit angle, atlas frame, slot + seed), so the colors ride in
# the slot. at most MAX_COLOR_SLOTS of those, past it a burst takes the
# slot of the nearest color its props already has, else the props' own

# keep in step with MAX_SLOTS in regolith_particles.gdshader
const MAX_SLOTS := 48
const MAX_COLOR_SLOTS := 16
const COLOR_STEPS := 16.0

var slots := {}
var counts := {}
# slots handed out so far, props and color slots together
var used_slots := 0
# props -> {rounded color key -> slot} of the color slots
var color_slots := {}
# slot -> [props, color, is source] of the color slots, for refresh
var color_slot_sources := {}
# the slot the last burst flew in, for tests
var last_burst_slot := -1
var emitted := 0
var pixels_per_unit := 0.0
var frame_count := 1
var ready_to_emit := false
# the start velocities of the last burst, sim units per second in world
# axes, for tests
var last_burst_velocities := PackedVector2Array()
# the same by props, the last burst of each
var burst_velocities := {}

var life_damping := PackedVector4Array()
var spin := PackedVector4Array()
var tilt := PackedVector4Array()
var tilt_velocity := PackedVector4Array()
var scale_begin := PackedVector4Array()
var scale_end := PackedVector4Array()
var color_begin := PackedVector4Array()
var color_end := PackedVector4Array()
var color_frames := PackedVector4Array()

func _ready() -> void:
	emitting = false
	fixed_fps = 0
	interpolate = false
	local_coords = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visibility_rect = Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
	pixels_per_unit = RegolithWorld.pixels_per_unit()

	for table in [life_damping, spin, tilt, tilt_velocity, scale_begin, scale_end, color_begin, color_end, color_frames]:
		table.resize(MAX_SLOTS)

	if texture == null:
		push_warning("ParticleEffect %s has no atlas texture, it draws nothing" % name)
		return

	var frames := atlas_frames()
	if frames == Vector2i.ZERO:
		push_warning("ParticleEffect %s needs a canvas material that picks the atlas frame (regolith_particles_canvas.gdshader, or a CanvasItemMaterial with particles_animation), it draws nothing" % name)
		return

	if not process_material is ShaderMaterial:
		push_warning("ParticleEffect %s has no particles material, it draws nothing" % name)
		return

	frame_count = frames.x * frames.y

	var own: ShaderMaterial = process_material.duplicate()
	own.set_shader_parameter("pixels_per_unit", pixels_per_unit)
	# the quad is the whole texture, the frames only pick a part of it
	own.set_shader_parameter("quad_size", Vector2(texture.get_size()))
	own.set_shader_parameter("frame_count", float(frame_count))
	process_material = own
	upload()
	ready_to_emit = true

# the atlas grid the canvas material picks frames from, columns by rows:
# the shared additive shader's h_frames and v_frames, or the
# particles_animation frames of a CanvasItemMaterial. zero when the
# material picks none
func atlas_frames() -> Vector2i:
	var canvas := material as CanvasItemMaterial
	if canvas != null:
		return Vector2i(canvas.particles_anim_h_frames, canvas.particles_anim_v_frames) if canvas.particles_animation else Vector2i.ZERO

	var shader := material as ShaderMaterial
	if shader != null:
		var h: Variant = shader.get_shader_parameter("h_frames")
		var v: Variant = shader.get_shader_parameter("v_frames")
		if h != null and v != null:
			return Vector2i(int(h), int(v))

	return Vector2i.ZERO

# the slot of props in the uniform arrays, given on first sight. -1 past
# MAX_SLOTS
func slot_for(props: ParticleProps) -> int:
	if slots.has(props):
		return slots[props]

	if used_slots >= MAX_SLOTS:
		push_warning("ParticleEffect %s is out of slots (%d), %s draws nothing" % [name, MAX_SLOTS, props.resource_path])
		return -1

	var slot := used_slots
	used_slots += 1
	slots[props] = slot
	counts[props] = 0
	write_slot(slot, props)

	if ready_to_emit:
		upload()

	return slot

# the slot of props flown in color: with source, the ramp derived from
# that source color (props with color_from_source), otherwise color replaces
# the props' begin color (a tint). base is the props' own slot, the
# fallback once the color slots run out and no color of props is cached
func color_slot_for(props: ParticleProps, base: int, color: Color, source: bool) -> int:
	var key := Vector4i(roundi(color.r * COLOR_STEPS), roundi(color.g * COLOR_STEPS), roundi(color.b * COLOR_STEPS), -1 if source else roundi(color.a * COLOR_STEPS))
	var cached: Dictionary = color_slots.get_or_add(props, {})

	if cached.has(key):
		return cached[key]

	if color_slot_sources.size() >= MAX_COLOR_SLOTS or used_slots >= MAX_SLOTS:
		var nearest := base
		var best := INF

		for other: Vector4i in cached:
			var distance := Vector4(other - key).length_squared()
			if distance < best:
				best = distance
				nearest = cached[other]

		return nearest

	var rounded := Color(key.x / COLOR_STEPS, key.y / COLOR_STEPS, key.z / COLOR_STEPS, 1.0 if source else key.w / COLOR_STEPS)
	var slot := used_slots
	used_slots += 1
	cached[key] = slot
	color_slot_sources[slot] = [props, rounded, source]
	write_color_slot(slot, props, rounded, source)

	if ready_to_emit:
		upload()

	return slot

func write_color_slot(slot: int, props: ParticleProps, color: Color, source: bool) -> void:
	if source:
		var ramp := source_ramp(props, color)
		write_slot(slot, props, ramp[0], ramp[1])
	else:
		write_slot(slot, props, color, props.color_end)

# the begin and end color of props flown in the hue of source. the props'
# ramp of the original hit spark runs from a near white overbright core
# (1, 1.1, 0.85) to a darker saturated orange (0.95, 0.55, 0.1) at half
# alpha. the derived one keeps that shape in the source's hue: the source
# at full value (its brightest channel at 1, a dim trail color is still a
# hue), the begin that brightened toward white by as much as the props'
# begin is whiter than its end (whiteness = lowest over highest channel)
# and scaled to the begin's brightest channel, the end the plain source
# scaled to the end's brightest channel. alphas are the props', so with
# emissive the begin runs as far over 1 as before and the particle
# shader's tonemap treats it the same
static func source_ramp(props: ParticleProps, source: Color) -> Array[Color]:
	var peak := peak_of(source)
	var hue := Color(source.r / peak, source.g / peak, source.b / peak, 1.0) if peak > 0.0 else Color.WHITE
	var core := hue.lerp(Color.WHITE, core_whitening(props)) * peak_of(props.color_begin)
	var tail := hue * peak_of(props.color_end)
	return [Color(core.r, core.g, core.b, props.color_begin.a), Color(tail.r, tail.g, tail.b, props.color_end.a)]

# how far toward white the begin of props sits past its end, 0 to 1: the
# lerp to white a source takes for its begin color. about 0.75 for the hit
# spark
static func core_whitening(props: ParticleProps) -> float:
	var begin := whiteness(props.color_begin)
	var end := whiteness(props.color_end)

	if end >= 1.0:
		return 0.0

	return clampf((begin - end) / (1.0 - end), 0.0, 1.0)

# lowest channel over highest, 1 for a gray, 0 for a pure hue
static func whiteness(color: Color) -> float:
	var peak := peak_of(color)
	return minf(color.r, minf(color.g, color.b)) / peak if peak > 0.0 else 1.0

static func peak_of(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b))

# the props' numbers into the slot's uniform rows, in the given colors
func write_slot(slot: int, props: ParticleProps, begin := Color(0.0, 0.0, 0.0, -1.0), end := Color(0.0, 0.0, 0.0, -1.0)) -> void:
	if begin.a < 0.0:
		begin = props.color_begin
	if end.a < 0.0:
		end = props.color_end

	life_damping[slot] = Vector4(props.life_min, props.life_max, props.damping_min, props.damping_max)
	spin[slot] = Vector4(props.angle_min, props.angle_max, props.angular_velocity_min, props.angular_velocity_max)
	tilt[slot] = Vector4(props.angle_xy_min.x, props.angle_xy_min.y, props.angle_xy_max.x, props.angle_xy_max.y)
	tilt_velocity[slot] = Vector4(props.angular_velocity_xy_min.x, props.angular_velocity_xy_min.y, props.angular_velocity_xy_max.x, props.angular_velocity_xy_max.y)
	scale_begin[slot] = Vector4(props.scale_begin_min.x, props.scale_begin_min.y, props.scale_begin_max.x, props.scale_begin_max.y)
	scale_end[slot] = Vector4(props.scale_end.x, props.scale_end.y, props.scale_factor, props.angular_damping)
	color_begin[slot] = Vector4(begin.r, begin.g, begin.b, begin.a)
	color_end[slot] = Vector4(end.r, end.g, end.b, end.a)
	color_frames[slot] = Vector4(props.color_factor, props.emissive, float(props.frame_min), float(props.frame_max))

# re-read edited props into their slot (the editor preview after an
# inspector change), a no-op for props that never emitted here
func refresh(props: ParticleProps) -> void:
	if not slots.has(props):
		return

	write_slot(slots[props], props)

	for slot: int in color_slots.get(props, {}).values():
		var entry: Array = color_slot_sources[slot]
		write_color_slot(slot, props, entry[1], entry[2])

	if ready_to_emit:
		upload()

# the world's scale the particles fly at, the editor preview sets the
# game's value since no world is active there
func set_pixels_per_unit(value: float) -> void:
	pixels_per_unit = value

	if process_material is ShaderMaterial and ready_to_emit:
		process_material.set_shader_parameter("pixels_per_unit", pixels_per_unit)

func upload() -> void:
	var own: ShaderMaterial = process_material
	own.set_shader_parameter("life_damping", life_damping)
	own.set_shader_parameter("spin", spin)
	own.set_shader_parameter("tilt", tilt)
	own.set_shader_parameter("tilt_velocity", tilt_velocity)
	own.set_shader_parameter("scale_begin", scale_begin)
	own.set_shader_parameter("scale_end", scale_end)
	own.set_shader_parameter("color_begin", color_begin)
	own.set_shader_parameter("color_end", color_end)
	own.set_shader_parameter("color_frames", color_frames)

func count_of(props: ParticleProps) -> int:
	return counts.get(props, 0)

# count particles of props at position, their spawn frame turned to angle.
# a count below zero takes the props range. a tint with alpha >= 0 replaces
# the props' begin color for this burst (the player cloud reddening). a
# speed >= 0 is the speed of what caused the burst, sim units per second:
# props with speed_from_source scale their velocity range so its fastest
# corner leaves at that speed. a source with alpha >= 0 is the color of
# what caused the burst: props with color_from_source fly their ramp in its
# hue (see source_ramp). both go through a color slot (see color_slot_for)
func burst(props: ParticleProps, position: Vector2, angle := 0.0, count := -1, tint := Color(0.0, 0.0, 0.0, -1.0), speed := -1.0, source := Color(0.0, 0.0, 0.0, -1.0)) -> void:
	if props == null or not ready_to_emit or not visible or not is_inside_tree():
		return

	var slot := slot_for(props)
	if slot < 0:
		return

	if source.a >= 0.0 and props.color_from_source:
		slot = color_slot_for(props, slot, source, true)
	elif tint.a >= 0.0:
		slot = color_slot_for(props, slot, tint, false)

	last_burst_slot = slot

	if count < 0:
		count = randi_range(props.count_min, props.count_max)

	var emit_angle := angle + props.direction_offset
	var custom := Color(0.0, emit_angle, 0.0, float(slot) + randf() * 0.999)
	var begin := Color(color_begin[slot].x, color_begin[slot].y, color_begin[slot].z, color_begin[slot].w)
	var flags := EMIT_FLAG_POSITION | EMIT_FLAG_VELOCITY | EMIT_FLAG_COLOR | EMIT_FLAG_CUSTOM
	var velocity_scale := 1.0

	if speed >= 0.0 and props.speed_from_source:
		var top := props.top_speed()
		if top > 0.0:
			velocity_scale = speed / top

	last_burst_velocities.resize(count)

	for i in count:
		var offset := Vector2(randf_range(props.offset_min.x, props.offset_max.x), randf_range(props.offset_min.y, props.offset_max.y))
		var velocity := Vector2(randf_range(props.velocity_min.x, props.velocity_max.x), randf_range(props.velocity_min.y, props.velocity_max.y))
		var start := position + offset.rotated(emit_angle) * pixels_per_unit
		var world_velocity := velocity.rotated(emit_angle) * velocity_scale
		last_burst_velocities[i] = world_velocity
		emit_particle(Transform2D(0.0, start), world_velocity * pixels_per_unit, begin, custom, flags)

	burst_velocities[props] = last_burst_velocities.duplicate()
	emitted += count
	counts[props] += count
