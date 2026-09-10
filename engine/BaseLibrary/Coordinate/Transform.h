#pragma once

#include "AxisAlignedBox.h"
#include "Math/Vector.h"

class Transform {
public:
    godot::Vector2 position = godot::Vector2(0.f, 0.f);
    godot::Vector2 scale = godot::Vector2(1.f, 1.f);
    float angle = 0;

    godot::Vector2 to_world_point(godot::Vector2 localPoint, float sinAngle, float cosAngle) const;

    godot::Vector2 to_world_point(godot::Vector2 localPoint) const;

    godot::Vector2 to_local_point(godot::Vector2 worldPoint, float negSinAngle, float negCosAngle) const;

    godot::Vector2 to_local_point(godot::Vector2 worldPoint) const;

    Transform child(const Transform& parent) const; // rename

    Transform sweep(godot::Vector2 linear_velocity, float angular_velocity, float delta_time) const;

    Transform sweep_around_center(godot::Vector2 center_of_mass, godot::Vector2 linear_velocity, float angular_velocity, float delta_time) const;

    AxisAlignedBox bounds() const;

    void corners(godot::Vector2* corners) const;

    bool contains_local_point(godot::Vector2 localPoint) const;
};
