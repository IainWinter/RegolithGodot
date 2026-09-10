#pragma once

#include "Math/Vector.h"

#include <godot_cpp/templates/pair.hpp>

class Transform;

struct  AxisAlignedBox {
    godot::Vector2 min;
    godot::Vector2 max;

    AxisAlignedBox();

    AxisAlignedBox(godot::Vector2 a, godot::Vector2 b);

    AxisAlignedBox(godot::Vector2 a, float boxExtent);

    AxisAlignedBox(const godot::Vector2* points, int pointCount);

    AxisAlignedBox(const godot::Vector2i* points, int pointCount);

    AxisAlignedBox(float left, float right, float bottom, float top);

    bool intersects_box(const AxisAlignedBox& other) const;

    bool intersects_ray(godot::Vector2 origin, godot::Vector2 direction, float max_length) const;

    bool contains_box(const AxisAlignedBox& other) const;

    bool contains_point(godot::Vector2 point) const;

    float area() const;

    AxisAlignedBox combine_box(const AxisAlignedBox& other) const;

    AxisAlignedBox extend_box(godot::Vector2 translation, float rotation) const;

    AxisAlignedBox bounds_of_intersection_box(const AxisAlignedBox& other) const;

    AxisAlignedBox to_world(const Transform& transform) const;

    AxisAlignedBox to_local(const Transform& transform) const;

    void add_point(godot::Vector2 point);

    void corners(godot::Vector2* corners) const;

    void clamp(godot::Vector2 clampMin, godot::Vector2 clampMax);

    godot::Pair<float, float> clip_ray(godot::Vector2 origin, godot::Vector2 direction, float max_length) const;
};
