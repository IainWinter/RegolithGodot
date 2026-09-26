#include "LineRender.h"

#include <godot_cpp/classes/rendering_server.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

constexpr float k_pi = 3.14159265358979f;
constexpr float k_min_segment = 1e-4f;

struct SignedRow {
    float mul;
    float add;
    float alpha;
};

bool is_center(float mul, float add) {
    return mul == 0.f && add == 0.f;
}

}

void LineRender::clear() {
    m_points.resize(0);
    m_colors.resize(0);
    m_indices.resize(0);
    m_bounds_min = Vector2(INFINITY, INFINITY);
    m_bounds_max = Vector2(-INFINITY, -INFINITY);
    m_lines = 0;
}

int LineRender::line_count() const {
    return m_lines;
}

int LineRender::vertex_count() const {
    return static_cast<int>(m_points.size());
}

bool LineRender::has_bounds() const {
    return m_points.size() > 0;
}

Rect2 LineRender::bounds() const {
    if (!has_bounds()) {
        return Rect2();
    }

    return Rect2(m_bounds_min, m_bounds_max - m_bounds_min);
}

int LineRender::push(Vector2 point, Color color, float alpha) {
    int index = static_cast<int>(m_points.size());

    color.a *= alpha;
    m_points.push_back(point);
    m_colors.push_back(color);
    m_bounds_min = m_bounds_min.min(point);
    m_bounds_max = m_bounds_max.max(point);

    return index;
}

void LineRender::triangle(int a, int b, int c) {
    m_indices.push_back(a);
    m_indices.push_back(b);
    m_indices.push_back(c);
}

void LineRender::add_polyline(const PackedVector2Array& points, const PackedFloat32Array& widths, const PackedColorArray& colors, const Style& style) {
    if (points.size() < 2 || widths.size() == 0 || colors.size() == 0) {
        return;
    }

    LocalVector<Vector2> run;
    LocalVector<float> half_widths;
    LocalVector<Color> run_colors;

    for (int64_t i = 0; i < points.size(); i++) {
        Vector2 point = points[i];

        if (run.size() > 0 && run[run.size() - 1].distance_squared_to(point) < k_min_segment * k_min_segment) {
            continue;
        }

        run.push_back(point);
        half_widths.push_back(0.5f * static_cast<float>(widths[std::min<int64_t>(i, widths.size() - 1)]));
        run_colors.push_back(colors[std::min<int64_t>(i, colors.size() - 1)]);
    }

    if (run.size() < 2) {
        return;
    }

    int cap_resolution = std::max(1, style.cap_resolution);

    if (style.glow_width > 0.f && style.glow_strength > 0.f) {
        Profile glow;
        glow.rows[0] = {0.f, 0.f, style.glow_strength};
        glow.rows[1] = {1.f, style.glow_width, 0.f};
        glow.count = 2;
        add_stroke(run, half_widths, run_colors, glow, cap_resolution);
    }

    Profile core;
    core.rows[0] = {1.f, 0.f, 1.f};
    core.count = 1;

    if (style.feather > 0.f) {
        core.rows[1] = {1.f, style.feather, 0.f};
        core.count = 2;
    }

    add_stroke(run, half_widths, run_colors, core, cap_resolution);
    m_lines++;
}

void LineRender::add_stroke(const LocalVector<Vector2>& points, const LocalVector<float>& half_widths, const LocalVector<Color>& colors, const Profile& profile, int cap_resolution) {
    bool center_row = is_center(profile.rows[0].mul, profile.rows[0].add);

    LocalVector<SignedRow> rows;

    for (int j = profile.count - 1; j >= (center_row ? 1 : 0); j--) {
        rows.push_back({-profile.rows[j].mul, -profile.rows[j].add, profile.rows[j].alpha});
    }

    for (int j = 0; j < profile.count; j++) {
        rows.push_back({profile.rows[j].mul, profile.rows[j].add, profile.rows[j].alpha});
    }

    int row_count = static_cast<int>(rows.size());
    int count = static_cast<int>(points.size());

    // one strip with the rows shared at every point along the miter of the
    // bend there, so the segments neither overlap (which an additive blend
    // would brighten) nor leave a wedge open. the miter is capped at twice
    // the width for sharp bends
    int base = static_cast<int>(m_points.size());

    for (int i = 0; i < count; i++) {
        Vector2 in = i > 0 ? (points[i] - points[i - 1]).normalized() : (points[i + 1] - points[i]).normalized();
        Vector2 out = i + 1 < count ? (points[i + 1] - points[i]).normalized() : in;
        Vector2 n0 = Vector2(-in.y, in.x);
        Vector2 n1 = Vector2(-out.y, out.x);
        Vector2 miter = n0 + n1;
        float scale = 1.f;

        if (miter.length_squared() < 1e-6f) {
            miter = n0;
        }

        else {
            miter = miter.normalized();
            scale = 1.f / std::max(miter.dot(n0), 0.5f);
        }

        for (const SignedRow& row : rows) {
            push(points[i] + miter * ((half_widths[i] * row.mul + row.add) * scale), colors[i], row.alpha);
        }
    }

    for (int i = 0; i + 1 < count; i++) {
        int a = base + i * row_count;
        int b = a + row_count;

        for (int r = 0; r + 1 < row_count; r++) {
            triangle(a + r, b + r, b + r + 1);
            triangle(a + r, b + r + 1, a + r + 1);
        }
    }

    Vector2 first_dir = (points[1] - points[0]).normalized();
    Vector2 first_normal = Vector2(-first_dir.y, first_dir.x);
    add_fan(points[0], half_widths[0], colors[0], first_normal, k_pi, cap_resolution, profile);

    Vector2 last_dir = (points[count - 1] - points[count - 2]).normalized();
    Vector2 last_normal = Vector2(-last_dir.y, last_dir.x);
    add_fan(points[count - 1], half_widths[count - 1], colors[count - 1], last_normal, -k_pi, cap_resolution, profile);
}

void LineRender::add_fan(Vector2 center, float half_width, Color color, Vector2 from, float angle, int steps, const Profile& profile) {
    struct Entry {
        float radius;
        float alpha;
    };

    LocalVector<Entry> entries;

    if (!is_center(profile.rows[0].mul, profile.rows[0].add)) {
        entries.push_back({0.f, profile.rows[0].alpha});
    }

    for (int j = 0; j < profile.count; j++) {
        entries.push_back({half_width * profile.rows[j].mul + profile.rows[j].add, profile.rows[j].alpha});
    }

    for (int b = 0; b + 1 < static_cast<int>(entries.size()); b++) {
        const Entry& inner = entries[b];
        const Entry& outer = entries[b + 1];

        if (outer.radius <= inner.radius) {
            continue;
        }

        if (inner.radius <= 0.f) {
            int c = push(center, color, inner.alpha);
            int first = static_cast<int>(m_points.size());

            for (int k = 0; k <= steps; k++) {
                push(center + from.rotated(angle * k / steps) * outer.radius, color, outer.alpha);
            }

            for (int k = 0; k < steps; k++) {
                triangle(c, first + k, first + k + 1);
            }
        }

        else {
            int first = static_cast<int>(m_points.size());

            for (int k = 0; k <= steps; k++) {
                Vector2 dir = from.rotated(angle * k / steps);
                push(center + dir * inner.radius, color, inner.alpha);
                push(center + dir * outer.radius, color, outer.alpha);
            }

            for (int k = 0; k < steps; k++) {
                int i0 = first + 2 * k;
                triangle(i0, i0 + 1, i0 + 3);
                triangle(i0, i0 + 3, i0 + 2);
            }
        }
    }
}

void LineRender::draw(RID item) const {
    if (m_indices.size() == 0) {
        return;
    }

    RenderingServer::get_singleton()->canvas_item_add_triangle_array(item, m_indices, m_points, m_colors);
}
