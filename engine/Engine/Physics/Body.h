#pragma once

#include "Coordinate/Transform.h"

#include <godot_cpp/core/object_id.hpp>

#include <vector>

enum PhysicsJointType {
    PhysicsJointType_Distance,
    PhysicsJointType_Rotator,
    PhysicsJointType_Rope
};

// To store these in the ecs set an id, then a system
// will match the ids to other entities
struct [[Struct]] PhysicsJoint {
    int id;
    vec2 r;
    int type;
    float distance = 0.f; // rest distance for rope joints
};

class [[Component]] PhysicsBody {
public:
    vec2 position;
    float angle;

    vec2 last_position;
    float last_angle;

    vec2 linear_velocity;
    float angular_velocity;

    float linear_damping;
    float angular_damping;

    vec2 center_of_mass;
    float inv_mass;
    float inv_inertia;

    bool angle_fixed;

    int joint_level;

    int collision_priority;

    bool attempt_lower_priority;

    std::vector<PhysicsJoint> joints;

    PhysicsBody();

    PhysicsBody(vec2 position, float angle);

    float mass() const;

    float inertia() const;

    float speed() const;

    void set_mass(float mass, float inertia);

    void add_joint(const PhysicsJoint& joint);

    void remove_joint(int id);

    const PhysicsJoint* get_joint(int id) const;

    Transform transform(vec2 scale) const;

    /*
     * Apply an impulse at the center of mass
     */
    void apply_impulse_center_of_mass(vec2 impulse);

    /*
     * Apply an impulse at the vector r
     * r must be rotated and relative to the center of mass
     */
    void apply_impulse_r(vec2 impulse, vec2 r);

    /*
     * Velocity of the point at local_point, including spin
     */
    vec2 velocity_at_local_point(vec2 local_point) const;
};
