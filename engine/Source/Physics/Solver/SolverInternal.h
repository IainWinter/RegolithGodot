#include <godot_cpp/templates/pair.hpp>
#pragma once

#include "Physics/World.h"
#include "DebugLineList.h"
#include "Math/MathUtil.h"
#include "Containers/UnionFindFixed.h"

#include <godot_cpp/templates/local_vector.hpp>

// solver bodies live at their center of mass, proxy position written back at the end

struct SolverBody {
    godot::Vector2 com;
    float angle;
    godot::Vector2 prev_com;
    float prev_angle;
    godot::Vector2 linear_velocity;
    float angular_velocity;
    float inv_mass;
    float inv_inertia;
    godot::Vector2 com_scaled; // center of mass * scale, unrotated
    godot::Vector2 scale;
    godot::Vector2 cells;
    float cell_world;
    float bound_radius;
    bool moves; // dynamic, or zero mass with a velocity (kinematic)

    godot::Vector2 bias_com; // depenetration this substep, excluded from derived velocity
    float bias_angle;
};

struct ContactCandidate {
    int point_proxy;
    int field_proxy;
    godot::Vector2 local_point;
    float radius;
    float vn_rest;
    float vt_rest;
    godot::Vector2 normal;
    float lambda_n;
    float depth;
    float separation;
    float impulse_n;
    godot::Vector2 impulse_t;
    bool active;
    bool sensor;
};

struct ProxyPair {
    int proxy_0;
    int proxy_1;
};

// what kind of field a proxy presents to contact queries, classified once per
// solve so the contact code dispatches without re-deriving it
enum FieldKind {
    FieldKind_None,
    FieldKind_Sprite,
    FieldKind_Circle,
    FieldKind_Capsule,
    FieldKind_Plane,
};

struct FieldSample {
    float separation; // to the field surface, before the point radius
    godot::Vector2 normal;
};

FieldKind field_kind_of(const PhysicsProxy& proxy, const Collider* shape);

FieldSample field_sample(const PhysicsProxy& fp, const Collider* shape, const SolverBody& fb, FieldKind kind, godot::Vector2 world);

struct Island {
    godot::LocalVector<int> candidate_indices;
    godot::LocalVector<int> body_indices;
    godot::LocalVector<int> rope_indices;
    godot::LocalVector<int> joint_indices;
};

// normal direction buckets for manifold reduction
inline constexpr int k_contact_sectors = 8;

// persistent buffers reused tick over tick. holding capacity keeps the solver
// off the allocator, the contents are rebuilt each call
struct PhysicsSolverState {
    godot::LocalVector<SolverBody> bodies;
    godot::LocalVector<FieldKind> field_kinds;
    godot::LocalVector<const Collider*> proxy_shapes; // per proxy, null without a shape
    godot::LocalVector<ProxyPair> pairs;
    godot::LocalVector<ContactCandidate> candidates;
    godot::LocalVector<godot::LocalVector<ContactCandidate>> candidates_per_pair;
    godot::LocalVector<godot::LocalVector<int>> rope_touches;
    UnionFindFixed uf;
    godot::LocalVector<int> island_of;
    godot::LocalVector<Island> islands;
    int islands_used = 0;
    AxisAlignedAreaTreeIndex broadphase;
    godot::LocalVector<int> broadphase_overlapping;

    godot::LocalVector<godot::Pair<godot::ObjectID, godot::ObjectID>> lowering_overlaps;
};

// ---------------------------------------------------------------------------
// pose math

inline godot::Vector2 body_point_world(const SolverBody& b, godot::Vector2 local, godot::Vector2 com, float angle) {
    return com + rotate_local_point(local * b.scale - b.com_scaled, angle);
}

inline godot::Vector2 body_point_world(const SolverBody& b, godot::Vector2 local) {
    return body_point_world(b, local, b.com, b.angle);
}

inline godot::Vector2 body_world_to_local(const SolverBody& b, godot::Vector2 world) {
    return (rotate_local_point(world - b.com, -b.angle) + b.com_scaled) / b.scale;
}

inline godot::Vector2 body_local_to_grid(const SolverBody& b, godot::Vector2 local) {
    return godot::Vector2((local.x + 1.f) * 0.5f * b.cells.x, (local.y + 1.f) * 0.5f * b.cells.y);
}

inline godot::Vector2 body_world_to_grid(const SolverBody& b, godot::Vector2 world) {
    return body_local_to_grid(b, body_world_to_local(b, world));
}

inline float body_inverse_mass_at(const SolverBody& b, godot::Vector2 r, godot::Vector2 n) {
    float rn = cross(r, n);
    return b.inv_mass + b.inv_inertia * rn * rn;
}

inline void body_apply_correction(SolverBody& b, godot::Vector2 impulse, godot::Vector2 r) {
    IF_DEBUG {
        debug_render_fixed().ray(b.com + r, impulse * b.inv_mass, DebugName_Physics_Force_Correction);
    }

    b.com += impulse * b.inv_mass;
    b.angle += b.inv_inertia * cross(r, impulse);
}

inline void body_apply_bias_correction(SolverBody& b, godot::Vector2 impulse, godot::Vector2 r) {
    IF_DEBUG {
        debug_render_fixed().ray(b.com + r, impulse * b.inv_mass, DebugName_Physics_Force_Bias);
    }

    godot::Vector2 delta_com = impulse * b.inv_mass;
    float delta_angle = b.inv_inertia * cross(r, impulse);

    b.com += delta_com;
    b.angle += delta_angle;
    b.bias_com += delta_com;
    b.bias_angle += delta_angle;
}

inline void body_apply_velocity(SolverBody& b, godot::Vector2 impulse, godot::Vector2 r) {
    IF_DEBUG {
        debug_render_fixed().ray(b.com + r, impulse * b.inv_mass, DebugName_Physics_Force_Velocity);
    }

    b.linear_velocity += impulse * b.inv_mass;
    b.angular_velocity += b.inv_inertia * cross(r, impulse);
}

inline godot::Vector2 body_velocity_at(const SolverBody& b, godot::Vector2 r) {
    return b.linear_velocity + cross(b.angular_velocity, r);
}

// ---------------------------------------------------------------------------
// broadphase, contact, joint, rope, island

godot::Vector2 contact_normal(const PhysicsProxy& proxy, const SolverBody& fb, godot::Vector2 grid, godot::Vector2 world);

void find_pairs(const godot::LocalVector<PhysicsProxy>& proxies, const godot::LocalVector<SolverBody>& bodies,
                PhysicsSolverState& state);

void gather_candidates(const godot::LocalVector<PhysicsProxy>& proxies,
                       const godot::LocalVector<FieldKind>& field_kinds, const godot::LocalVector<const Collider*>& proxy_shapes,
                       const godot::LocalVector<SolverBody>& bodies, const PhysicsSettings& settings, float delta_time,
                       PhysicsSolverState& state);

void solve_contact_position(const godot::LocalVector<PhysicsProxy>& proxies, const godot::LocalVector<FieldKind>& field_kinds,
                            const godot::LocalVector<const Collider*>& proxy_shapes, godot::LocalVector<SolverBody>& bodies,
                            ContactCandidate& c, float friction, float max_depenetration_cells);

void solve_contact_velocity(godot::LocalVector<SolverBody>& bodies, ContactCandidate& c, const PhysicsSettings& settings,
                            float substep_time);

void solve_contact_restitution(godot::LocalVector<SolverBody>& bodies, ContactCandidate& c, const PhysicsSettings& settings);

void solve_joint(godot::LocalVector<SolverBody>& bodies, const SolverJoint& joint);

void solve_rope_attach(godot::LocalVector<SolverBody>& bodies, PhysicsRope& rope, const PhysicsRopeAnchor& anchor, int particle);

void solve_rope_pin_to_rope(godot::LocalVector<PhysicsRope>& ropes, PhysicsRope& rope, const PhysicsRopeAnchor& anchor,
                            int particle);

void solve_rope_long_range(godot::LocalVector<SolverBody>& bodies, PhysicsRope& rope);

void solve_rope_segments(PhysicsRope& rope, float compliance, float min_length_factor, float substep_time);

void solve_rope_shape(const godot::LocalVector<SolverBody>& bodies, PhysicsRope& rope, float stiffness);

void solve_rope_collision(const godot::LocalVector<PhysicsProxy>& proxies, godot::LocalVector<SolverBody>& bodies,
                          PhysicsRope& rope, int proxy_index, float max_depenetration_cells);

void solve_rope_contact_velocity(godot::LocalVector<SolverBody>& bodies, PhysicsRope& rope);

void solve_rope_rope_collision(godot::LocalVector<PhysicsRope>& ropes, int index_a, int index_b);

void solve_island(const godot::LocalVector<PhysicsProxy>& proxies, const godot::LocalVector<FieldKind>& field_kinds,
                  const godot::LocalVector<const Collider*>& proxy_shapes, godot::LocalVector<SolverBody>& bodies,
                  godot::LocalVector<ContactCandidate>& candidates, godot::LocalVector<PhysicsRope>& ropes,
                  const godot::LocalVector<godot::LocalVector<int>>& rope_touches, const godot::LocalVector<SolverJoint>& joints,
                  const Island& island, const PhysicsSettings& settings, float delta_time);
