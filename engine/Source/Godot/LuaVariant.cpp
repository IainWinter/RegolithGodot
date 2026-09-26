#include "LuaVariant.h"

extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstring>

using namespace godot;

namespace {

constexpr const char* k_vec2_key = "regolith.vec2";
constexpr const char* k_object_key = "regolith.object";
constexpr int k_max_depth = 32;

struct ObjectBox {
    uint64_t id;
};

void push_variant_depth(lua_State* L, const Variant& value, int depth);
Variant to_variant_depth(lua_State* L, int index, int depth);

void push_vec2(lua_State* L, double x, double y) {
    lua_createtable(L, 0, 2);
    lua_pushnumber(L, x);
    lua_setfield(L, -2, "x");
    lua_pushnumber(L, y);
    lua_setfield(L, -2, "y");
    luaL_getmetatable(L, k_vec2_key);
    lua_setmetatable(L, -2);
}

bool has_vec2_metatable(lua_State* L, int index) {
    if (!lua_getmetatable(L, index)) {
        return false;
    }

    luaL_getmetatable(L, k_vec2_key);
    bool same = lua_rawequal(L, -1, -2) != 0;
    lua_pop(L, 2);
    return same;
}

// vec2(x, y), vec2(other), vec2()
int vec2_new(lua_State* L) {
    double x = 0.0;
    double y = 0.0;

    if (lua_type(L, 1) == LUA_TTABLE) {
        lua_getfield(L, 1, "x");
        lua_getfield(L, 1, "y");
        x = lua_tonumber(L, -2);
        y = lua_tonumber(L, -1);
        lua_pop(L, 2);
    } else {
        x = luaL_optnumber(L, 1, 0.0);
        y = luaL_optnumber(L, 2, 0.0);
    }

    push_vec2(L, x, y);
    return 1;
}

// object userdata

ObjectBox* check_box(lua_State* L, int index) {
    if (lua_type(L, index) != LUA_TUSERDATA) {
        return nullptr;
    }

    if (!lua_getmetatable(L, index)) {
        return nullptr;
    }

    luaL_getmetatable(L, k_object_key);
    bool same = lua_rawequal(L, -1, -2) != 0;
    lua_pop(L, 2);

    if (!same) {
        return nullptr;
    }

    return static_cast<ObjectBox*>(lua_touserdata(L, index));
}

Object* box_object(const ObjectBox* box) {
    return box ? ObjectDB::get_instance(box->id) : nullptr;
}

// the method closure: upvalue 1 is the method name, arg 1 must be the
// object it was read from (colon call)
int object_method(lua_State* L) {
    ObjectBox* box = check_box(L, 1);

    if (!box) {
        return luaL_error(L, "call object methods with ':' (obj:%s())", lua_tostring(L, lua_upvalueindex(1)));
    }

    Object* object = box_object(box);

    if (!object) {
        lua_pushnil(L);
        return 1;
    }

    int arg_count = lua_gettop(L) - 1;

    StringName method(lua_tostring(L, lua_upvalueindex(1)));
    Array args;
    args.resize(arg_count);

    for (int i = 0; i < arg_count; i++) {
        args[i] = to_variant_depth(L, i + 2, 0);
    }

    Variant out = object->callv(method, args);
    lua_settop(L, 0);
    push_variant_depth(L, out, 0);
    return 1;
}

int object_index(lua_State* L) {
    ObjectBox* box = check_box(L, 1);

    if (!box || lua_type(L, 2) != LUA_TSTRING) {
        lua_pushnil(L);
        return 1;
    }

    const char* key = lua_tostring(L, 2);

    if (std::strcmp(key, "valid") == 0) {
        lua_pushboolean(L, box_object(box) != nullptr);
        return 1;
    }

    if (std::strcmp(key, "instance_id") == 0) {
        lua_pushinteger(L, static_cast<lua_Integer>(box->id));
        return 1;
    }

    Object* object = box_object(box);

    if (!object) {
        lua_pushnil(L);
        return 1;
    }

    StringName name(key);

    if (object->has_method(name)) {
        lua_pushvalue(L, 2);
        lua_pushcclosure(L, object_method, 1);
        return 1;
    }

    push_variant_depth(L, object->get(name), 0);
    return 1;
}

int object_newindex(lua_State* L) {
    ObjectBox* box = check_box(L, 1);
    Object* object = box_object(box);

    if (!object || lua_type(L, 2) != LUA_TSTRING) {
        return 0;
    }

    {
        StringName name(lua_tostring(L, 2));
        Variant value = to_variant_depth(L, 3, 0);
        object->set(name, value);
    }

    return 0;
}

int object_eq(lua_State* L) {
    ObjectBox* a = check_box(L, 1);
    ObjectBox* b = check_box(L, 2);
    lua_pushboolean(L, a && b && a->id == b->id);
    return 1;
}

int object_tostring(lua_State* L) {
    ObjectBox* box = check_box(L, 1);
    Object* object = box_object(box);

    if (!object) {
        lua_pushstring(L, "<freed object>");
        return 1;
    }

    {
        String text = "<" + object->get_class() + "#" + String::num_int64(static_cast<int64_t>(box->id)) + ">";
        lua_pushstring(L, text.utf8().get_data());
    }

    return 1;
}

// tables

bool is_sequence(lua_State* L, int index) {
    lua_Integer n = static_cast<lua_Integer>(lua_rawlen(L, index));
    lua_Integer count = 0;

    lua_pushnil(L);

    while (lua_next(L, index) != 0) {
        lua_pop(L, 1);
        count++;

        if (lua_type(L, -1) != LUA_TNUMBER || !lua_isinteger(L, -1)) {
            lua_pop(L, 1);
            return false;
        }

        lua_Integer key = lua_tointeger(L, -1);

        if (key < 1 || key > n) {
            lua_pop(L, 1);
            return false;
        }
    }

    return count == n && n > 0;
}

Variant table_to_variant(lua_State* L, int index, int depth) {
    if (has_vec2_metatable(L, index)) {
        lua_getfield(L, index, "x");
        lua_getfield(L, index, "y");
        Vector2 v(static_cast<float>(lua_tonumber(L, -2)), static_cast<float>(lua_tonumber(L, -1)));
        lua_pop(L, 2);
        return v;
    }

    if (is_sequence(L, index)) {
        Array out;
        lua_Integer n = static_cast<lua_Integer>(lua_rawlen(L, index));
        out.resize(static_cast<int64_t>(n));

        for (lua_Integer i = 1; i <= n; i++) {
            lua_rawgeti(L, index, i);
            out[static_cast<int64_t>(i - 1)] = to_variant_depth(L, lua_gettop(L), depth + 1);
            lua_pop(L, 1);
        }

        return out;
    }

    Dictionary out;
    lua_pushnil(L);

    while (lua_next(L, index) != 0) {
        int value_index = lua_gettop(L);
        int key_index = value_index - 1;
        Variant key;

        switch (lua_type(L, key_index)) {
            case LUA_TSTRING:
                key = String::utf8(lua_tostring(L, key_index));
                break;
            case LUA_TNUMBER:
                key = lua_isinteger(L, key_index) ? Variant(static_cast<int64_t>(lua_tointeger(L, key_index))) : Variant(lua_tonumber(L, key_index));
                break;
            case LUA_TBOOLEAN:
                key = static_cast<bool>(lua_toboolean(L, key_index));
                break;
            default:
                lua_pop(L, 1);
                continue;
        }

        out[key] = to_variant_depth(L, value_index, depth + 1);
        lua_pop(L, 1);
    }

    return out;
}

Variant to_variant_depth(lua_State* L, int index, int depth) {
    index = lua_absindex(L, index);

    if (depth > k_max_depth) {
        return Variant();
    }

    switch (lua_type(L, index)) {
        case LUA_TNIL:
        case LUA_TNONE:
            return Variant();
        case LUA_TBOOLEAN:
            return static_cast<bool>(lua_toboolean(L, index));
        case LUA_TNUMBER:
            if (lua_isinteger(L, index)) {
                return static_cast<int64_t>(lua_tointeger(L, index));
            }
            return lua_tonumber(L, index);
        case LUA_TSTRING:
            return String::utf8(lua_tostring(L, index));
        case LUA_TTABLE:
            return table_to_variant(L, index, depth);
        case LUA_TUSERDATA: {
            Object* object = box_object(check_box(L, index));
            return object ? Variant(object) : Variant();
        }
        default:
            return Variant();
    }
}

template <typename T>
void push_sequence(lua_State* L, const T& values, int depth) {
    int64_t n = values.size();
    lua_createtable(L, static_cast<int>(n), 0);

    for (int64_t i = 0; i < n; i++) {
        push_variant_depth(L, values[i], depth + 1);
        lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
    }
}

void push_variant_depth(lua_State* L, const Variant& value, int depth) {
    if (depth > k_max_depth) {
        lua_pushnil(L);
        return;
    }

    switch (value.get_type()) {
        case Variant::NIL:
            lua_pushnil(L);
            break;
        case Variant::BOOL:
            lua_pushboolean(L, static_cast<bool>(value));
            break;
        case Variant::INT:
            lua_pushinteger(L, static_cast<lua_Integer>(static_cast<int64_t>(value)));
            break;
        case Variant::FLOAT:
            lua_pushnumber(L, static_cast<double>(value));
            break;
        case Variant::STRING:
        case Variant::STRING_NAME:
        case Variant::NODE_PATH: {
            String text = value;
            lua_pushstring(L, text.utf8().get_data());
            break;
        }
        case Variant::VECTOR2: {
            Vector2 v = value;
            push_vec2(L, v.x, v.y);
            break;
        }
        case Variant::VECTOR2I: {
            Vector2i v = value;
            push_vec2(L, v.x, v.y);
            break;
        }
        case Variant::COLOR: {
            Color c = value;
            lua_createtable(L, 0, 4);
            lua_pushnumber(L, c.r);
            lua_setfield(L, -2, "r");
            lua_pushnumber(L, c.g);
            lua_setfield(L, -2, "g");
            lua_pushnumber(L, c.b);
            lua_setfield(L, -2, "b");
            lua_pushnumber(L, c.a);
            lua_setfield(L, -2, "a");
            break;
        }
        case Variant::ARRAY:
            push_sequence(L, static_cast<Array>(value), depth);
            break;
        case Variant::PACKED_VECTOR2_ARRAY:
            push_sequence(L, static_cast<PackedVector2Array>(value), depth);
            break;
        case Variant::PACKED_INT32_ARRAY:
            push_sequence(L, static_cast<PackedInt32Array>(value), depth);
            break;
        case Variant::PACKED_INT64_ARRAY:
            push_sequence(L, static_cast<PackedInt64Array>(value), depth);
            break;
        case Variant::PACKED_FLOAT32_ARRAY:
            push_sequence(L, static_cast<PackedFloat32Array>(value), depth);
            break;
        case Variant::PACKED_FLOAT64_ARRAY:
            push_sequence(L, static_cast<PackedFloat64Array>(value), depth);
            break;
        case Variant::PACKED_STRING_ARRAY:
            push_sequence(L, static_cast<PackedStringArray>(value), depth);
            break;
        case Variant::DICTIONARY: {
            Dictionary dict = value;
            Array keys = dict.keys();
            lua_createtable(L, 0, static_cast<int>(keys.size()));

            for (int64_t i = 0; i < keys.size(); i++) {
                const Variant& key = keys[i];

                switch (key.get_type()) {
                    case Variant::STRING:
                    case Variant::STRING_NAME:
                    case Variant::INT:
                    case Variant::FLOAT:
                    case Variant::BOOL:
                        push_variant_depth(L, key, depth + 1);
                        break;
                    default: {
                        String text = key.stringify();
                        lua_pushstring(L, text.utf8().get_data());
                        break;
                    }
                }

                push_variant_depth(L, dict[key], depth + 1);
                lua_rawset(L, -3);
            }
            break;
        }
        case Variant::OBJECT:
            lua_variant::push_object(L, static_cast<Object*>(value));
            break;
        default:
            lua_pushnil(L);
            break;
    }
}

}

namespace lua_variant {

void open_types(lua_State* L) {
    luaL_newmetatable(L, k_vec2_key);
    lua_pop(L, 1);

    luaL_newmetatable(L, k_object_key);
    lua_pushcfunction(L, object_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, object_newindex);
    lua_setfield(L, -2, "__newindex");
    lua_pushcfunction(L, object_eq);
    lua_setfield(L, -2, "__eq");
    lua_pushcfunction(L, object_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pushstring(L, "object");
    lua_setfield(L, -2, "__name");
    lua_pop(L, 1);

    lua_pushcfunction(L, vec2_new);
    lua_setglobal(L, "vec2");
}

void push_variant(lua_State* L, const Variant& value) {
    push_variant_depth(L, value, 0);
}

Variant to_variant(lua_State* L, int index) {
    return to_variant_depth(L, index, 0);
}

void push_object(lua_State* L, Object* object) {
    if (!object) {
        lua_pushnil(L);
        return;
    }

    ObjectBox* box = static_cast<ObjectBox*>(lua_newuserdatauv(L, sizeof(ObjectBox), 0));
    box->id = object->get_instance_id();
    luaL_getmetatable(L, k_object_key);
    lua_setmetatable(L, -2);
}

}
