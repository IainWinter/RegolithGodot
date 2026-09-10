#pragma once

#include "Coordinate/Transform.h"

struct  ContactPoint {
    godot::Vector2 local_point_0;
    godot::Vector2 local_point_1;
    godot::Vector2 world_point;
    godot::Vector2 normal;
    float depth;
};
