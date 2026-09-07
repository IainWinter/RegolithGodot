#include "AxisAlignedBox.h"
#include "Transform.h"

#include "Math/MathUtil.h"

#include "glm/common.hpp"

#include <float.h>
#include <algorithm>

AxisAlignedBox::AxisAlignedBox()
    : min (INFINITY)
    , max (-INFINITY)
{}

AxisAlignedBox::AxisAlignedBox(vec2 a, vec2 b) {
    min.x = std::min(a.x, b.x);
    min.y = std::min(a.y, b.y);
    max.x = std::max(a.x, b.x);
    max.y = std::max(a.y, b.y);
}

AxisAlignedBox::AxisAlignedBox(vec2 a, float boxExtent) 
    : min (a - boxExtent / 2.f)
    , max (a + boxExtent / 2.f)
{}

AxisAlignedBox::AxisAlignedBox(const vec2* points, int pointCount) 
    : min (INFINITY)
    , max (-INFINITY)
{
    const vec2* begin = points;
    const vec2* end = points + pointCount;
    for (const vec2* itr = begin; itr != end; ++itr) {
        add_point(*itr);
    }
}

AxisAlignedBox::AxisAlignedBox(const ivec2* points, int pointCount) 
    : min (INFINITY)
    , max (-INFINITY)
{
    const ivec2* begin = points;
    const ivec2* end = points + pointCount;
    for (const ivec2* itr = begin; itr != end; ++itr) {
        add_point(*itr);
    }
}

AxisAlignedBox::AxisAlignedBox(float left, float right, float bottom, float top) 
    : min (left, bottom)
    , max (right, top)
{}

bool AxisAlignedBox::intersects_box(const AxisAlignedBox& other) const {
    return max.x > other.min.x
        && min.x < other.max.x 
        && max.y > other.min.y
        && min.y < other.max.y;
}

bool AxisAlignedBox::intersects_ray(vec2 origin, vec2 direction, float max_length) const {
    float t1x = (min.x - origin.x) / direction.x;
    float t2x = (max.x - origin.x) / direction.x;
    float tmin = std::min(t1x, t2x);
    float tmax = std::max(t1x, t2x);

    float t1y = (min.y - origin.y) / direction.y;
    float t2y = (max.y - origin.y) / direction.y;
    tmin = std::max(tmin, std::min(t1y, t2y));
    tmax = std::min(tmax, std::max(t1y, t2y));

    if (tmax < 0.f) {
        return false;
    }

    if (tmin > max_length) {
        return false;
    }

    if (tmin > tmax) {
        return false;
    }

    return true;
}

bool AxisAlignedBox::contains_box(const AxisAlignedBox& other) const {
    return min.x < other.min.x 
        && max.x > other.max.x
        && min.y < other.min.y 
        && max.y > other.max.y;
}

bool AxisAlignedBox::contains_point(vec2 point) const {
    return min.x < point.x
        && min.y < point.y
        && max.x > point.x
        && max.y > point.y;
}

float AxisAlignedBox::area() const {
    vec2 s = max - min;
    return s.x * s.y;
}

AxisAlignedBox AxisAlignedBox::combine_box(const AxisAlignedBox& other) const {
    AxisAlignedBox bounds;
    bounds.min = glm::min(min, other.min);
    bounds.max = glm::max(max, other.max);

    return bounds;
}

AxisAlignedBox AxisAlignedBox::extend_box(vec2 translation, float rotation) const {
    float s = sinf(rotation);
    float c = cosf(rotation);
    
    vec2 points[8];
    corners(points);

    for (int i = 0; i < 4; i++) {
        points[i + 4] = translation + rotate_local_point(points[i], s, c);
    }

    return AxisAlignedBox(points, 8);
}

AxisAlignedBox AxisAlignedBox::bounds_of_intersection_box(const AxisAlignedBox& other) const {
    AxisAlignedBox result;

    result.min.x = std::max(min.x, other.min.x);
    result.min.y = std::max(min.y, other.min.y);

    result.max.x = std::min(max.x, other.max.x);
    result.max.y = std::min(max.y, other.max.y);

    if (result.min.x > result.max.x || result.min.y > result.max.y) {
        return AxisAlignedBox{ glm::vec2(0), glm::vec2(0) };
    }

    return result;
}

AxisAlignedBox AxisAlignedBox::to_world(const ::Transform& transform) const {
    float s = sinf(transform.angle);
    float c = cosf(transform.angle);
    
    vec2 points[4];
    corners(points);

    for (int i = 0; i < 4; i++) {
        points[i] = transform.to_world_point(points[i], s, c);
    }

    return AxisAlignedBox(points, 4);
}

AxisAlignedBox AxisAlignedBox::to_local(const ::Transform& transform) const {
    float s = sinf(-transform.angle);
    float c = cosf(-transform.angle);
    
    vec2 points[4];
    corners(points);

    for (int i = 0; i < 4; i++) {
        points[i] = transform.to_local_point(points[i], s, c);
    }

    return AxisAlignedBox(points, 4);
}

void AxisAlignedBox::add_point(vec2 point) {
    min.x = std::min(min.x, point.x);
    min.y = std::min(min.y, point.y);
    max.x = std::max(max.x, point.x);
    max.y = std::max(max.y, point.y);
}

void AxisAlignedBox::corners(vec2* corners) const {
    corners[0] = min;
    corners[1] = vec2(max.x, min.y);
    corners[2] = max;
    corners[3] = vec2(min.x, max.y);
}

void AxisAlignedBox::clamp(vec2 clampMin, vec2 clampMax) {
    min = glm::clamp(min, clampMin, clampMax);
    max = glm::clamp(max, clampMin, clampMax);
}

std::pair<float, float> AxisAlignedBox::clip_ray(vec2 origin, vec2 direction, float max_length) const {
    float t1x = (min.x - origin.x) / direction.x;
    float t2x = (max.x - origin.x) / direction.x;
    float tmin = std::min(t1x, t2x);
    float tmax = std::max(t1x, t2x);

    float t1y = (min.y - origin.y) / direction.y;
    float t2y = (max.y - origin.y) / direction.y;
    tmin = std::max(tmin, std::min(t1y, t2y));
    tmax = std::min(tmax, std::max(t1y, t2y));

    tmin = std::max(tmin, 0.f);
    tmax = std::min(tmax, max_length);

    return std::make_pair(tmin, tmax);
}