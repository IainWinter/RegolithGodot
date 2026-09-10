#pragma once

#include "Coordinate/Transform.h"

#include <godot_cpp/core/object_id.hpp>

#include <godot_cpp/templates/local_vector.hpp>

enum PhysicsJointType {
    PhysicsJointType_Distance,
    PhysicsJointType_Rotator,
    PhysicsJointType_Rope
};

// To store these in the ecs set an id, then a system
// will match the ids to other entities
struct  PhysicsJoint {
    int id;
    godot::Vector2 r;
    int type;
    float distance = 0.f; // rest distance for rope joints
};

class  PhysicsBody {
public:
    godot::Vector2 position;
    float angle;

    godot::Vector2 last_position;
    float last_angle;

    godot::Vector2 linear_velocity;
    float angular_velocity;

    float linear_damping;
    float angular_damping;

    godot::Vector2 center_of_mass;
    float inv_mass;
    float inv_inertia;

    bool angle_fixed;

    int joint_level;

    int collision_priority;

    bool attempt_lower_priority;

    godot::LocalVector<PhysicsJoint> joints;

    PhysicsBody();

    PhysicsBody(godot::Vector2 position, float angle);

    float mass() const;

    float inertia() const;

    float speed() const;

    void set_mass(float mass, float inertia);

    void add_joint(const PhysicsJoint& joint);

    void remove_joint(int id);

    const PhysicsJoint* get_joint(int id) const;

    Transform transform(godot::Vector2 scale) const;

    /*
     * Apply an impulse at the center of mass
     */
    void apply_impulse_center_of_mass(godot::Vector2 impulse);

    /*
     * Apply an impulse at the vector r
     * r must be rotated and relative to the center of mass
     */
    void apply_impulse_r(godot::Vector2 impulse, godot::Vector2 r);

    /*
     * Velocity of the point at local_point, including spin
     */
    godot::Vector2 velocity_at_local_point(godot::Vector2 local_point) const;
};
