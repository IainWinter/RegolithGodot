#pragma once

#include "Coordinate/Transform.h"
#include "Coordinate/AxisAlignedAreaTree.h"
#include "Coordinate/AxisAlignedBox.h"
#include "Physics/Body.h"
#include "Physics/Collider.h"
#include "DestructibleSprite/Sprite.h"
#include "UnionFindFixed.h"

#include "Parallel.h"

#include <memory>
#include <unordered_map>
#include <utility>
#include <vector>

// sdf sprite physics, substepped xpbd. depth and normals come from each
// sprite's distance field, ropes are particle chains and joints solve in
// the same loop. joints never touch the field, they share the loop and
// the islands so everything moving a body negotiates together

enum PhysicsWorldJointType {
    PhysicsWorldJointType_Pin,
    PhysicsWorldJointType_Distance, // pull only, slack under the rest distance
    PhysicsWorldJointType_PushDistance, // push only, keeps bodies apart
};

// a proxy without a sprite has no field of its own, it interacts through
// ropes, joints, or a Collider shape pushed into PhysicsWorld::shapes()
struct PhysicsProxy {
    godot::ObjectID entity;
    PhysicsBody* body = nullptr;
    Sprite* sprite = nullptr;
    vec2 scale = vec2(1.f);
    AxisAlignedBox extended_box;
};

// the shape collection. each entry attaches a Collider to the proxy holding
// the same body, the solve turns every shape into depth + normal contacts
struct PhysicsShapeEntry {
    PhysicsBody* body = nullptr;
    Collider collider;
};

struct PhysicsRopeAnchor {
    int proxy_index = -1; // -1 = free end
    vec2 local_point = vec2(0.f);

    // pin onto another rope's node instead of a body
    int rope_index = -1;
    int node_index = 0;
};

struct PhysicsRopeContact {
    int proxy_index;
    int node_a;
    int node_b; // -1 when the sample only loads one node
    float weight_a;
    float weight_b;
    vec2 normal; // points out of the body
    vec2 point; // world
    bool one_way;
};

struct PhysicsRope {
    PhysicsRopeAnchor anchor_a;
    PhysicsRopeAnchor anchor_b;

    std::vector<vec2> positions; // world
    std::vector<vec2> velocities;
    std::vector<vec2> prev_positions; // transient, substep start

    float segment_rest_length = 0.f;
    std::vector<float> rest_lengths; // per segment, empty uses segment_rest_length
    float node_inv_mass = 10.f;
    float radius = 0.f; // world collision radius of a node, 0 picks half a cell

    // rest node positions in the owner's local frame. the shape solve pulls
    // every node back toward this pose by shape_stiffness, empty disables
    std::vector<vec2> rest_locals;
    float shape_stiffness = 0.f; // restore factor per tick

    int owner_proxy = -1; // constraints against the owner go one way until an outside body presses the chain

    bool externally_pushed = false; // transient, set during the solve

    float damping = -1.f; // per second, negative uses the settings value

    std::vector<vec2> bias; // transient, positional polish excluded from derived velocity

    // transient, the last position pass's sprite contacts. the velocity pass
    // resolves them so depenetration never has to carry the momentum
    std::vector<PhysicsRopeContact> contacts;
};

struct SolverJoint {
    int proxy_0;
    int proxy_1;
    vec2 local_0;
    vec2 local_1;
    int type; // PhysicsWorldJointType
    float distance = 0.f;
};

// one contact per touching pair, for gameplay events
struct PhysicsContact {
    godot::ObjectID entity_0;
    godot::ObjectID entity_1;
    vec2 world_point;
    vec2 normal;
    vec2 local_point_0;
    vec2 local_point_1;
    float depth;
    float approach_speed;
    float tangent_speed;
};

struct PhysicsSettings {
    int substeps = 8;
    int position_iterations = 2; // per substep
    int velocity_iterations = 4; // per substep
    vec2 gravity = vec2(0.f);
    float friction = 0.4f;
    float restitution = 0.f;
    float restitution_threshold = 1.f; // approach speed under this sticks
    float contact_margin_cells = 2.f; // extra reach when gathering candidates
    float max_depenetration_cells = 2.f; // per substep
    float rope_stretch_compliance = 0.f;
    float rope_damping = 0.5f; // per second
    bool rope_collide_sprites = true;
    bool rope_collide_ropes = true;
    float rope_min_length_factor = 0.5f; // segments resist compressing below this
};

// evenly spaced nodes between two points, slack > 1 leaves extra length
PhysicsRope physics_create_rope(vec2 world_a, vec2 world_b, int node_count, float slack);

// anchors are sprite local points, the world maps bodies to solver proxies
struct PhysicsWorldJoint {
    PhysicsBody* body_0;
    PhysicsBody* body_1;
    vec2 local_0;
    vec2 local_1;
    int type;
    float distance = 0.f;
};

// internal scratch held by PhysicsWorld, opaque to public callers
struct PhysicsSolverState;

// owns the solve. systems fill proxies and ropes each fixed tick, queue
// joints from anywhere before that, then solve runs everything. proxies
// hold component pointers so they clear with the solve, ropes stay until
// the next fill so solved state can be read back
class PhysicsWorld {
public:
    PhysicsWorld();
    ~PhysicsWorld();

    PhysicsWorld(const PhysicsWorld&) = delete;
    PhysicsWorld& operator=(const PhysicsWorld&) = delete;
    PhysicsWorld(PhysicsWorld&&) = delete;
    PhysicsWorld& operator=(PhysicsWorld&&) = delete;

    int get_joint_id();

    void add_joint(const PhysicsWorldJoint& joint);

    void clear_joints();

    PhysicsSettings& settings();

    std::vector<PhysicsProxy>& proxies();

    std::vector<PhysicsShapeEntry>& shapes();

    std::vector<PhysicsRope>& ropes();

    void solve(float delta_time);

    const std::vector<PhysicsContact>& contacts() const;

    // pairs skipped this solve because a body is lowering its priority, used to
    // tell when such a body has moved clear of everything
    const std::vector<std::pair<godot::ObjectID, godot::ObjectID>>& overlaps() const;

private:
    PhysicsSettings m_settings;
    std::vector<PhysicsProxy> m_proxies;
    std::vector<PhysicsShapeEntry> m_shapes;
    std::vector<PhysicsRope> m_ropes;
    std::vector<PhysicsWorldJoint> m_joints;
    std::vector<PhysicsContact> m_contacts;
    std::vector<SolverJoint> m_solver_joints_scratch;
    std::unordered_map<const PhysicsBody*, int> m_proxy_lookup_scratch;
    std::unique_ptr<PhysicsSolverState> m_state;
    int m_next_joint_id = 0;
};
