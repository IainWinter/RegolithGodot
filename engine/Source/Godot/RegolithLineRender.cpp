#include "RegolithLineRender.h"

using namespace godot;

RegolithLineRender::RegolithLineRender() {
    set_physics_interpolation_mode(Node::PHYSICS_INTERPOLATION_MODE_OFF);
}

void RegolithLineRender::_draw() {
    m_render.draw(get_canvas_item());
}

void RegolithLineRender::clear() {
    m_render.clear();
}

void RegolithLineRender::add_line(Vector2 a, Vector2 b, float width, Color color) {
    PackedVector2Array points;
    points.push_back(a);
    points.push_back(b);

    PackedFloat32Array widths;
    widths.push_back(width);

    PackedColorArray colors;
    colors.push_back(color);

    m_render.add_polyline(points, widths, colors, m_style);
}

void RegolithLineRender::add_polyline(const PackedVector2Array& points, const PackedFloat32Array& widths, const PackedColorArray& colors) {
    m_render.add_polyline(points, widths, colors, m_style);
}

void RegolithLineRender::commit() {
    queue_redraw();
}

int RegolithLineRender::get_line_count() const {
    return m_render.line_count();
}

int RegolithLineRender::get_vertex_count() const {
    return m_render.vertex_count();
}

Rect2 RegolithLineRender::get_bounds() const {
    return m_render.bounds();
}

void RegolithLineRender::set_glow_width(float width) {
    m_style.glow_width = width;
}

float RegolithLineRender::get_glow_width() const {
    return m_style.glow_width;
}

void RegolithLineRender::set_glow_strength(float strength) {
    m_style.glow_strength = strength;
}

float RegolithLineRender::get_glow_strength() const {
    return m_style.glow_strength;
}

void RegolithLineRender::set_feather(float feather) {
    m_style.feather = feather;
}

float RegolithLineRender::get_feather() const {
    return m_style.feather;
}

void RegolithLineRender::set_cap_resolution(int resolution) {
    m_style.cap_resolution = resolution;
}

int RegolithLineRender::get_cap_resolution() const {
    return m_style.cap_resolution;
}
