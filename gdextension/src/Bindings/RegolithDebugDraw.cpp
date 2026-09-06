#include "RegolithDebugDraw.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void RegolithDebugDraw::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_name_count"), &RegolithDebugDraw::get_name_count);
    ClassDB::bind_method(D_METHOD("get_name_label", "name"), &RegolithDebugDraw::get_name_label);
    ClassDB::bind_method(D_METHOD("set_name_enabled", "name", "enabled"), &RegolithDebugDraw::set_name_enabled);
    ClassDB::bind_method(D_METHOD("is_name_enabled", "name"), &RegolithDebugDraw::is_name_enabled);
    ClassDB::bind_method(D_METHOD("set_all_names_enabled", "enabled"), &RegolithDebugDraw::set_all_names_enabled);
    ClassDB::bind_method(D_METHOD("set_name_color", "name", "color"), &RegolithDebugDraw::set_name_color);
    ClassDB::bind_method(D_METHOD("get_name_color", "name"), &RegolithDebugDraw::get_name_color);

    ClassDB::bind_method(D_METHOD("get_layer_count"), &RegolithDebugDraw::get_layer_count);
    ClassDB::bind_method(D_METHOD("set_layer_enabled", "layer", "enabled"), &RegolithDebugDraw::set_layer_enabled);
    ClassDB::bind_method(D_METHOD("is_layer_enabled", "layer"), &RegolithDebugDraw::is_layer_enabled);
    ClassDB::bind_method(D_METHOD("set_layer_tint", "layer", "tint"), &RegolithDebugDraw::set_layer_tint);
    ClassDB::bind_method(D_METHOD("get_layer_tint", "layer"), &RegolithDebugDraw::get_layer_tint);

    ClassDB::bind_method(D_METHOD("add_line", "a", "b", "name", "layer"), &RegolithDebugDraw::add_line, DEFVAL(0), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("add_ray", "origin", "ray", "name", "layer"), &RegolithDebugDraw::add_ray, DEFVAL(0), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("add_circle", "origin", "radius", "name", "layer"), &RegolithDebugDraw::add_circle, DEFVAL(0), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("add_capsule", "a", "b", "radius", "name", "layer"), &RegolithDebugDraw::add_capsule, DEFVAL(0), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("add_rect", "rect", "name", "layer"), &RegolithDebugDraw::add_rect, DEFVAL(0), DEFVAL(0));

    ClassDB::bind_method(D_METHOD("set_line_width", "width"), &RegolithDebugDraw::set_line_width);
    ClassDB::bind_method(D_METHOD("get_line_width"), &RegolithDebugDraw::get_line_width);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "line_width", PROPERTY_HINT_RANGE, "-1,8,0.5"), "set_line_width", "get_line_width");

    ClassDB::bind_method(D_METHOD("get_line_count"), &RegolithDebugDraw::get_line_count);

    // RegolithDebugDraw.PHYSICS_CONTACT_POINT and friends
    int count = 0;
    const NameEntry* entries = names(&count);

    for (int i = 0; i < count; i++) {
        ClassDB::bind_integer_constant(get_class_static(), "DebugName", entries[i].label, entries[i].value);
    }

    ClassDB::bind_integer_constant(get_class_static(), "DebugLayer", "LAYER_DEFAULT", DebugLayer_Default);
    ClassDB::bind_integer_constant(get_class_static(), "DebugLayer", "LAYER_A", DebugLayer_A);
    ClassDB::bind_integer_constant(get_class_static(), "DebugLayer", "LAYER_B", DebugLayer_B);
}
