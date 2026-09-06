#pragma once

#include "DebugLineList.h"

class RegolithWorld;

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

// draws the engine's debug line lists in world pixels. lines carry a name
// and a layer, each with a color and an on/off switch, off names are dropped
// at emit time. show it to see the lines
class RegolithDebugDraw : public godot::Node2D {
    GDCLASS(RegolithDebugDraw, godot::Node2D)

public:
    RegolithDebugDraw();

    void _enter_tree() override;
    void _process(double delta) override;
    void _draw() override;

    int get_name_count() const;
    godot::String get_name_label(int name) const;

    void set_name_enabled(int name, bool enabled);
    bool is_name_enabled(int name) const;
    void set_all_names_enabled(bool enabled);

    void set_name_color(int name, godot::Color color);
    godot::Color get_name_color(int name) const;

    // layers tint every name drawn on them
    int get_layer_count() const;

    void set_layer_enabled(int layer, bool enabled);
    bool is_layer_enabled(int layer) const;

    void set_layer_tint(int layer, godot::Color tint);
    godot::Color get_layer_tint(int layer) const;

    // script emitters, pixels, live until the next frame is drawn
    void add_line(godot::Vector2 a, godot::Vector2 b, int name, int layer);
    void add_ray(godot::Vector2 origin, godot::Vector2 ray, int name, int layer);
    void add_circle(godot::Vector2 origin, float radius, int name, int layer);
    void add_capsule(godot::Vector2 a, godot::Vector2 b, float radius, int name, int layer);
    void add_rect(godot::Rect2 rect, int name, int layer);

    // -1 is a one pixel line at any zoom
    void set_line_width(float width);
    float get_line_width() const;

    int get_line_count() const;

    struct NameEntry {
        DebugName value;
        const char* label;
    };

    static const NameEntry* names(int* count);
    static bool name_valid(int name);
    static bool layer_valid(int layer);

protected:
    static void _bind_methods();

private:
    void emit_world_lines(const RegolithWorld& world);
    void gather(const RegolithWorld& world, DebugRendererLineList& list);

private:
    float m_line_width = -1.f;
    godot::PackedVector2Array m_points;
    godot::PackedColorArray m_colors;
};
