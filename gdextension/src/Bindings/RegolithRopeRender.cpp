#include "RegolithRopeRender.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void RegolithRopeRender::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_instance_count"), &RegolithRopeRender::get_instance_count);
}
