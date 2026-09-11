#include "DebugLineList.h"

#include "Math/MathUtil.h"

#include <godot_cpp/core/math.hpp>

#define DRAW_METHOD_FILTER if (!debug_color_map().is_enabled(layer, name)) { return; }
// #define DRAW_METHOD_FILTER

static constexpr float k_pi_f = godot::Math::PI;
static constexpr float k_half_pi_f = godot::Math::PI * 0.5f;

DebugRendererColorMap::DebugRendererColorMap() {
    for (size_t i = 0; i < static_cast<size_t>(DebugName_Count); i++) {
        m_debug_name_color[i].color = {52, 143, 235, 255};
        m_debug_name_color[i].enabled = false;
    }

    for (size_t i = 0; i < static_cast<size_t>(DebugLayer_Count); i++) {
        m_debug_layer_tint[i].color = {255, 255, 255, 255};
        m_debug_layer_tint[i].enabled = true;
    }

    set_name_enabled(DebugName_Default, true);
    set_name_enabled(DebugName_Region, true);
    set_name_enabled(DebugName_Region_Spawn_Zone, true);

    set_name_color(DebugName_Default, {52, 143, 235, 255});
    set_name_color(DebugName_Region, {120, 200, 255, 255});
    set_name_color(DebugName_Region_Spawn_Zone, {255, 200, 80, 255});
    set_name_color(DebugName_Region_StableSpawnAttemptAABB, {255, 80, 80, 255});
    set_name_color(DebugName_Physics_Contact_Point, {255, 10, 10, 255});
    set_name_color(DebugName_Physics_Contact_Point_Normal, {255, 10, 10, 255});
    set_name_color(DebugName_Physics_Surface_Point, {10, 255, 10, 255});
    set_name_color(DebugName_Physics_Rope_Node, {255, 200, 10, 255});
    set_name_color(DebugName_Physics_Force_Bias, {255, 10, 255, 255});
    set_name_color(DebugName_Physics_Force_Correction, {10, 200, 255, 255});
    set_name_color(DebugName_Physics_Force_Velocity, {255, 255, 10, 255});
    set_name_color(DebugName_Physics_Force_World, {255, 120, 10, 255});
    set_name_color(DebugName_Physics_Joint, {120, 255, 120, 255});
    set_name_color(DebugName_Physics_Joint_Rotator, {120, 200, 255, 255});
    set_name_color(DebugName_Physics_Joint_Rope, {255, 200, 10, 255});
    set_name_color(DebugName_Physics_Joint_Anchor, {255, 255, 255, 255});
    set_name_color(DebugName_Physics_Drag, {255, 60, 200, 255});
    set_name_color(DebugName_Aim_Assist, {255, 136, 30, 255});
    set_name_color(DebugName_Ai_Pathfinding, {255, 60, 60, 255});
    set_name_color(DebugName_Ai_Path, {30, 255, 30, 255});
    set_name_color(DebugName_Ai_Flocker, {60, 255, 160, 255});
    set_name_color(DebugName_Ai_Los_Clear, {30, 255, 30, 255});
    set_name_color(DebugName_Ai_Los_Blocked, {255, 30, 30, 255});
    set_name_color(DebugName_Ai_Thrower, {255, 160, 30, 255});
    set_name_color(DebugName_Ai_Shield, {60, 220, 255, 255});
    set_name_color(DebugName_Ai_Trap, {255, 80, 220, 255});

    set_name_color(DebugName_Sprite, {80, 220, 255, 255});
    set_name_color(DebugName_Sprite_Chunk, {40, 120, 160, 255});
    set_name_color(DebugName_World_Tree, {200, 200, 80, 255});

    set_name_color(DebugName_Explosion, {255, 160, 40, 255});
    set_name_color(DebugName_Explosion_Force, {255, 60, 10, 255});

    set_layer_tint(DebugLayer_Default, {255, 255, 255, 255});
    set_layer_tint(DebugLayer_A, {255, 0, 255, 255});
    set_layer_tint(DebugLayer_B, {0, 255, 255, 255});
}

void DebugRendererColorMap::set_name_color(DebugName name, Color4 color) {
    m_debug_name_color[static_cast<size_t>(name)].color = color;
}

void DebugRendererColorMap::set_name_enabled(DebugName name, bool enabled) {
    m_debug_name_color[static_cast<size_t>(name)].enabled = enabled;
}

void DebugRendererColorMap::set_layer_tint(DebugLayer layer, Color4 tint) {
    m_debug_layer_tint[static_cast<size_t>(layer)].color = tint;
}

void DebugRendererColorMap::set_layer_enabled(DebugLayer layer, bool enabled) {
    m_debug_layer_tint[static_cast<size_t>(layer)].enabled = enabled;
}

Color4 DebugRendererColorMap::map_color(DebugLayer layer, DebugName name) const {
    Color4 l = m_debug_layer_tint[static_cast<size_t>(layer)].color;
    Color4 c = m_debug_name_color[static_cast<size_t>(name)].color;

    return l.mix(c);
}

bool DebugRendererColorMap::is_enabled(DebugLayer layer, DebugName name) const {
    bool l = m_debug_layer_tint[static_cast<size_t>(layer)].enabled;
    bool c = m_debug_name_color[static_cast<size_t>(name)].enabled;

    return l && c;
}

const godot::LocalVector<DebugRendererLine>& DebugRendererLineList::get_lines() {
    if (!m_cache_valid) {
        m_cache_valid = true;
        m_cache.clear();

        for (const DebugRendererLineInternal& l : m_lines) {
            if (debug_color_map().is_enabled(l.layer, l.name)) {
                m_cache.push_back({l.a, l.b, debug_color_map().map_color(l.layer, l.name), l.name});
            }
        }
    }

    return m_cache;
}

void DebugRendererLineList::invalidate_cache() {
    m_cache_valid = false;
}

void DebugRendererLineList::clear_lines() {
    std::unique_lock lock(m_lines_mutex);
    m_lines.clear();
    invalidate_cache();
}

void DebugRendererLineList::line(godot::Vector2 a, godot::Vector2 b, DebugName name, DebugLayer layer) {
    DRAW_METHOD_FILTER

    std::unique_lock lock(m_lines_mutex);
    m_lines.push_back({a, b, layer, name});
    m_cache_valid = false;
}

void DebugRendererLineList::ray(godot::Vector2 origin, godot::Vector2 ray, DebugName name, DebugLayer layer) {
    DRAW_METHOD_FILTER

    line(origin, origin + ray, name, layer);
}

void DebugRendererLineList::circle(godot::Vector2 origin, float radius, DebugName name, DebugLayer layer) {
    DRAW_METHOD_FILTER

    int steps = debug_render_circle_steps();

    for (int i = 0; i < steps; i++) {
        float aa = k_pi_f * 2.f / steps * i;
        float ab = k_pi_f * 2.f / steps * (i + 1);

        godot::Vector2 a = vector(aa) * radius + origin;
        godot::Vector2 b = vector(ab) * radius + origin;

        line(a, b, name, layer);
    }
}

void DebugRendererLineList::capsule(godot::Vector2 a, godot::Vector2 b, float radius, DebugName name, DebugLayer layer) {
    DRAW_METHOD_FILTER

    godot::Vector2 dir = b - a;
    float len = dir.length();

    if (len < 1e-6f) {
        circle(a, radius, name, layer);

        return;
    }

    godot::Vector2 x = dir / len;
    godot::Vector2 y = godot::Vector2(-x.y, x.x);
    float dir_angle = ::angle(x);

    line(a + y * radius, b + y * radius, name, layer);
    line(a - y * radius, b - y * radius, name, layer);

    arc(a, radius, dir_angle + k_half_pi_f, dir_angle + 3.f * k_half_pi_f, name, layer);
    arc(b, radius, dir_angle - k_half_pi_f, dir_angle + k_half_pi_f, name, layer);
}

void DebugRendererLineList::arc(godot::Vector2 origin, float radius, float min_angle, float max_angle, DebugName name, DebugLayer layer) {
    DRAW_METHOD_FILTER

    int steps = debug_render_circle_steps();
    float span = max_angle - min_angle;

    for (int i = 0; i < steps; i++) {
        float aa = min_angle + span / steps * i;
        float ab = min_angle + span / steps * (i + 1);

        godot::Vector2 a = vector(aa) * radius + origin;
        godot::Vector2 b = vector(ab) * radius + origin;

        line(a, b, name, layer);
    }
}

void DebugRendererLineList::axis_aligned_box(const AxisAlignedBox& box, DebugName name, DebugLayer layer) {
    DRAW_METHOD_FILTER

    godot::Vector2 a = box.min;
    godot::Vector2 b = godot::Vector2(box.min.x, box.max.y);
    godot::Vector2 c = box.max;
    godot::Vector2 d = godot::Vector2(box.max.x, box.min.y);

    line(a, b, name, layer);
    line(b, c, name, layer);
    line(c, d, name, layer);
    line(d, a, name, layer);
}

void DebugRendererLineList::axis_aligned_area_tree(const AxisAlignedAreaTreeIndex& tree, DebugName name, DebugLayer layer) {
    DRAW_METHOD_FILTER

    for (const AxisAlignedAreaTreeIndex::Node& node : tree.nodes()) {
        axis_aligned_box(node.box, name, layer);
    }
}

void DebugRendererLineList::polygon(const godot::Vector2* points, int count, DebugName name, DebugLayer layer) {
    DRAW_METHOD_FILTER

    if (count < 3) {
        return;
    }

    for (int i = 1; i < count; i++) {
        line(points[i - 1], points[i], name, layer);
    }

    line(points[count - 1], points[0], name, layer);
}

void DebugRendererLineList::transform(const Transform& transform, DebugName name, DebugLayer layer) {
    DRAW_METHOD_FILTER

    godot::Vector2 corners[4];
    transform.corners(corners);

    polygon(corners, 4, name, layer);
}

static DebugRendererColorMap s_color_map;
static int s_circle_steps = 12;
static DebugRendererLineList s_lines;
static DebugRendererLineList s_lines_fixed_tick;
static DebugRendererLineList s_lines_render_tick;

DebugRendererColorMap& debug_color_map() {
    return s_color_map;
}

int& debug_render_circle_steps() {
    return s_circle_steps;
}

DebugRendererLineList& debug_render() {
    return s_lines;
}

DebugRendererLineList& debug_render_fixed() {
    return s_lines_fixed_tick;
}

DebugRendererLineList& debug_render_render() {
    return s_lines_render_tick;
}

void debug_render_invalidate_cache() {
    s_lines.invalidate_cache();
    s_lines_fixed_tick.invalidate_cache();
    s_lines_render_tick.invalidate_cache();
}
