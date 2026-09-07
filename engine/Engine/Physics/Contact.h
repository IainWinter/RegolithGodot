#pragma once

#include "Coordinate/Transform.h"

struct [[Struct]] ContactPoint {
    vec2 local_point_0;
    vec2 local_point_1;
    vec2 world_point;
    vec2 normal;
    float depth;
};
