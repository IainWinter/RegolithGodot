#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/variant.hpp>

struct lua_State;

// the value bridge between godot variants and a lua stack. see
// RegolithLua.h for the mapping. none of these raise a lua error, so they
// are safe to call from c functions that hold godot values on the stack
namespace lua_variant {

// registers the vec2 and object metatables in the registry and the vec2
// constructor as a global. call once per state before any push
void open_types(lua_State* L);

void push_variant(lua_State* L, const godot::Variant& value);
godot::Variant to_variant(lua_State* L, int index);

// nil when the object is null
void push_object(lua_State* L, godot::Object* object);

}
