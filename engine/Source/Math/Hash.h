#pragma once

#include "Math/Vector.h"

#include <bit>
#include <cstdint>
#include <godot_cpp/templates/pair.hpp>

namespace std {
    template <>
    struct hash<godot::Vector2i> {
        size_t operator()(const godot::Vector2i& x) const {
            uint64_t key = (uint64_t(uint32_t(x.x)) << 32) | uint64_t(uint32_t(x.y));
            return std::hash<uint64_t>()(key);
        }
    };

    template <>
    struct hash<godot::Vector2> {
        size_t operator()(const godot::Vector2& x) const {
            uint64_t key = (uint64_t(std::bit_cast<uint32_t>(x.x)) << 32) | uint64_t(std::bit_cast<uint32_t>(x.y));
            return std::hash<uint64_t>()(key);
        }
    };
}
