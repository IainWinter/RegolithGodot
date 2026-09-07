#include "Body.h"
#include "Math/MathUtil.h"

#include "glm/geometric.hpp"

PhysicsBody::PhysicsBody()
    : PhysicsBody(vec2(0.f), 0.f) {}

PhysicsBody::PhysicsBody(vec2 position, float angle)
    : position(position)
    , angle(angle)
    , last_position(position)
    , last_angle(angle)
    , linear_velocity(vec2(0.f))
    , angular_velocity(0.f)
    , linear_damping(0.01f)
    , angular_damping(0.01f)
    , center_of_mass(vec2(0.f))
    , inv_mass(1.f)
    , inv_inertia(1.f)
    , angle_fixed(false)
    , joint_level(0)
    , collision_priority(0)
    , attempt_lower_priority(false) {}

float PhysicsBody::mass() const {
    return inv_mass > 0.f ? 1.f / inv_mass : 0.f;
}

float PhysicsBody::inertia() const {
    return inv_inertia > 0.f ? 1.f / inv_inertia : 0.f;
}

float PhysicsBody::speed() const {
    return length(linear_velocity);
}

void PhysicsBody::set_mass(float mass, float inertia) {
    inv_mass = mass > 0.f ? 1.f / mass : 0.f;
    inv_inertia = inertia > 0.f ? 1.f / inertia : 0.f;
}

void PhysicsBody::add_joint(const PhysicsJoint& joint) {
    joints.push_back(joint);
}

void PhysicsBody::remove_joint(int id) {
    std::erase_if(joints, [id](const auto& x) { return x.id == id; });
}

const PhysicsJoint* PhysicsBody::get_joint(int id) const {
    auto it = std::find_if(joints.begin(), joints.end(), [id](const auto& x) { return x.id == id; });

    if (it == joints.end()) {
        return nullptr;
    }

    return &*it;
}

Transform PhysicsBody::transform(vec2 scale) const {
    return Transform {
        .position = position,
        .scale = scale,
        .angle = angle
    };
}

void PhysicsBody::apply_impulse_center_of_mass(vec2 impulse) {
    linear_velocity += impulse * inv_mass;
}

void PhysicsBody::apply_impulse_r(vec2 impulse, vec2 r) {
    apply_impulse_center_of_mass(impulse);

    if (!angle_fixed) {
        angular_velocity += cross(r, impulse) * inv_inertia;
    }
}

vec2 PhysicsBody::velocity_at_local_point(vec2 local_point) const {
    vec2 r = rotate_local_point(local_point - center_of_mass, angle);
    return linear_velocity + cross(angular_velocity, r);
}