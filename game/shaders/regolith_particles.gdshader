// port of the particle.hlsl of the original engine for the one ParticleEffect
// node. the node emits nothing on its own, every particle comes from
// emit_particle with position, velocity in pixels per second and
// custom = (age, emit angle, atlas frame phase, slot + seed). every
// ParticleProps the node has seen owns a slot in the uniform arrays, so one
// material and one draw call serve every effect. a particle hashes its life,
// damping, spin, tilt, start scale and atlas frame from its index and the
// seed. velocity damps, the quad turns in three axes with a damped angular
// velocity, scale and color lerp on a powered life ratio. the color goes
// out as color.rgb * (color.a + emissive) like the particle.hlsl frag of
// the original, put through the tonemap its HDR scene went through (see
// process), the canvas material adds it onto the scene (One / One, see
// regolith_particles_canvas.gdshader) and reads CUSTOM.z as the sprite
// sheet frame

shader_type particles;

// keep in step with ParticleEffect.MAX_SLOTS
const int MAX_SLOTS = 48;
// the exposure and white point of the original's tonemap, the
// RadianceCascadesPass settings rc_composite.hlsl ran with
const float EXPOSURE = 1.0;
const float WHITE_POINT = 2.0;

uniform float pixels_per_unit = 32.0;
// the quad GPUParticles2D draws, the whole atlas texture in pixels. the
// node builds its mesh at texture.get_size() no matter how many animation
// frames the canvas material cuts it into, frames only move the UVs
uniform vec2 quad_size = vec2(128.0, 64.0);
uniform float frame_count = 8.0;
uniform vec4 life_damping[MAX_SLOTS];
uniform vec4 spin[MAX_SLOTS];
uniform vec4 tilt[MAX_SLOTS];
uniform vec4 tilt_velocity[MAX_SLOTS];
uniform vec4 scale_begin[MAX_SLOTS];
uniform vec4 scale_end[MAX_SLOTS];
uniform vec4 color_begin[MAX_SLOTS];
uniform vec4 color_end[MAX_SLOTS];
uniform vec4 color_frames[MAX_SLOTS];

float hash(uint n) {
    n = (n << 13u) ^ n;
    n = n * (n * n * 15731u + 789221u) + 1376312589u;
    return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
    CUSTOM.x = 0.0;
}

void process() {
    int slot = clamp(int(floor(CUSTOM.w)), 0, MAX_SLOTS - 1);
    uint seed = INDEX * 131u + uint(fract(CUSTOM.w) * 1048576.0);

    // life min, life max, damping min, damping max
    vec4 ld = life_damping[slot];
    // angle min, angle max, angular velocity min, angular velocity max
    vec4 sp = spin[slot];
    // scale end xy, scale factor, angular damping
    vec4 se = scale_end[slot];
    // color factor, emissive, frame min, frame max
    vec4 cf = color_frames[slot];

    float life_time = mix(ld.x, ld.y, hash(seed + 1u));
    float damp = mix(ld.z, ld.w, hash(seed + 2u));
    vec2 tilt_start = mix(tilt[slot].xy, tilt[slot].zw, vec2(hash(seed + 3u), hash(seed + 4u)));
    float spin_start = CUSTOM.y + mix(sp.x, sp.y, hash(seed + 5u));
    vec2 tilt_speed = mix(tilt_velocity[slot].xy, tilt_velocity[slot].zw, vec2(hash(seed + 6u), hash(seed + 7u)));
    float spin_speed = mix(sp.z, sp.w, hash(seed + 8u));
    vec2 start_scale = mix(scale_begin[slot].xy, scale_begin[slot].zw, vec2(hash(seed + 9u), hash(seed + 10u)));
    float frame = min(floor(mix(cf.z, cf.w + 1.0, hash(seed + 11u))), cf.w);

    CUSTOM.x += DELTA;
    CUSTOM.z = (frame + 0.5) / frame_count;
    float age = CUSTOM.x;

    if (age >= life_time) {
        ACTIVE = false;
    }

    float ratio = clamp(age / life_time, 0.0, 1.0);
    float turn = (1.0 - exp(-se.w * age)) / (se.w + 1e-8);
    vec3 rotation = vec3(tilt_start, spin_start) + vec3(tilt_speed, spin_speed) * turn;

    float cx = cos(rotation.x); float sx = sin(rotation.x);
    float cy = cos(rotation.y); float sy = sin(rotation.y);
    float cz = cos(rotation.z); float sz = sin(rotation.z);

    // the original quad spanned -1..1, so a scale is a half extent: a
    // particle is twice its scale across, in units. the transform scales
    // the whole texture sized quad, not one frame of it: dividing by the
    // frame size drew every particle four times as long and twice as tall
    vec2 size = mix(start_scale, se.xy, pow(ratio, se.z)) * 2.0 * pixels_per_unit / quad_size;

    VELOCITY *= exp(-damp * DELTA);
    TRANSFORM[3].xy += VELOCITY.xy * DELTA;
    TRANSFORM[0] = vec4(cy * cz, cy * sz, 0.0, 0.0) * size.x;
    TRANSFORM[1] = vec4(sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, 0.0, 0.0) * size.y;

    vec4 color = mix(color_begin[slot], color_end[slot], pow(ratio, cf.x));
    // particle.hlsl: rgb * (a + emissive), which runs well over 1 on a spark.
    // the original drew that into an RGBA16F scene and rc_composite.hlsl put
    // the whole scene through the extended Reinhard
    //   mapped = hdr * (1 + hdr / white^2) / (1 + hdr), hdr = scene * exposure
    // so nothing reached the screen at its raw value: the cannon's muzzle
    // flash (1, 1.1, 0.85) showed as (0.63, 0.67, 0.56), its 0.4 gray casing
    // as 0.31, and the hit spark's (2.0, 1.16, 0.21) as (1.0, 0.69, 0.18),
    // orange, not the yellow a plain clamp makes of it. the canvas here is
    // not HDR, so the curve runs per particle instead, exactly what the
    // original showed where a particle lay over the dark background.
    // overlapping particles add up after the curve rather than before, a
    // little brighter than the original where sparks pile up
    vec3 hdr = color.rgb * (color.a + cf.y) * EXPOSURE;
    vec3 lit = hdr * (1.0 + hdr / (WHITE_POINT * WHITE_POINT)) / (1.0 + hdr);
    COLOR = vec4(lit, color.a);
}
