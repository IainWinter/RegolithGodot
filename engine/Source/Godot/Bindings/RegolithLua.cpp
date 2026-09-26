#include "RegolithLua.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void RegolithLua::_bind_methods() {
    ClassDB::bind_method(D_METHOD("run", "source", "chunk_name"), &RegolithLua::run, DEFVAL("chunk"));
    ClassDB::bind_method(D_METHOD("load_class", "name", "source"), &RegolithLua::load_class);
    ClassDB::bind_method(D_METHOD("has_class", "name"), &RegolithLua::has_class);

    ClassDB::bind_method(D_METHOD("create", "class_name", "owner"), &RegolithLua::create);
    ClassDB::bind_method(D_METHOD("destroy", "id"), &RegolithLua::destroy);
    ClassDB::bind_method(D_METHOD("has_instance", "id"), &RegolithLua::has_instance);
    ClassDB::bind_method(D_METHOD("has_method", "id", "method"), &RegolithLua::has_method);
    ClassDB::bind_method(D_METHOD("call", "id", "method", "args"), &RegolithLua::call, DEFVAL(Array()));
    ClassDB::bind_method(D_METHOD("call_global", "function", "args"), &RegolithLua::call_global, DEFVAL(Array()));

    ClassDB::bind_method(D_METHOD("set_global", "name", "value"), &RegolithLua::set_global);
    ClassDB::bind_method(D_METHOD("get_global", "name"), &RegolithLua::get_global);

    ClassDB::bind_method(D_METHOD("set_instruction_limit", "limit"), &RegolithLua::set_instruction_limit);
    ClassDB::bind_method(D_METHOD("get_instruction_limit"), &RegolithLua::get_instruction_limit);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "instruction_limit"), "set_instruction_limit", "get_instruction_limit");
    ClassDB::bind_method(D_METHOD("set_print_errors", "print"), &RegolithLua::set_print_errors);
    ClassDB::bind_method(D_METHOD("get_print_errors"), &RegolithLua::get_print_errors);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "print_errors"), "set_print_errors", "get_print_errors");

    ClassDB::bind_method(D_METHOD("get_memory_used"), &RegolithLua::get_memory_used);
    ClassDB::bind_method(D_METHOD("get_instance_count"), &RegolithLua::get_instance_count);

    ADD_SIGNAL(MethodInfo("script_error", PropertyInfo(Variant::STRING, "where"), PropertyInfo(Variant::STRING, "message")));
}
