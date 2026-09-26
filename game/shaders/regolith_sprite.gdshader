// sprite chunks sample the world atlas. u carries the page in its integer
// part, the mask low byte holds the cell type, its high byte the heat

shader_type canvas_item;

uniform sampler2DArray color_atlas : filter_nearest, repeat_disable;
uniform sampler2DArray mask_atlas : filter_nearest, repeat_disable;

// burn of the original sprite.hlsl: a cell first chars toward c_charred,
// then past c_burn_char_heat glows up the blackbody ramp, deep red to
// orange to pale yellow, with a per texel jitter so a front is ragged
const vec3 CHARRED = vec3(26.0, 18.0, 14.0) / 255.0;
const float BURN_CHAR_HEAT = 0.5;

vec3 blackbody_color(float t) {
    vec3 c = mix(vec3(0.35, 0.02, 0.0), vec3(1.0, 0.35, 0.02), clamp(t * 2.0, 0.0, 1.0));
    return mix(c, vec3(1.0, 0.9, 0.45), clamp(t * 2.0 - 1.0, 0.0, 1.0));
}

void fragment() {
    float layer = floor(UV.x * 0.5);
    vec3 uvw = vec3(UV.x - layer * 2.0, UV.y, layer);

    vec2 m = texture(mask_atlas, uvw).rg * 255.0;
    int lo = int(m.r + 0.5);
    int hi = int(m.g + 0.5);

    if ((lo & 31) == 0 || (lo & 32) != 0) {
        discard;
    }

    vec4 c = texture(color_atlas, uvw);

    int heat = (hi >> 2) & 15;

    if (heat > 0) {
        vec2 texel = floor(uvw.xy * vec2(textureSize(mask_atlas, 0).xy));
        float jitter = fract(sin(dot(texel + uvw.z * 1024.0, vec2(12.9898, 78.233))) * 43758.5453);
        float burn = clamp(float(heat) / 15.0 + (jitter - 0.5) * 0.15, 0.0, 1.0);

        float char_amount = clamp(burn / BURN_CHAR_HEAT, 0.0, 1.0);
        float glow_amount = clamp((burn - BURN_CHAR_HEAT) / (1.0 - BURN_CHAR_HEAT), 0.0, 1.0);

        c.rgb = mix(c.rgb, CHARRED, char_amount);
        c.rgb = mix(c.rgb, blackbody_color(glow_amount), glow_amount);
    }

    COLOR = c * COLOR;
}
