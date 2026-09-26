// the canvas side of the one ParticleEffect node, the blend of the original
// particle pass: One / One. every quad adds color.rgb * (color.a + emissive)
// (the vertex color regolith_particles.gdshader hands over) onto the scene
// and never covers anything, so a spark glows over the rock it hit and smoke
// lifts the scene instead of replacing it. blend_premul_alpha is
// src + dst * (1 - a), with the alpha written as 0 that is plain addition.
// the frame pick is the one CanvasItemMaterial.particles_animation does:
// INSTANCE_CUSTOM.z is the frame phase over h_frames x v_frames cells
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform int h_frames = 4;
uniform int v_frames = 2;

void vertex() {
	float columns = float(h_frames);
	float rows = float(v_frames);
	float total = columns * rows;
	float frame = clamp(floor(INSTANCE_CUSTOM.z * total), 0.0, total - 1.0);
	UV /= vec2(columns, rows);
	UV += vec2(mod(frame, columns) / columns, floor((frame + 0.5) / columns) / rows);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb * tex.a * COLOR.rgb, 0.0);
}
