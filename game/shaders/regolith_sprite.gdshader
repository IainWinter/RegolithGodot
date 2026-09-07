// sprite chunks sample the world atlas. u carries the page in its integer
// part, the mask low byte holds the cell type, its high byte the heat

shader_type canvas_item;

uniform sampler2DArray color_atlas : filter_nearest, repeat_disable;
uniform sampler2DArray mask_atlas : filter_nearest, repeat_disable;

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
    c.rgb = mix(c.rgb, vec3(1.0, 0.55, 0.15), float(heat) / 15.0 * 0.85);

    COLOR = c * COLOR;
}
