#pragma once

#include <string_view>
#include <cstddef>

class OutputSerializer;
class InputSerializer;
class ComponentInspectorVisitor;

template<typename T>
void write(OutputSerializer& s, std::string_view name, const T& v);

template<typename T>
void read(InputSerializer& s, std::string_view name, T& v);

#define write_field(v) write(s, #v, v)
#define read_field(v) read(s, #v, v)

#define reflect_friend(T) \
    friend void type_serialize_write(OutputSerializer& s, const T& v); \
    friend void type_serialize_read(InputSerializer& s, T& v); \
    friend void type_inspect(ComponentInspectorVisitor& vis, T& v);

void begin_object(OutputSerializer& s, std::string_view name);
void end_object(OutputSerializer& s);
void begin_container(OutputSerializer& s, std::string_view name);
void end_container(OutputSerializer& s);
void size(OutputSerializer& s, std::string_view name, size_t size);

void begin_object(InputSerializer& s, std::string_view name);
void end_object(InputSerializer& s);
void begin_container(InputSerializer& s, std::string_view name);
void end_container(InputSerializer& s);
void size(InputSerializer& s, std::string_view name, size_t& size);
