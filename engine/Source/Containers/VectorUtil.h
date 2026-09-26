#pragma once

#include <godot_cpp/templates/local_vector.hpp>

#include <cstdint>

// Fill helper, the replacement for std::vector's `assign(count, value)`:
// every slot ends up holding value. For `resize(count, value)`, which keeps
// what is already there and only fills the new tail, use vector_grow below.
// The rope solver lost its velocities every tick when this was used for
// that (Sep 2026), so pick by whether the old contents matter.
template <typename T, typename Count, typename V>
void vector_fill(godot::LocalVector<T>& vec, Count count, const V& value) {
    vec.resize(static_cast<uint32_t>(count));
    for (uint32_t i = 0; i < static_cast<uint32_t>(count); i++) {
        vec[i] = value;
    }
}

// Resize keeping the existing entries, new slots take value. This is
// std::vector's `resize(count, value)`.
template <typename T, typename Count, typename V>
void vector_grow(godot::LocalVector<T>& vec, Count count, const V& value) {
    uint32_t old_size = vec.size();
    vec.resize(static_cast<uint32_t>(count));
    for (uint32_t i = old_size; i < static_cast<uint32_t>(count); i++) {
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
