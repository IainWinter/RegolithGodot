#pragma once

#include <godot_cpp/templates/local_vector.hpp>

#include <cstdint>

// Fill helper. godot::LocalVector::resize doesn't take a fill value, so this
// is the canonical replacement for std::vector's `assign(count, value)` and
// `resize(count, value)` patterns.
template <typename T, typename Count, typename V>
void vector_fill(godot::LocalVector<T>& vec, Count count, const V& value) {
    vec.resize(static_cast<uint32_t>(count));
    for (uint32_t i = 0; i < static_cast<uint32_t>(count); i++) {
        vec[i] = value;
    }
}

// Range assign, replacement for std::vector::assign(iter, iter).
template <typename T>
void vector_assign_range(godot::LocalVector<T>& vec, const T* first, const T* last) {
    vec.clear();
    for (const T* it = first; it != last; ++it) {
        vec.push_back(*it);
    }
}
