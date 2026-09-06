#pragma once

#include "glm/vec2.hpp"
using namespace glm;

enum class ColliderShape {
    None,
    Circle,
    Capsule,
    Plane
};

// analytic collision shape on the 2d plane, paired with a PhysicsBody.
// pushed into PhysicsWorld::shapes() each tick alongside the body's proxy,
// the solve converts every shape into depth + normal for the contacts.
// sensors report contacts without solving them
struct [[Component]] Collider {
    bool enabled = true;
    bool sensor = false;

    ColliderShape shape = ColliderShape::Circle;

    float radius = 1.f;

    // capsule runs from center - direction * half_length to center + direction * half_length,
    // radius is its thickness, the direction rotates with the body angle
    vec2 capsule_direction = vec2(1.f, 0.f);
    float capsule_half_length = 1.f;

    // plane collides when dot(normalize(normal), p) - d < radius of the other body,
    // fixed in world space
    vec2 plane_normal = vec2(0.f, 1.f);
    float plane_d = 0.f;
};
