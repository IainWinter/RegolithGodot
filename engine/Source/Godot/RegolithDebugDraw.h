#pragma once

#include "DebugLineList.h"

class RegolithWorld;

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

// draws the engine's debug line lists in world pixels. lines carry a name
// and a layer, each with a color and an on/off switch, off names are dropped
// at emit time. show it to see the lines
//
// the node owns its copy of the color map and pushes it to the engine's
// global map on every change and when it enters the tree. when the game runs
// from the editor it registers the "regolith" debugger capture, says "ready",
// and applies whatever settings the editor's Debug Draw dock sends back.
// the game has one as the DebugDraw autoload, the editor plugin keeps one of
// its own and calls collect() to draw the lines over the edited scene
class RegolithDebugDraw : public godot::Node2D {
    GDCLASS(RegolithDebugDraw, godot::Node2D)

public:
    RegolithDebugDraw();

    void _enter_tree() override;
    void _process(double delta) override;
    void _draw() override;

    void _exit_tree() override;

    // emits the world's lines, gathers every list into pixels and clears
    // the per frame lists. _process does this when visible, the editor
    // plugin calls it itself. returns the line count
    int collect();
    godot::PackedVector2Array get_points() const;
    godot::PackedColorArray get_colors() const;

    // {"visible": bool, "names": {LABEL: bool}, "colors": {LABEL: Color},
    //  "layers": {LABEL: bool}, "tints": {LABEL: Color}}, every key optional
    void apply_settings(const godot::Dictionary& settings);
    godot::Dictionary get_settings() const;

    bool debugger_message(const godot::String& message, const godot::Array& data);

    int get_name_count() const;
    godot::String get_name_label(int name) const;

    void set_name_enabled(int name, bool enabled);
    bool is_name_enabled(int name) const;
    void set_all_names_enabled(bool enabled);

    void set_name_color(int name, godot::Color color);
    godot::Color get_name_color(int name) const;

    int get_layer_count() const;

    void set_layer_enabled(int layer, bool enabled);
    bool is_layer_enabled(int layer) const;

    void set_layer_tint(int layer, godot::Color tint);
    godot::Color get_layer_tint(int layer) const;

    void add_line(godot::Vector2 a, godot::Vector2 b, int name, int layer);
    void add_ray(godot::Vector2 origin, godot::Vector2 ray, int name, int layer);
    void add_circle(godot::Vector2 origin, float radius, int name, int layer);
    void add_capsule(godot::Vector2 a, godot::Vector2 b, float radius, int name, int layer);
    void add_rect(godot::Rect2 rect, int name, int layer);

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
    void gather(float pixels_per_unit, DebugRendererLineList& list);

    // copies m_map into the engine's global map
    void apply();

    static int name_index(const godot::String& label);
    static int layer_index(const godot::String& label);

private:
    DebugRendererColorMap m_map;
    float m_line_width = -1.f;
    godot::PackedVector2Array m_points;
    godot::PackedColorArray m_colors;
};
