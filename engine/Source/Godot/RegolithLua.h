#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/variant.hpp>

struct lua_State;

// one sandboxed lua 5.4 state for game scripts. a script file returns a
// class table, instances are tables with that class as metatable, kept in
// the state by an integer id so gdscript never holds a lua value. godot
// objects cross into lua as userdata that forwards field reads to get(),
// writes to set() and method calls to callv(), so anything an owner node
// exposes is callable from the script with no per method binding.
//
// values cross as: nil, bool, int, float, string, Vector2/Vector2i as a
// table {x, y} with the vec2 metatable, Array as a sequence, Dictionary as
// a table, Object as userdata. tables come back as Vector2 when they carry
// the vec2 metatable, Array when their keys are 1..n, else Dictionary.
//
// only the base, table, string, math and utf8 libraries are open. a
// count hook aborts a call that runs past instruction_limit. lua errors
// never cross a c function of ours, every entry point is a pcall
class RegolithLua : public godot::RefCounted {
    GDCLASS(RegolithLua, godot::RefCounted)

public:
    RegolithLua();
    ~RegolithLua() override;

    // runs a chunk, "" on success else the error message
    godot::String run(const godot::String& source, const godot::String& chunk_name);

    // runs a chunk that returns a class table and stores it under name.
    // loading a name again copies the new fields into the old table so
    // live instances pick up the new methods
    godot::String load_class(const godot::String& name, const godot::String& source);
    bool has_class(const godot::String& name) const;

    // makes an instance of a class with owner as its node field, calls
    // init(self) when the class has one. 0 when the class is missing
    int create(const godot::String& class_name, godot::Object* owner);
    void destroy(int id);
    bool has_instance(int id) const;
    bool has_method(int id, const godot::String& method) const;

    // calls instance:method(args...), nil when the method is missing or
    // errored. errors go to script_error and the output
    godot::Variant call(int id, const godot::String& method, const godot::Array& args);
    godot::Variant call_global(const godot::String& function, const godot::Array& args);

    void set_global(const godot::String& name, const godot::Variant& value);
    godot::Variant get_global(const godot::String& name) const;

    void set_instruction_limit(int limit);
    int get_instruction_limit() const;

    // errors always go to script_error, print_errors also pushes them to
    // the output. off for tests that expect errors
    void set_print_errors(bool print);
    bool get_print_errors() const;

    int get_memory_used() const;
    int get_instance_count() const;

    lua_State* state() const { return m_state; }

protected:
    static void _bind_methods();

private:
    void open_sandbox();
    void arm_hook();
    bool push_instance(int id) const;
    godot::String load_and_call(const godot::String& source, const godot::String& name, int nresults);
    godot::Variant pcall_top(int arg_count, const godot::String& where);
    void report(const godot::String& where, const godot::String& message);

    static void* alloc(void* ud, void* ptr, size_t old_size, size_t new_size);
    static void count_hook(lua_State* L, struct lua_Debug* ar);

    lua_State* m_state = nullptr;
    size_t m_memory_used = 0;
    int m_instruction_limit = 2000000;
    bool m_print_errors = true;
    int m_next_id = 1;
    int m_instance_count = 0;
};
