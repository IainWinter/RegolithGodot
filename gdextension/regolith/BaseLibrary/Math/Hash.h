#pragma once

#include "glm/vec2.hpp"
using namespace glm;

#include <bit>
#include <cstdint>
#include <utility>

namespace std {
    template <>
    struct hash<ivec2> {
        size_t operator()(const ivec2& x) const {
            uint64_t key = (uint64_t(uint32_t(x.x)) << 32) | uint64_t(uint32_t(x.y));
            return std::hash<uint64_t>()(key);
        }
    };

    template <>
    struct hash<vec2> {
        size_t operator()(const vec2& x) const {
            uint64_t key = (uint64_t(std::bit_cast<uint32_t>(x.x)) << 32) | uint64_t(std::bit_cast<uint32_t>(x.y));
            return std::hash<uint64_t>()(key);
        }
    };
}
