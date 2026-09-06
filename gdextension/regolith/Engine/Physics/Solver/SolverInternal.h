#pragma once

#include "Physics/World.h"
#include "DebugLineList.h"
#include "Math/MathUtil.h"
#include "UnionFindFixed.h"

#include <vector>

// solver bodies live at their center of mass, proxy position written back at the end

struct SolverBody {
    vec2 com;
    float angle;
    vec2 prev_com;
    float prev_angle;
    vec2 linear_velocity;
    float angular_velocity;
    float inv_mass;
    float inv_inertia;
    vec2 com_scaled; // center of mass * scale, unrotated
    vec2 scale;
    vec2 cells;
    float cell_world;
    float bound_radius;
    bool moves; // dynamic, or zero mass with a velocity (kinematic)

    vec2 bias_com; // depenetration this substep, excluded from derived velocity
    float bias_angle;
};

struct ContactCandidate {
    int point_proxy;
    int field_proxy;
    vec2 local_point;
    float radius;
    float vn_rest;
    float vt_rest;
    vec2 normal;
    float lambda_n;
    float depth;
    float separation;
    float impulse_n;
    vec2 impulse_t;
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
    vec2 normal;
};

FieldKind field_kind_of(const PhysicsProxy& proxy, const Collider* shape);

FieldSample field_sample(const PhysicsProxy& fp, const Collider* shape, const SolverBody& fb, FieldKind kind, vec2 world);

struct Island {
    std::vector<int> candidate_indices;
    std::vector<int> body_indices;
    std::vector<int> rope_indices;
    std::vector<int> joint_indices;
};

// normal direction buckets for manifold reduction
inline constexpr int k_contact_sectors = 8;

// persistent buffers reused tick over tick. holding capacity keeps the solver
// off the allocator, the contents are rebuilt each call
struct PhysicsSolverState {
    std::vector<SolverBody> bodies;
    std::vector<FieldKind> field_kinds;
    std::vector<const Collider*> proxy_shapes; // per proxy, null without a shape
    std::vector<ProxyPair> pairs;
    std::vector<ContactCandidate> candidates;
    std::vector<std::vector<ContactCandidate>> candidates_per_pair;
    std::vector<std::vector<int>> rope_touches;
    UnionFindFixed uf;
    std::vector<int> island_of;
    std::vector<Island> islands;
    int islands_used = 0;
    AxisAlignedAreaTreeIndex broadphase;
    std::vector<int> broadphase_overlapping;

    std::vector<std::pair<godot::ObjectID, godot::ObjectID>> lowering_overlaps;
};

// ---------------------------------------------------------------------------
// pose math

inline vec2 body_point_world(const SolverBody& b, vec2 local, vec2 com, float angle) {
    return com + rotate_local_point(local * b.scale - b.com_scaled, angle);
}

inline vec2 body_point_world(const SolverBody& b, vec2 local) {
    return body_point_world(b, local, b.com, b.angle);
}

inline vec2 body_world_to_local(const SolverBody& b, vec2 world) {
    return (rotate_local_point(world - b.com, -b.angle) + b.com_scaled) / b.scale;
}

inline vec2 body_local_to_grid(const SolverBody& b, vec2 local) {
    return (local + 1.f) * 0.5f * b.cells;
}

inline vec2 body_world_to_grid(const SolverBody& b, vec2 world) {
    return body_local_to_grid(b, body_world_to_local(b, world));
}

inline float body_inverse_mass_at(const SolverBody& b, vec2 r, vec2 n) {
    float rn = cross(r, n);
    return b.inv_mass + b.inv_inertia * rn * rn;
}

inline void body_apply_correction(SolverBody& b, vec2 impulse, vec2 r) {
    IF_DEBUG {
        debug_render_fixed().ray(b.com + r, impulse * b.inv_mass, DebugName_Physics_Force_Correction);
    }

    b.com += impulse * b.inv_mass;
    b.angle += b.inv_inertia * cross(r, impulse);
}

inline void body_apply_bias_correction(SolverBody& b, vec2 impulse, vec2 r) {
    IF_DEBUG {
        debug_render_fixed().ray(b.com + r, impulse * b.inv_mass, DebugName_Physics_Force_Bias);
    }

    vec2 delta_com = impulse * b.inv_mass;
    float delta_angle = b.inv_inertia * cross(r, impulse);

    b.com += delta_com;
    b.angle += delta_angle;
    b.bias_com += delta_com;
    b.bias_angle += delta_angle;
}

inline void body_apply_velocity(SolverBody& b, vec2 impulse, vec2 r) {
    IF_DEBUG {
        debug_render_fixed().ray(b.com + r, impulse * b.inv_mass, DebugName_Physics_Force_Velocity);
    }

    b.linear_velocity += impulse * b.inv_mass;
    b.angular_velocity += b.inv_inertia * cross(r, impulse);
}

inline vec2 body_velocity_at(const SolverBody& b, vec2 r) {
    return b.linear_velocity + cross(b.angular_velocity, r);
}

// ---------------------------------------------------------------------------
// broadphase, contact, joint, rope, island

vec2 contact_normal(const PhysicsProxy& proxy, const SolverBody& fb, vec2 grid, vec2 world);

void find_pairs(const std::vector<PhysicsProxy>& proxies, const std::vector<SolverBody>& bodies,
                PhysicsSolverState& state);

void gather_candidates(const std::vector<PhysicsProxy>& proxies,
                       const std::vector<FieldKind>& field_kinds, const std::vector<const Collider*>& proxy_shapes,
                       const std::vector<SolverBody>& bodies, const PhysicsSettings& settings, float delta_time,
                       PhysicsSolverState& state);

void solve_contact_position(const std::vector<PhysicsProxy>& proxies, const std::vector<FieldKind>& field_kinds,
                            const std::vector<const Collider*>& proxy_shapes, std::vector<SolverBody>& bodies,
                            ContactCandidate& c, float friction, float max_depenetration_cells);

void solve_contact_velocity(std::vector<SolverBody>& bodies, ContactCandidate& c, const PhysicsSettings& settings,
                            float substep_time);

void solve_contact_restitution(std::vector<SolverBody>& bodies, ContactCandidate& c, const PhysicsSettings& settings);

void solve_joint(std::vector<SolverBody>& bodies, const SolverJoint& joint);

void solve_rope_attach(std::vector<SolverBody>& bodies, PhysicsRope& rope, const PhysicsRopeAnchor& anchor, int particle);

void solve_rope_pin_to_rope(std::vector<PhysicsRope>& ropes, PhysicsRope& rope, const PhysicsRopeAnchor& anchor,
                            int particle);

void solve_rope_long_range(std::vector<SolverBody>& bodies, PhysicsRope& rope);

void solve_rope_segments(PhysicsRope& rope, float compliance, float min_length_factor, float substep_time);

void solve_rope_shape(const std::vector<SolverBody>& bodies, PhysicsRope& rope, float stiffness);

void solve_rope_collision(const std::vector<PhysicsProxy>& proxies, std::vector<SolverBody>& bodies,
                          PhysicsRope& rope, int proxy_index, float max_depenetration_cells);

void solve_rope_contact_velocity(std::vector<SolverBody>& bodies, PhysicsRope& rope);

void solve_rope_rope_collision(std::vector<PhysicsRope>& ropes, int index_a, int index_b);

void solve_island(const std::vector<PhysicsProxy>& proxies, const std::vector<FieldKind>& field_kinds,
                  const std::vector<const Collider*>& proxy_shapes, std::vector<SolverBody>& bodies,
                  std::vector<ContactCandidate>& candidates, std::vector<PhysicsRope>& ropes,
                  const std::vector<std::vector<int>>& rope_touches, const std::vector<SolverJoint>& joints,
                  const Island& island, const PhysicsSettings& settings, float delta_time);
