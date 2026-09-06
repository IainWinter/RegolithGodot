#pragma once

#include "glm/vec3.hpp"
#include "glm/vec4.hpp"
using namespace glm;

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

    constexpr Color4(vec4 rgba) 
        : r (static_cast<uint8_t>(rgba.x * 255.0f))
        , g (static_cast<uint8_t>(rgba.y * 255.0f))
        , b (static_cast<uint8_t>(rgba.z * 255.0f))
        , a (static_cast<uint8_t>(rgba.w * 255.0f))
    {}

    vec4 as_vec4() const {
        return vec4(float(r), float(g), float(b), float(a)) / 255.f;
    }

    vec4 as_vec4_no_alpha() const {
        return vec4(float(r), float(g), float(b), 0.f) / 255.f;
    }

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

struct Color3 {
    uint8_t r, g, b;

    Color3() 
        : r (0)
        , g (0)
        , b (0)
    {}

    Color3(int red, int green, int blue) 
        : r (static_cast<uint8_t>(red))
        , g (static_cast<uint8_t>(green))
        , b (static_cast<uint8_t>(blue))
    {}

    Color3(float red, float green, float blue) 
        : r (static_cast<uint8_t>(red * 255.0f))
        , g (static_cast<uint8_t>(green * 255.0f))
        , b (static_cast<uint8_t>(blue * 255.0f))
    {}

    vec3 as_vec3() const {
        return vec3(float(r), float(g), float(b)) / 255.f;
    }

    bool operator==(const Color4& other) const {
        return r == other.r
            && g == other.g
            && b == other.b;
    }
};

struct ColorFloat {
    float r, g, b, a;

    constexpr ColorFloat()
        : r (0.f)
        , g (0.f)
        , b (0.f)
        , a (0.f)
    {}

    constexpr ColorFloat(float red, float green, float blue, float alpha)
        : r (red)
        , g (green)
        , b (blue)
        , a (alpha)
    {}

    constexpr ColorFloat(vec4 rgba)
        : r (rgba.x)
        , g (rgba.y)
        , b (rgba.z)
        , a (rgba.w)
    {}

    constexpr ColorFloat(Color4 c)
        : r (c.r / 255.f)
        , g (c.g / 255.f)
        , b (c.b / 255.f)
        , a (c.a / 255.f)
    {}

    vec4 as_vec4() const {
        return vec4(r, g, b, a);
    }

    vec4 as_vec4_no_alpha() const {
        return vec4(r, g, b, 0.f);
    }

    operator vec4() const {
        return as_vec4();
    }

    operator Color4() const {
        return Color4(r, g, b, a);
    }

    bool operator==(const ColorFloat& other) const {
        return r == other.r
            && g == other.g
            && b == other.b
            && a == other.a;
    }
};
