#pragma once

#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <godot_cpp/templates/local_vector.hpp>

// mirror of the engine's LineMesh / line_additive.hlsl: a polyline is one
// mitered strip with the width and color lerped from point to point and
// round caps on the two ends. everything is built on the cpu into one
// triangle array with per vertex colors, so the caller's material decides
// the blend (additive for lightning) and no shader is needed. the edge of
// the core fades to nothing over feather pixels in place of anti aliasing,
// and a second wider stroke under it fading from glow_strength on the
// center line to nothing at half width + glow_width stands in for the
// engine's radiance cascade emission. positions are in the owning canvas
// item's space, widths are full widths in the same units

class LineRender {
public:
    struct Style {
        float glow_width = 0.f;
        float glow_strength = 0.f;
        float feather = 1.f;
        int cap_resolution = 8;
    };

    void clear();

    // widths and colors are per point, or a single value for the whole line
    void add_polyline(const godot::PackedVector2Array& points, const godot::PackedFloat32Array& widths, const godot::PackedColorArray& colors, const Style& style);

    void draw(godot::RID item) const;

    int line_count() const;
    int vertex_count() const;
    bool has_bounds() const;
    godot::Rect2 bounds() const;

private:
    struct ProfileRow {
        float mul;
        float add;
        float alpha;
    };

    static constexpr int k_max_rows = 3;

    // the alpha of a stroke by distance from its center line, from the
    // center out: distance = half width * mul + add
    struct Profile {
        ProfileRow rows[k_max_rows];
        int count = 0;
    };

    void add_stroke(const godot::LocalVector<godot::Vector2>& points, const godot::LocalVector<float>& half_widths, const godot::LocalVector<godot::Color>& colors, const Profile& profile, int cap_resolution);
    void add_fan(godot::Vector2 center, float half_width, godot::Color color, godot::Vector2 from, float angle, int steps, const Profile& profile);
    int push(godot::Vector2 point, godot::Color color, float alpha);
    void triangle(int a, int b, int c);

    godot::PackedVector2Array m_points;
    godot::PackedColorArray m_colors;
    godot::PackedInt32Array m_indices;
    godot::Vector2 m_bounds_min;
    godot::Vector2 m_bounds_max;
    int m_lines = 0;
};
