#pragma once

#include "AxisAlignedBox.h"

#include "glm/vec2.hpp"
#include "glm/mat4x4.hpp"
using namespace glm;

/**
 * A 2D matrix stored as its components
*/
class [[Component]] Transform {
public:
    vec2 position = vec2(0.f);
    vec2 scale = vec2(1.f);
    float angle = 0;
    float z = 0;

    vec2 to_world_point(vec2 localPoint, float sinAngle, float cosAngle) const;

    vec2 to_world_point(vec2 localPoint) const;

    vec2 to_local_point(vec2 worldPoint, float negSinAngle, float negCosAngle) const;
    
    vec2 to_local_point(vec2 worldPoint) const;

    mat4x4 matrix4() const;

    Transform child(const Transform& parent) const; // rename

    Transform sweep(vec2 linear_velocity, float angular_velocity, float delta_time) const;

    Transform sweep_around_center(vec2 center_of_mass, vec2 linear_velocity, float angular_velocity, float delta_time) const;

    AxisAlignedBox bounds() const;

    void corners(vec2* corners) const;

    bool contains_local_point(vec2 localPoint) const;
};
