#include "Transform.h"
#include "Math/MathUtil.h"

#include <cmath>

godot::Vector2 Transform::to_world_point(godot::Vector2 localPoint, float sinAngle, float cosAngle) const {
    return rotate_local_point(localPoint * scale, sinAngle, cosAngle) + position;
}

godot::Vector2 Transform::to_world_point(godot::Vector2 localPoint) const {
    return rotate_local_point(localPoint * scale, angle) + position;
}

godot::Vector2 Transform::to_local_point(godot::Vector2 worldPoint, float negSinAngle, float negCosAngle) const {
    return rotate_local_point(worldPoint - position, negSinAngle, negCosAngle) / scale;
}

godot::Vector2 Transform::to_local_point(godot::Vector2 worldPoint) const {
    return rotate_local_point(worldPoint - position, -angle) / scale;
}

Transform Transform::child(const Transform& child) const {
    Transform combo;
    combo.position = position + rotate_local_point(child.position * scale, angle);
    combo.angle = angle + child.angle;
    combo.scale = scale * child.scale;

    return combo;
}

Transform Transform::sweep(godot::Vector2 linear_velocity, float angular_velocity, float delta_time) const {
    Transform swept;
    swept.scale = scale;
    swept.position = position + linear_velocity * delta_time;
    swept.angle = angle + angular_velocity * delta_time;

    return swept;
}

Transform Transform::sweep_around_center(godot::Vector2 center_of_mass, godot::Vector2 linear_velocity, float angular_velocity, float delta_time) const {
    auto [swept_position, swept_angle] = rotate_object_with_center_of_mass(
        center_of_mass,
        position,
        angle,
        linear_velocity,
        angular_velocity,
        delta_time
    );

    Transform swept;
    swept.scale = scale;
    swept.position = swept_position;
    swept.angle = swept_angle;

    return swept;
}

AxisAlignedBox Transform::bounds() const {
    godot::Vector2 corners[4];
    this->corners(corners);

    godot::Vector2 min = godot::Vector2(INFINITY, INFINITY);
    godot::Vector2 max = godot::Vector2(-INFINITY, -INFINITY);
    for (int i = 0; i < 4; ++i) {
        if (corners[i].x < min.x) min.x = corners[i].x;
        if (corners[i].y < min.y) min.y = corners[i].y;
        if (corners[i].x > max.x) max.x = corners[i].x;
        if (corners[i].y > max.y) max.y = corners[i].y;
    }

    AxisAlignedBox box;
    box.min = min;
    box.max = max;

    return box;
}

void Transform::corners(godot::Vector2* corners) const {
    float s = sinf(angle);
    float c = cosf(angle);

    corners[0] = rotate_local_point(godot::Vector2( scale.x,  scale.y), s, c) + position;
    corners[1] = rotate_local_point(godot::Vector2( scale.x, -scale.y), s, c) + position;
    corners[2] = rotate_local_point(godot::Vector2(-scale.x, -scale.y), s, c) + position;
    corners[3] = rotate_local_point(godot::Vector2(-scale.x,  scale.y), s, c) + position;
}

bool Transform::contains_local_point(godot::Vector2 localPoint) const {
    return localPoint.x >= -1.f && localPoint.x <= 1.f
        && localPoint.y >= -1.f && localPoint.y <= 1.f;
}
