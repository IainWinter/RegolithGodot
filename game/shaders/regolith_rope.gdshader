// port of the engine's pixel_line shader. segment endpoints come in grid
// space through the instance custom data, the instance transform places grid
// cells in the world, the fragment fills whole cells whose center sits within
// half a cell of the segment

shader_type canvas_item;
render_mode blend_mix, unshaded;

const float half_width = 0.5;

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

    // pad the quad so every cell the frag can snap to is covered
    float margin = half_width + 1.5;
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

    if (d > half_width || line_color.a <= 0.0) {
        discard;
    }

    COLOR = line_color;
}
