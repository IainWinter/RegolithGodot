#include "Transform.h"
#include "Math/MathUtil.h"

#include "glm/trigonometric.hpp"
#include "glm/gtc/matrix_transform.hpp"
#include <cmath>

vec2 Transform::to_world_point(vec2 localPoint, float sinAngle, float cosAngle) const {
    return rotate_local_point(localPoint * scale, sinAngle, cosAngle) + position;
}

vec2 Transform::to_world_point(vec2 localPoint) const {
    return rotate_local_point(localPoint * scale, angle) + position;
}

vec2 Transform::to_local_point(vec2 worldPoint, float negSinAngle, float negCosAngle) const {
    return rotate_local_point(worldPoint - position, negSinAngle, negCosAngle) / scale;
}

vec2 Transform::to_local_point(vec2 worldPoint) const {
    return rotate_local_point(worldPoint - position, -angle) / scale;
}

mat4x4 Transform::matrix4() const {
    mat4 model = glm::mat4(1.f);
    model = glm::translate(model, vec3(position, z));
    model = glm::rotate(model, angle, vec3(0.f, 0.f, 1.f));
    model = glm::scale(model, vec3(scale, 1.f));

    return model;
}

Transform Transform::child(const Transform& child) const {
    Transform combo;
    combo.position = position + rotate_local_point(child.position * scale, angle);
    combo.angle = angle + child.angle;
    combo.scale = scale * child.scale;
    combo.z = z + child.z;

    return combo;
}

Transform Transform::sweep(vec2 linear_velocity, float angular_velocity, float delta_time) const {
    Transform swept;
    swept.scale = scale;
    swept.position = position + linear_velocity * delta_time;
    swept.angle = angle + angular_velocity * delta_time;
    swept.z = z;

    return swept;
}

Transform Transform::sweep_around_center(vec2 center_of_mass, vec2 linear_velocity, float angular_velocity, float delta_time) const {
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
    swept.z = z;
    
    return swept;
}

AxisAlignedBox Transform::bounds() const {
    vec2 corners[4];
    this->corners(corners);

    vec2 min = vec2(INFINITY);
    vec2 max = vec2(-INFINITY);
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

void Transform::corners(vec2* corners) const {
    float s = sinf(angle);
    float c = cosf(angle);

    corners[0] = rotate_local_point(vec2( scale.x,  scale.y), s, c) + position;
    corners[1] = rotate_local_point(vec2( scale.x, -scale.y), s, c) + position;
    corners[2] = rotate_local_point(vec2(-scale.x, -scale.y), s, c) + position;
    corners[3] = rotate_local_point(vec2(-scale.x,  scale.y), s, c) + position;
}

bool Transform::contains_local_point(vec2 localPoint) const {
    return localPoint.x >= -1.f && localPoint.x <= 1.f 
        && localPoint.y >= -1.f && localPoint.y <= 1.f;
}