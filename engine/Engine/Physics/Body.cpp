#include "Body.h"
#include "Math/MathUtil.h"



PhysicsBody::PhysicsBody()
    : PhysicsBody(godot::Vector2(0.f, 0.f), 0.f) {}

PhysicsBody::PhysicsBody(godot::Vector2 position, float angle)
    : position(position)
    , angle(angle)
    , last_position(position)
    , last_angle(angle)
    , linear_velocity(godot::Vector2(0.f, 0.f))
    , angular_velocity(0.f)
    , linear_damping(0.01f)
    , angular_damping(0.01f)
    , center_of_mass(godot::Vector2(0.f, 0.f))
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
    return (linear_velocity).length();
}

void PhysicsBody::set_mass(float mass, float inertia) {
    inv_mass = mass > 0.f ? 1.f / mass : 0.f;
    inv_inertia = inertia > 0.f ? 1.f / inertia : 0.f;
}

void PhysicsBody::add_joint(const PhysicsJoint& joint) {
    joints.push_back(joint);
}

void PhysicsBody::remove_joint(int id) {
    for (uint32_t i = 0; i < joints.size(); ) {
        if (joints[i].id == id) {
            joints.remove_at(i);
        } else {
            i++;
        }
    }
}

const PhysicsJoint* PhysicsBody::get_joint(int id) const {
    for (uint32_t i = 0; i < joints.size(); i++) {
        if (joints[i].id == id) {
            return &joints[i];
        }
    }
    return nullptr;
}

Transform PhysicsBody::transform(godot::Vector2 scale) const {
    return Transform {
        .position = position,
        .scale = scale,
        .angle = angle
    };
}

void PhysicsBody::apply_impulse_center_of_mass(godot::Vector2 impulse) {
    linear_velocity += impulse * inv_mass;
}

void PhysicsBody::apply_impulse_r(godot::Vector2 impulse, godot::Vector2 r) {
    apply_impulse_center_of_mass(impulse);

    if (!angle_fixed) {
        angular_velocity += cross(r, impulse) * inv_inertia;
    }
}

godot::Vector2 PhysicsBody::velocity_at_local_point(godot::Vector2 local_point) const {
    godot::Vector2 r = rotate_local_point(local_point - center_of_mass, angle);
    return linear_velocity + cross(angular_velocity, r);
}