// lightning bolts on the world cell grid, from the rope pixel line shader.
// segment endpoints come in cell space through the instance custom data and
// the instance transform scales cells to pixels (Lightning.gd sets it from
// pixels_per_unit / CELLS_PER_CHUNK). the fragment fills whole cells within
// half_width of the segment with the core color, and the ring of cells out
// to glow_width with a dimmed glow. COLOR is the bolt color already faded by
// age, so both the core and the glow go out with it

shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float half_width = 0.5;
uniform float glow_width = 1.0;
uniform float glow_strength = 0.35;
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float core_mix = 0.5;

varying vec2 grid_pos;
varying flat vec2 point_a;
varying flat vec2 point_b;
varying flat vec4 line_color;

void vertex() {
    vec2 a = INSTANCE_CUSTOM.xy;
    vec2 b = INSTANCE_CUSTOM.zw;

    vec2 dir = b - a;
    float len = length(dir);
    vec2 x_basis = len > 1e-6 ? dir / len : vec2(1.0, 0.0);
    vec2 y_basis = vec2(-x_basis.y, x_basis.x);

    float margin = half_width + glow_width + 1.5;
    vec2 p = mix(a, b, UV.x) + (x_basis * VERTEX.x + y_basis * VERTEX.y) * margin;

    grid_pos = p;
    point_a = a;
    point_b = b;
    line_color = COLOR;

    VERTEX = p;
}

void fragment() {
    vec2 cell = floor(grid_pos) + 0.5;

    vec2 ab = point_b - point_a;
    float len2 = max(dot(ab, ab), 1e-12);
    float t = clamp(dot(cell - point_a, ab) / len2, 0.0, 1.0);
    float d = distance(cell, point_a + ab * t);

    if (d > half_width + glow_width || line_color.a <= 0.0) {
        discard;
    }

    if (d <= half_width) {
        COLOR = vec4(mix(line_color.rgb, core_color.rgb, core_mix), line_color.a);
    } else {
        float falloff = 1.0 - (d - half_width) / max(glow_width, 1e-4);
        COLOR = vec4(line_color.rgb, line_color.a * glow_strength * falloff);
    }
}
