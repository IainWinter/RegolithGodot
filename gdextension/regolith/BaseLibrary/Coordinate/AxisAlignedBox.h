#pragma once

#include "glm/vec2.hpp"
using namespace glm;

#include <utility>

class Transform;

struct [[Struct]] AxisAlignedBox {
    vec2 min;
    vec2 max;

    AxisAlignedBox();
    
    AxisAlignedBox(vec2 a, vec2 b);

    AxisAlignedBox(vec2 a, float boxExtent);

    AxisAlignedBox(const vec2* points, int pointCount);

    AxisAlignedBox(const ivec2* points, int pointCount);

    AxisAlignedBox(float left, float right, float bottom, float top);

    bool intersects_box(const AxisAlignedBox& other) const;

    bool intersects_ray(vec2 origin, vec2 direction, float max_length) const;

    bool contains_box(const AxisAlignedBox& other) const;

    bool contains_point(vec2 point) const;

    float area() const;

    AxisAlignedBox combine_box(const AxisAlignedBox& other) const;

    AxisAlignedBox extend_box(vec2 translation, float rotation) const;

    AxisAlignedBox bounds_of_intersection_box(const AxisAlignedBox& other) const;

    AxisAlignedBox to_world(const Transform& transform) const;

    AxisAlignedBox to_local(const Transform& transform) const;

    void add_point(vec2 point);

    void corners(vec2* corners) const;

    void clamp(vec2 clampMin, vec2 clampMax);

    std::pair<float, float> clip_ray(vec2 origin, vec2 direction, float max_length) const;
};
