#pragma once

#include "Math/Vector.h"

#include <cmath>

inline bool equal(float a, float b, float e = 1e-8f) {
    float x = a - b;
    return x * x < e;
}

inline bool equal(godot::Vector2 a, godot::Vector2 b, float e = 1e-8f) {
    return equal(a.x, b.x, e) && equal(a.y, b.y, e);
}
