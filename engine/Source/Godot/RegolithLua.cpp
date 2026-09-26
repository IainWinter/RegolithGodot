#include "RegolithLua.h"
#include "LuaVariant.h"

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdlib>

using namespace godot;

namespace {

constexpr const char* k_classes_key = "regolith.classes";
constexpr const char* k_instances_key = "regolith.instances";
constexpr const char* k_traceback_key = "regolith.traceback";

void open_lib(lua_State* L, const char* name, lua_CFunction open) {
    luaL_requiref(L, name, open, 1);
    lua_pop(L, 1);
}

// __instance(id): the instance table for an id, so scripts can read each
// other's state through a node's id field
int instance_lookup(lua_State* L) {
    lua_Integer id = luaL_optinteger(L, 1, 0);
    lua_getfield(L, LUA_REGISTRYINDEX, k_instances_key);
    lua_rawgeti(L, -1, id);
    lua_remove(L, -2);
    return 1;
}

// the message of a failed load or pcall, which left its error object on top
String error_at_top(lua_State* L) {
    return lua_type(L, -1) == LUA_TSTRING ? String::utf8(lua_tostring(L, -1)) : String("error object is not a string");
}

}

RegolithLua::RegolithLua() {
    m_state = lua_newstate(alloc, this);
    open_sandbox();
}

RegolithLua::~RegolithLua() {
    if (m_state) {
        lua_close(m_state);
        m_state = nullptr;
    }
}

void* RegolithLua::alloc(void* ud, void* ptr, size_t old_size, size_t new_size) {
    RegolithLua* self = static_cast<RegolithLua*>(ud);

    if (new_size == 0) {
        if (ptr) {
            self->m_memory_used -= old_size;
        }

        std::free(ptr);
        return nullptr;
    }

    void* out = std::realloc(ptr, new_size);

    if (out) {
        self->m_memory_used += new_size;

        if (ptr) {
            self->m_memory_used -= old_size;
        }
    }

    return out;
}

void RegolithLua::count_hook(lua_State* L, lua_Debug*) {
    lua_sethook(L, nullptr, 0, 0);
    luaL_error(L, "instruction limit reached, the call was aborted");
}

void RegolithLua::open_sandbox() {
    lua_State* L = m_state;

    open_lib(L, LUA_GNAME, luaopen_base);
    open_lib(L, LUA_TABLIBNAME, luaopen_table);
    open_lib(L, LUA_STRLIBNAME, luaopen_string);
    open_lib(L, LUA_MATHLIBNAME, luaopen_math);
    open_lib(L, LUA_UTF8LIBNAME, luaopen_utf8);

    // keep traceback for error reports, drop the rest of debug
    luaL_requiref(L, LUA_DBLIBNAME, luaopen_debug, 0);
    lua_getfield(L, -1, "traceback");
    lua_setfield(L, LUA_REGISTRYINDEX, k_traceback_key);
    lua_pop(L, 1);

    const char* dropped[] = { "dofile", "loadfile", "load", "require" };

    for (const char* name : dropped) {
        lua_pushnil(L);
        lua_setglobal(L, name);
    }

    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, k_classes_key);
    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, k_instances_key);

    lua_variant::open_types(L);
    lua_register(L, "__instance", instance_lookup);
}

void RegolithLua::arm_hook() {
    lua_sethook(m_state, count_hook, LUA_MASKCOUNT, m_instruction_limit);
}

void RegolithLua::report(const String& where, const String& message) {
    if (m_print_errors) {
        UtilityFunctions::push_error("RegolithLua " + where + ": " + message);
    }

    emit_signal("script_error", where, message);
}

// stack: [..., traceback, function, args...]. pops everything from the
// traceback up, leaves nothing, returns the single result
Variant RegolithLua::pcall_top(int arg_count, const String& where) {
    lua_State* L = m_state;
    int base = lua_gettop(L) - arg_count - 1;

    arm_hook();
    int status = lua_pcall(L, arg_count, 1, base);
    lua_sethook(L, nullptr, 0, 0);

    Variant out;

    if (status != LUA_OK) {
        report(where, error_at_top(L));
    } else {
        out = lua_variant::to_variant(L, -1);
    }

    lua_settop(L, base - 1);
    return out;
}

// loads source as a text chunk called name and runs it under the traceback
// handler. "" on success with nresults left on top of the stack, else the
// stack is back where it was and the reported message comes back
String RegolithLua::load_and_call(const String& source, const String& name, int nresults) {
    lua_State* L = m_state;
    int base = lua_gettop(L);

    lua_getfield(L, LUA_REGISTRYINDEX, k_traceback_key);

    CharString text = source.utf8();
    CharString chunk = (String("=") + name).utf8();

    int status = luaL_loadbufferx(L, text.get_data(), text.length(), chunk.get_data(), "t");

    if (status == LUA_OK) {
        arm_hook();
        status = lua_pcall(L, 0, nresults, base + 1);
        lua_sethook(L, nullptr, 0, 0);
    }

    if (status != LUA_OK) {
        String message = error_at_top(L);
        lua_settop(L, base);
        report(name, message);
        return message;
    }

    lua_remove(L, base + 1);
    return String();
}

String RegolithLua::run(const String& source, const String& chunk_name) {
    return load_and_call(source, chunk_name, 0);
}

String RegolithLua::load_class(const String& name, const String& source) {
    lua_State* L = m_state;
    int base = lua_gettop(L);

    String error = load_and_call(source, name, 1);

    if (!error.is_empty()) {
        return error;
    }

    if (lua_type(L, -1) != LUA_TTABLE) {
        lua_settop(L, base);
        String message = "script must return a class table";
        report(name, message);
        return message;
    }

    int fresh = lua_gettop(L);
    CharString name_text = name.utf8();

    // a class indexes itself and knows its name
    lua_pushstring(L, name_text.get_data());
    lua_setfield(L, fresh, "__name");

    if (!lua_getmetatable(L, fresh)) {
        lua_getglobal(L, "Ai");

        if (lua_type(L, -1) == LUA_TTABLE) {
            lua_createtable(L, 0, 1);
            lua_pushvalue(L, -2);
            lua_setfield(L, -2, "__index");
            lua_setmetatable(L, fresh);
        }

        lua_pop(L, 1);
    } else {
        lua_pop(L, 1);
    }

    lua_getfield(L, LUA_REGISTRYINDEX, k_classes_key);
    int classes = lua_gettop(L);
    lua_getfield(L, classes, name_text.get_data());

    if (lua_type(L, -1) == LUA_TTABLE) {
        // reload: move the new fields into the table live instances use
        int old = lua_gettop(L);

        lua_pushnil(L);

        while (lua_next(L, old) != 0) {
            lua_pop(L, 1);
            lua_pushvalue(L, -1);
            lua_pushnil(L);
            lua_rawset(L, old);
        }

        lua_pushnil(L);

        while (lua_next(L, fresh) != 0) {
            lua_pushvalue(L, -2);
            lua_pushvalue(L, -2);
            lua_rawset(L, old);
            lua_pop(L, 1);
        }

        if (lua_getmetatable(L, fresh)) {
            lua_setmetatable(L, old);
        }

        lua_pushvalue(L, old);
        lua_setfield(L, old, "__index");
    } else {
        lua_pop(L, 1);
        lua_pushvalue(L, fresh);
        lua_setfield(L, fresh, "__index");
        lua_pushvalue(L, fresh);
        lua_setfield(L, classes, name_text.get_data());
    }

    lua_settop(L, base);
    return String();
}

bool RegolithLua::has_class(const String& name) const {
    lua_State* L = m_state;
    int base = lua_gettop(L);

    lua_getfield(L, LUA_REGISTRYINDEX, k_classes_key);
    lua_getfield(L, -1, name.utf8().get_data());
    bool found = lua_type(L, -1) == LUA_TTABLE;

    lua_settop(L, base);
    return found;
}

int RegolithLua::create(const String& class_name, Object* owner) {
    lua_State* L = m_state;
    int base = lua_gettop(L);

    lua_getfield(L, LUA_REGISTRYINDEX, k_classes_key);
    lua_getfield(L, -1, class_name.utf8().get_data());

    if (lua_type(L, -1) != LUA_TTABLE) {
        lua_settop(L, base);
        report(class_name, "no such class, load_class it first");
        return 0;
    }

    int klass = lua_gettop(L);
    int id = m_next_id++;

    lua_newtable(L);
    int instance = lua_gettop(L);

    lua_pushvalue(L, klass);
    lua_setmetatable(L, instance);

    lua_variant::push_object(L, owner);
    lua_setfield(L, instance, "node");
    lua_pushinteger(L, id);
    lua_setfield(L, instance, "id");

    lua_getfield(L, LUA_REGISTRYINDEX, k_instances_key);
    lua_pushvalue(L, instance);
    lua_rawseti(L, -2, id);
    lua_pop(L, 1);

    m_instance_count++;

    lua_getfield(L, instance, "init");

    if (lua_type(L, -1) == LUA_TFUNCTION) {
        lua_getfield(L, LUA_REGISTRYINDEX, k_traceback_key);
        lua_insert(L, -2);
        lua_pushvalue(L, instance);
        pcall_top(1, class_name + String(".init"));
    } else {
        lua_pop(L, 1);
    }

    lua_settop(L, base);
    return id;
}

void RegolithLua::destroy(int id) {
    lua_State* L = m_state;
    int base = lua_gettop(L);

    lua_getfield(L, LUA_REGISTRYINDEX, k_instances_key);
    lua_rawgeti(L, -1, id);
    bool found = lua_type(L, -1) == LUA_TTABLE;
    lua_pop(L, 1);

    if (found) {
        lua_pushnil(L);
        lua_rawseti(L, -2, id);
        m_instance_count--;
    }

    lua_settop(L, base);
}

bool RegolithLua::push_instance(int id) const {
    lua_State* L = m_state;

    lua_getfield(L, LUA_REGISTRYINDEX, k_instances_key);
    lua_rawgeti(L, -1, id);
    lua_remove(L, -2);

    if (lua_type(L, -1) != LUA_TTABLE) {
        lua_pop(L, 1);
        return false;
    }

    return true;
}

bool RegolithLua::has_instance(int id) const {
    lua_State* L = m_state;
    int base = lua_gettop(L);
    bool found = push_instance(id);
    lua_settop(L, base);
    return found;
}

bool RegolithLua::has_method(int id, const String& method) const {
    lua_State* L = m_state;
    int base = lua_gettop(L);

    if (!push_instance(id)) {
        return false;
    }

    lua_getfield(L, -1, method.utf8().get_data());
    bool found = lua_type(L, -1) == LUA_TFUNCTION;

    lua_settop(L, base);
    return found;
}

Variant RegolithLua::call(int id, const String& method, const Array& args) {
    lua_State* L = m_state;
    int base = lua_gettop(L);

    if (!push_instance(id)) {
        return Variant();
    }

    int instance = lua_gettop(L);
    lua_getfield(L, instance, method.utf8().get_data());

    if (lua_type(L, -1) != LUA_TFUNCTION) {
        lua_settop(L, base);
        return Variant();
    }

    int arg_count = static_cast<int>(args.size());

    if (!lua_checkstack(L, arg_count + 4)) {
        lua_settop(L, base);
        report(method, "lua stack overflow");
        return Variant();
    }

    lua_getfield(L, LUA_REGISTRYINDEX, k_traceback_key);
    lua_insert(L, -2);
    lua_pushvalue(L, instance);

    for (int i = 0; i < arg_count; i++) {
        lua_variant::push_variant(L, args[i]);
    }

    Variant out = pcall_top(arg_count + 1, method);
    lua_settop(L, base);
    return out;
}

Variant RegolithLua::call_global(const String& function, const Array& args) {
    lua_State* L = m_state;
    int base = lua_gettop(L);

    lua_getfield(L, LUA_REGISTRYINDEX, k_traceback_key);
    lua_getglobal(L, function.utf8().get_data());

    if (lua_type(L, -1) != LUA_TFUNCTION) {
        lua_settop(L, base);
        report(function, "no such global function");
        return Variant();
    }

    int arg_count = static_cast<int>(args.size());

    if (!lua_checkstack(L, arg_count + 4)) {
        lua_settop(L, base);
        report(function, "lua stack overflow");
        return Variant();
    }

    for (int i = 0; i < arg_count; i++) {
        lua_variant::push_variant(L, args[i]);
    }

    Variant out = pcall_top(arg_count, function);
    lua_settop(L, base);
    return out;
}

void RegolithLua::set_global(const String& name, const Variant& value) {
    lua_variant::push_variant(m_state, value);
    lua_setglobal(m_state, name.utf8().get_data());
}

Variant RegolithLua::get_global(const String& name) const {
    lua_State* L = m_state;
    int base = lua_gettop(L);

    lua_getglobal(L, name.utf8().get_data());
    Variant out = lua_variant::to_variant(L, -1);

    lua_settop(L, base);
    return out;
}

void RegolithLua::set_instruction_limit(int limit) {
    m_instruction_limit = limit > 0 ? limit : 1;
}

int RegolithLua::get_instruction_limit() const {
    return m_instruction_limit;
}

void RegolithLua::set_print_errors(bool print) {
    m_print_errors = print;
}

bool RegolithLua::get_print_errors() const {
    return m_print_errors;
}

int RegolithLua::get_memory_used() const {
    return static_cast<int>(m_memory_used);
}

int RegolithLua::get_instance_count() const {
    return m_instance_count;
}
