#include <godot_cpp/templates/pair.hpp>
#include "AxisAlignedBox.h"
#include "Transform.h"

#include "Math/MathUtil.h"

#include <float.h>
#include <algorithm>

AxisAlignedBox::AxisAlignedBox()
    : min (INFINITY, INFINITY)
    , max (-INFINITY, -INFINITY)
{}

AxisAlignedBox::AxisAlignedBox(godot::Vector2 a, godot::Vector2 b) {
    min.x = std::min(a.x, b.x);
    min.y = std::min(a.y, b.y);
    max.x = std::max(a.x, b.x);
    max.y = std::max(a.y, b.y);
}

AxisAlignedBox::AxisAlignedBox(godot::Vector2 a, float boxExtent)
    : min (a.x - boxExtent / 2.f, a.y - boxExtent / 2.f)
    , max (a.x + boxExtent / 2.f, a.y + boxExtent / 2.f)
{}

AxisAlignedBox::AxisAlignedBox(const godot::Vector2* points, int pointCount)
    : min (INFINITY, INFINITY)
    , max (-INFINITY, -INFINITY)
{
    const godot::Vector2* begin = points;
    const godot::Vector2* end = points + pointCount;
    for (const godot::Vector2* itr = begin; itr != end; ++itr) {
        add_point(*itr);
    }
}

AxisAlignedBox::AxisAlignedBox(const godot::Vector2i* points, int pointCount)
    : min (INFINITY, INFINITY)
    , max (-INFINITY, -INFINITY)
{
    const godot::Vector2i* begin = points;
    const godot::Vector2i* end = points + pointCount;
    for (const godot::Vector2i* itr = begin; itr != end; ++itr) {
        add_point(godot::Vector2(itr->x, itr->y));
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

bool AxisAlignedBox::intersects_ray(godot::Vector2 origin, godot::Vector2 direction, float max_length) const {
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

bool AxisAlignedBox::contains_point(godot::Vector2 point) const {
    return min.x < point.x
        && min.y < point.y
        && max.x > point.x
        && max.y > point.y;
}

float AxisAlignedBox::area() const {
    godot::Vector2 s = max - min;
    return s.x * s.y;
}

AxisAlignedBox AxisAlignedBox::combine_box(const AxisAlignedBox& other) const {
    AxisAlignedBox bounds;
    bounds.min = min.min(other.min);
    bounds.max = max.max(other.max);

    return bounds;
}

AxisAlignedBox AxisAlignedBox::extend_box(godot::Vector2 translation, float rotation) const {
    float s = sinf(rotation);
    float c = cosf(rotation);

    godot::Vector2 points[8];
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
        return AxisAlignedBox{ godot::Vector2(0, 0), godot::Vector2(0, 0) };
    }

    return result;
}

AxisAlignedBox AxisAlignedBox::to_world(const ::Transform& transform) const {
    float s = sinf(transform.angle);
    float c = cosf(transform.angle);

    godot::Vector2 points[4];
    corners(points);

    for (int i = 0; i < 4; i++) {
        points[i] = transform.to_world_point(points[i], s, c);
    }

    return AxisAlignedBox(points, 4);
}

AxisAlignedBox AxisAlignedBox::to_local(const ::Transform& transform) const {
    float s = sinf(-transform.angle);
    float c = cosf(-transform.angle);

    godot::Vector2 points[4];
    corners(points);

    for (int i = 0; i < 4; i++) {
        points[i] = transform.to_local_point(points[i], s, c);
    }

    return AxisAlignedBox(points, 4);
}

void AxisAlignedBox::add_point(godot::Vector2 point) {
    min.x = std::min(min.x, point.x);
    min.y = std::min(min.y, point.y);
    max.x = std::max(max.x, point.x);
    max.y = std::max(max.y, point.y);
}

void AxisAlignedBox::corners(godot::Vector2* corners) const {
    corners[0] = min;
    corners[1] = godot::Vector2(max.x, min.y);
    corners[2] = max;
    corners[3] = godot::Vector2(min.x, max.y);
}

void AxisAlignedBox::clamp(godot::Vector2 clampMin, godot::Vector2 clampMax) {
    min = min.clamp(clampMin, clampMax);
    max = max.clamp(clampMin, clampMax);
}

godot::Pair<float, float> AxisAlignedBox::clip_ray(godot::Vector2 origin, godot::Vector2 direction, float max_length) const {
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

    return {tmin, tmax};
}
