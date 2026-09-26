#pragma once

#include "LineRender.h"

#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/core/binder_common.hpp>

// a canvas item that draws whatever polylines it was fed since the last
// clear() as the engine's custom line strokes, see LineRender. a script
// calls clear(), add_line / add_polyline in the item's own space, then
// commit() once per frame. the blend comes from the node's material, so an
// additive CanvasItemMaterial makes it the engine's additive line pass.
// glow_width / glow_strength / feather are in the item's units
class RegolithLineRender : public godot::Node2D {
    GDCLASS(RegolithLineRender, godot::Node2D)

public:
    RegolithLineRender();

    void _draw() override;

    void clear();
    void add_line(godot::Vector2 a, godot::Vector2 b, float width, godot::Color color);
    void add_polyline(const godot::PackedVector2Array& points, const godot::PackedFloat32Array& widths, const godot::PackedColorArray& colors);
    void commit();

    int get_line_count() const;
    int get_vertex_count() const;
    godot::Rect2 get_bounds() const;

    void set_glow_width(float width);
    float get_glow_width() const;

    void set_glow_strength(float strength);
    float get_glow_strength() const;

    void set_feather(float feather);
    float get_feather() const;

    void set_cap_resolution(int resolution);
    int get_cap_resolution() const;

protected:
    static void _bind_methods();

private:
    LineRender m_render;
    LineRender::Style m_style;
};
