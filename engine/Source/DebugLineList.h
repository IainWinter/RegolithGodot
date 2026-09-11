#pragma once

#include "Color.h"
#include "Coordinate/AxisAlignedAreaTree.h"
#include "Coordinate/Transform.h"
#include "Math/Vector.h"

#include <godot_cpp/templates/local_vector.hpp>

#include <godot_cpp/variant/string.hpp>

#include <ostream>
#include <istream>
#include <mutex>

enum DebugLayer {
    DebugLayer_Default,
    DebugLayer_A,
    DebugLayer_B,

    DebugLayer_Count
};

enum DebugName {
    DebugName_Default,

    DebugName_Physics_Broadphase_Tree,
    DebugName_Physics_Broadphase_Overlap_World_Bounds,
    DebugName_Physics_Broadphase_Overlap_World_Pair_Line,
    DebugName_Physics_Contact_Point,
    DebugName_Physics_Contact_Point_Normal,
    DebugName_Physics_Surface_Point,
    DebugName_Physics_Rope_Node,
    DebugName_Physics_Force_Bias,
    DebugName_Physics_Force_Correction,
    DebugName_Physics_Force_Velocity,
    DebugName_Physics_Force_World,
    DebugName_Physics_Joint,
    DebugName_Physics_Joint_Rotator,
    DebugName_Physics_Joint_Rope,
    DebugName_Physics_Joint_Anchor,
    DebugName_Physics_Drag,

    DebugName_Ai,
    DebugName_Ai_Pathfinding,
    DebugName_Ai_Path,
    DebugName_Ai_Flocker,
    DebugName_Ai_Los_Clear,
    DebugName_Ai_Los_Blocked,
    DebugName_Ai_Thrower,
    DebugName_Ai_Shield,
    DebugName_Ai_Trap,

    DebugName_Sprite,
    DebugName_Sprite_Chunk,
    DebugName_World_Tree,

    DebugName_Aim_Assist,

    DebugName_Region,
    DebugName_Region_Spawn_Zone,
    DebugName_Region_Asteroid_Belt,
    DebugName_Region_Generated,
    DebugName_Region_StableSpawnAttemptAABB,

    DebugName_Explosion,
    DebugName_Explosion_Force,

    DebugName_Count
};

struct DebugColorEntry {
    Color4 color;
    bool enabled;
};

class DebugRendererColorMap {
public:
    DebugRendererColorMap();

    void set_name_color(DebugName name, Color4 color);
    void set_name_enabled(DebugName name, bool enabled);

    void set_layer_tint(DebugLayer layer, Color4 tint);
    void set_layer_enabled(DebugLayer layer, bool enabled);

    Color4 map_color(DebugLayer layer, DebugName name) const;

    bool is_enabled(DebugLayer layer, DebugName name) const;

    auto& colors() { return m_debug_name_color; }
    auto& tints() { return m_debug_layer_tint; }

    const auto& colors() const { return m_debug_name_color; }
    const auto& tints() const { return m_debug_layer_tint; }

private:
    DebugColorEntry m_debug_name_color[static_cast<size_t>(DebugName_Count)];
    DebugColorEntry m_debug_layer_tint[static_cast<size_t>(DebugLayer_Count)];
};

struct DebugRendererLine {
    godot::Vector2 a, b;
    Color4 color;
    DebugName name;
};

struct DebugRendererLineInternal {
    godot::Vector2 a, b;
    DebugLayer layer;
    DebugName name;
};

class DebugRendererLineList {
public:
    const godot::LocalVector<DebugRendererLine>& get_lines();

    void invalidate_cache();
    void clear_lines();

    void line                  (godot::Vector2 a, godot::Vector2 b,                       DebugName name = DebugName_Default, DebugLayer layer = DebugLayer_Default);
    void ray                   (godot::Vector2 origin, godot::Vector2 ray,                DebugName name = DebugName_Default, DebugLayer layer = DebugLayer_Default);
    void circle                (godot::Vector2 origin, float radius,            DebugName name = DebugName_Default, DebugLayer layer = DebugLayer_Default);
    void capsule               (godot::Vector2 a, godot::Vector2 b, float radius,         DebugName name = DebugName_Default, DebugLayer layer = DebugLayer_Default);
    void arc                   (godot::Vector2 origin, float radius, float min_angle, float max_angle, DebugName name = DebugName_Default, DebugLayer layer = DebugLayer_Default);
    void axis_aligned_box      (const AxisAlignedBox& box,            DebugName name = DebugName_Default, DebugLayer layer = DebugLayer_Default);
    void axis_aligned_area_tree(const AxisAlignedAreaTreeIndex& tree, DebugName name = DebugName_Default, DebugLayer layer = DebugLayer_Default);
    void polygon               (const godot::Vector2* points, int count,        DebugName name = DebugName_Default, DebugLayer layer = DebugLayer_Default);
    void transform             (const Transform& transform,           DebugName name = DebugName_Default, DebugLayer layer = DebugLayer_Default);

private:
    std::mutex m_lines_mutex;
    godot::LocalVector<DebugRendererLineInternal> m_lines;

    bool m_cache_valid;
    godot::LocalVector<DebugRendererLine> m_cache;
};

// Static accessors so this doesn't need to be passed around
// not mt

DebugRendererColorMap& debug_color_map();

int& debug_render_circle_steps();

DebugRendererLineList& debug_render();
DebugRendererLineList& debug_render_fixed();
DebugRendererLineList& debug_render_render();

void debug_render_invalidate_cache();

#define IF_DEBUG if (true)
