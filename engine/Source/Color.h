#pragma once

#include <stdint.h>

struct Color4 {
    uint8_t r, g, b, a;

    constexpr Color4()
        : r (0)
        , g (0)
        , b (0)
        , a (0)
    {}

    constexpr Color4(int red, int green, int blue, int alpha)
        : r (static_cast<uint8_t>(red))
        , g (static_cast<uint8_t>(green))
        , b (static_cast<uint8_t>(blue))
        , a (static_cast<uint8_t>(alpha))
    {}

    constexpr Color4(float red, float green, float blue, float alpha)
        : r (static_cast<uint8_t>(red * 255.0f))
        , g (static_cast<uint8_t>(green * 255.0f))
        , b (static_cast<uint8_t>(blue * 255.0f))
        , a (static_cast<uint8_t>(alpha * 255.0f))
    {}

    Color4 mix(const Color4& other) const {
        return Color4(
            (r + other.r) / 2,
            (g + other.g) / 2,
            (b + other.b) / 2,
            (a + other.a) / 2
        );
    }

    bool operator==(const Color4& other) const {
        return r == other.r
            && g == other.g
            && b == other.b
            && a == other.a;
    }
};
