#include "RegolithLineRender.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void RegolithLineRender::_bind_methods() {
    ClassDB::bind_method(D_METHOD("clear"), &RegolithLineRender::clear);
    ClassDB::bind_method(D_METHOD("add_line", "a", "b", "width", "color"), &RegolithLineRender::add_line);
    ClassDB::bind_method(D_METHOD("add_polyline", "points", "widths", "colors"), &RegolithLineRender::add_polyline);
    ClassDB::bind_method(D_METHOD("commit"), &RegolithLineRender::commit);

    ClassDB::bind_method(D_METHOD("get_line_count"), &RegolithLineRender::get_line_count);
    ClassDB::bind_method(D_METHOD("get_vertex_count"), &RegolithLineRender::get_vertex_count);
    ClassDB::bind_method(D_METHOD("get_bounds"), &RegolithLineRender::get_bounds);

    ClassDB::bind_method(D_METHOD("set_glow_width", "width"), &RegolithLineRender::set_glow_width);
    ClassDB::bind_method(D_METHOD("get_glow_width"), &RegolithLineRender::get_glow_width);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "glow_width", PROPERTY_HINT_RANGE, "0,64,0.1"), "set_glow_width", "get_glow_width");

    ClassDB::bind_method(D_METHOD("set_glow_strength", "strength"), &RegolithLineRender::set_glow_strength);
    ClassDB::bind_method(D_METHOD("get_glow_strength"), &RegolithLineRender::get_glow_strength);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "glow_strength", PROPERTY_HINT_RANGE, "0,4,0.01"), "set_glow_strength", "get_glow_strength");

    ClassDB::bind_method(D_METHOD("set_feather", "feather"), &RegolithLineRender::set_feather);
    ClassDB::bind_method(D_METHOD("get_feather"), &RegolithLineRender::get_feather);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "feather", PROPERTY_HINT_RANGE, "0,8,0.1"), "set_feather", "get_feather");

    ClassDB::bind_method(D_METHOD("set_cap_resolution", "resolution"), &RegolithLineRender::set_cap_resolution);
    ClassDB::bind_method(D_METHOD("get_cap_resolution"), &RegolithLineRender::get_cap_resolution);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "cap_resolution", PROPERTY_HINT_RANGE, "1,32,1"), "set_cap_resolution", "get_cap_resolution");
}
