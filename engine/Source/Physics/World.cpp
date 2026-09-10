#include <godot_cpp/templates/pair.hpp>
#include "Containers/VectorUtil.h"
#include "World.h"
#include "Physics/Solver/SolverInternal.h"

#include <godot_cpp/core/memory.hpp>

#include <algorithm>
#include <cassert>
#include <cmath>

PhysicsWorld::PhysicsWorld()
    : m_state(memnew(PhysicsSolverState)) {}

PhysicsWorld::~PhysicsWorld() {
    godot::memdelete(m_state);
}

int PhysicsWorld::get_joint_id() {
    return m_next_joint_id++;
}

void PhysicsWorld::add_joint(const PhysicsWorldJoint& joint) {
    m_joints.push_back(joint);
}

void PhysicsWorld::clear_joints() {
    m_joints.clear();
}

PhysicsSettings& PhysicsWorld::settings() {
    return m_settings;
}

godot::LocalVector<PhysicsProxy>& PhysicsWorld::proxies() {
    return m_proxies;
}

godot::LocalVector<PhysicsShapeEntry>& PhysicsWorld::shapes() {
    return m_shapes;
}

godot::LocalVector<PhysicsRope>& PhysicsWorld::ropes() {
    return m_ropes;
}

const godot::LocalVector<PhysicsContact>& PhysicsWorld::contacts() const {
    return m_contacts;
}

const godot::LocalVector<godot::Pair<godot::ObjectID, godot::ObjectID>>& PhysicsWorld::overlaps() const {
    return m_state->lowering_overlaps;
}

// scale drives the solver's cell size for margins and depenetration caps,
// shapes have no grid so keep it near the shape's own size
static godot::Vector2 shape_proxy_scale(float radius) {
    float r = std::max(radius, 0.25f);
    return godot::Vector2(r, r);
}

static SolverBody make_solver_body(const PhysicsProxy& proxy) {
    const PhysicsBody& body = *proxy.body;

    SolverBody b;
    b.com_scaled = body.center_of_mass * proxy.scale;
    b.scale = proxy.scale;
    b.angle = body.angle;
    b.com = body.position + rotate_local_point(b.com_scaled, body.angle);
    b.prev_com = b.com;
    b.prev_angle = b.angle;
    b.linear_velocity = body.linear_velocity;
    b.angular_velocity = body.angular_velocity;
    b.inv_mass = body.inv_mass;
    b.inv_inertia = body.angle_fixed ? 0.f : body.inv_inertia;
    b.bound_radius = (proxy.scale).length() + 1e-3f;

    if (proxy.sprite) {
        b.cells = godot::Vector2(proxy.sprite->grid().cells);
        b.inv_inertia /= proxy.scale.x * proxy.scale.y;
    }

    else {
        b.cells = godot::Vector2(1.f, 1.f);
    }

    // sdf sampling uses a scalar cell size, so the world cell must be square.
    // scale may be non-uniform (a wide sprite has more chunks across) as long
    // as scale/cells stays equal per axis, which keeps each cell square
    godot::Vector2 world_cell = proxy.scale * 2.f / b.cells;
    assert(fabsf(world_cell.x - world_cell.y) < 1e-4f && "PhysicsBody requires square world cells");

    b.cell_world = world_cell.x;

    bool still = (body.linear_velocity).length() < 1e-9f && fabsf(body.angular_velocity) < 1e-9f;
    b.moves = body.inv_mass > 0.f || !still;

    b.bias_com = godot::Vector2(0.f, 0.f);
    b.bias_angle = 0.f;

    return b;
}

static Island& state_take_island(PhysicsSolverState& state) {
    if (state.islands_used >= static_cast<int>(state.islands.size())) {
        state.islands.push_back({});
    }

    Island& island = state.islands[state.islands_used++];
    island.candidate_indices.clear();
    island.body_indices.clear();
    island.rope_indices.clear();
    island.joint_indices.clear();

    return island;
}

void PhysicsWorld::solve(float delta_time) {

    m_proxy_lookup_scratch.clear();
    m_proxy_lookup_scratch.reserve(m_proxies.size());

    for (int i = 0; i < static_cast<int>(m_proxies.size()); i++) {
        // a body can be referenced by at most one proxy per tick, otherwise
        // joints and lookups bind to the wrong one
        [[maybe_unused]] bool inserted = !m_proxy_lookup_scratch.has(m_proxies[i].body);
        m_proxy_lookup_scratch.insert(m_proxies[i].body, i);
        assert(inserted && "duplicate PhysicsBody* in PhysicsWorld::solve proxies");
    }

    // the shape collection. attach each collider to the proxy holding the
    // same body and fill the shape driven parts of the proxy contract:
    // uniform scale for square cells and a broadphase box covering the shape

    vector_fill(m_state->proxy_shapes, m_proxies.size(), (const Collider*)nullptr);

    for (PhysicsShapeEntry& entry : m_shapes) {
        Collider& collider = entry.collider;

        if (!collider.enabled || collider.shape == ColliderShape::None) {
            continue;
        }

        auto it = m_proxy_lookup_scratch.find(entry.body);

        if (it == m_proxy_lookup_scratch.end()) {
            continue;
        }

        int index = it->value;
        PhysicsProxy& proxy = m_proxies[index];

        assert(!m_state->proxy_shapes[index] && "two shapes on one body");
        m_state->proxy_shapes[index] = &collider;

        // a sprite proxy fills its own scale and box, the shape only matters
        // once the sprite field is gone
        if (proxy.sprite) {
            continue;
        }

        const PhysicsBody& body = *entry.body;

        switch (collider.shape) {
            case ColliderShape::Circle: {
                proxy.scale = shape_proxy_scale(collider.radius);

                AxisAlignedBox box(body.position - godot::Vector2(collider.radius, collider.radius), body.position + godot::Vector2(collider.radius, collider.radius));
                proxy.extended_box = box.extend_box(body.linear_velocity * delta_time, 0.f);
                break;
            }

            case ColliderShape::Capsule: {
                collider.capsule_direction = safe_normalize(collider.capsule_direction);
                proxy.scale = shape_proxy_scale(collider.radius);

                godot::Vector2 axis = rotate_local_point(collider.capsule_direction, body.angle) * collider.capsule_half_length;
                godot::Vector2 points[2] = { body.position - axis, body.position + axis };

                AxisAlignedBox box(points, 2);
                box.min -= godot::Vector2(collider.radius, collider.radius);
                box.max += godot::Vector2(collider.radius, collider.radius);
                proxy.extended_box = box.extend_box(body.linear_velocity * delta_time, 0.f);
                break;
            }

            case ColliderShape::Plane: {
                // normal normalized here, d stays raw, the old iw convention.
                // planes are infinite so they always pass the broadphase
                collider.plane_normal = safe_normalize(collider.plane_normal);
                proxy.scale = godot::Vector2(0.5f, 0.5f);
                proxy.extended_box = AxisAlignedBox(godot::Vector2(-1e9f, -1e9f), godot::Vector2(1e9f, 1e9f));
                break;
            }

            default: {
                break;
            }
        }
    }

    // joints queued this tick, both ends need a proxy

    m_solver_joints_scratch.clear();
    m_solver_joints_scratch.reserve(m_joints.size());

    for (const PhysicsWorldJoint& joint : m_joints) {
        auto it_0 = m_proxy_lookup_scratch.find(joint.body_0);
        auto it_1 = m_proxy_lookup_scratch.find(joint.body_1);

        if (it_0 == m_proxy_lookup_scratch.end() || it_1 == m_proxy_lookup_scratch.end()) {
            continue;
        }

        m_solver_joints_scratch.push_back({it_0->value, it_1->value, joint.local_0, joint.local_1, joint.type, joint.distance});
    }

    m_joints.clear();
    m_contacts.clear();

    PhysicsSolverState& state = *m_state;
    godot::LocalVector<PhysicsProxy>& proxies = m_proxies;
    godot::LocalVector<PhysicsRope>& ropes = m_ropes;
    const godot::LocalVector<SolverJoint>& joints = m_solver_joints_scratch;
    const PhysicsSettings& settings = m_settings;


    godot::LocalVector<SolverBody>& bodies = state.bodies;
    bodies.clear();
    bodies.reserve(proxies.size());

    for (const PhysicsProxy& proxy : proxies) {
        bodies.push_back(make_solver_body(proxy));
    }

    // classify what each proxy presents to contact queries, everything after
    // this dispatches on the kind instead of poking at sprite pointers
    state.field_kinds.clear();
    state.field_kinds.reserve(proxies.size());

    for (int i = 0; i < static_cast<int>(proxies.size()); i++) {
        state.field_kinds.push_back(field_kind_of(proxies[i], state.proxy_shapes[i]));
    }

    for (PhysicsRope& rope : ropes) {
        vector_fill(rope.velocities, rope.positions.size(),  godot::Vector2(0.f, 0.f));
        vector_fill(rope.prev_positions, rope.positions.size(),  godot::Vector2(0.f, 0.f));
        vector_fill(rope.bias, rope.positions.size(),  godot::Vector2(0.f, 0.f));
    }

    find_pairs(proxies, bodies, state);
    gather_candidates(proxies, state.field_kinds, state.proxy_shapes, bodies, settings, delta_time, state);

    godot::LocalVector<ContactCandidate>& candidates = state.candidates;

    // sort so solve order stays deterministic across thread timing
    {

        std::sort(candidates.ptr(), candidates.ptr() + candidates.size(), [](const ContactCandidate& a, const ContactCandidate& b) {
            if (a.point_proxy != b.point_proxy) {
                return a.point_proxy < b.point_proxy;
            }

            if (a.field_proxy != b.field_proxy) {
                return a.field_proxy < b.field_proxy;
            }

            if (a.local_point.y != b.local_point.y) {
                return a.local_point.y < b.local_point.y;
            }

            return a.local_point.x < b.local_point.x;
        });
    }

    int proxy_count = static_cast<int>(proxies.size());
    int rope_count = static_cast<int>(ropes.size());

    // ropes touch the proxies whose extended boxes overlap theirs

    godot::LocalVector<godot::LocalVector<int>>& rope_touches = state.rope_touches;
    rope_touches.resize(rope_count);

    for (auto& touches : rope_touches) {
        touches.clear();
    }

    for (int rope_index = 0; rope_index < rope_count; rope_index++) {
        const PhysicsRope& rope = ropes[rope_index];

        if (rope.positions.is_empty()) {
            continue;
        }

        AxisAlignedBox rope_box(rope.positions.ptr(), static_cast<int>(rope.positions.size()));
        rope_box.min -= godot::Vector2(rope.segment_rest_length, rope.segment_rest_length);
        rope_box.max += godot::Vector2(rope.segment_rest_length, rope.segment_rest_length);

        for (int proxy_index = 0; proxy_index < proxy_count; proxy_index++) {
            bool anchored = rope.anchor_a.proxy_index == proxy_index || rope.anchor_b.proxy_index == proxy_index;

            if (anchored || rope_box.intersects_box(proxies[proxy_index].extended_box)) {
                rope_touches[rope_index].push_back(proxy_index);
            }
        }
    }

    // islands

    state.uf.reset(proxy_count + rope_count);
    UnionFindFixed& uf = state.uf;

    for (const ProxyPair& pair : state.pairs) {
        if (bodies[pair.proxy_0].moves && bodies[pair.proxy_1].moves) {
            uf.merge(pair.proxy_0, pair.proxy_1);
        }
    }

    // a joint writes both bodies, they must solve on one thread

    for (const SolverJoint& joint : joints) {
        if (bodies[joint.proxy_0].moves && bodies[joint.proxy_1].moves) {
            uf.merge(joint.proxy_0, joint.proxy_1);
        }
    }

    for (int rope_index = 0; rope_index < rope_count; rope_index++) {
        for (int proxy_index : rope_touches[rope_index]) {
            if (bodies[proxy_index].moves) {
                uf.merge(proxy_count + rope_index, proxy_index);
            }
        }
    }

    for (int i = 0; i < rope_count; i++) {
        const PhysicsRope& rope = ropes[i];

        if (rope.anchor_a.rope_index >= 0 && rope.anchor_a.rope_index < rope_count) {
            uf.merge(proxy_count + i, proxy_count + rope.anchor_a.rope_index);
        }

        if (rope.anchor_b.rope_index >= 0 && rope.anchor_b.rope_index < rope_count) {
            uf.merge(proxy_count + i, proxy_count + rope.anchor_b.rope_index);
        }
    }

    vector_fill(state.island_of, proxy_count + rope_count,  -1);
    state.islands_used = 0;

    auto island_index = [&](int node) {
        int root = uf.find(node);

        if (state.island_of[root] == -1) {
            state.island_of[root] = state.islands_used;
            state_take_island(state);
        }

        return state.island_of[root];
    };

    for (int i = 0; i < proxy_count; i++) {
        if (bodies[i].moves) {
            state.islands[island_index(i)].body_indices.push_back(i);
        }
    }

    for (int i = 0; i < rope_count; i++) {
        state.islands[island_index(proxy_count + i)].rope_indices.push_back(i);
    }

    for (int i = 0; i < static_cast<int>(candidates.size()); i++) {
        const ContactCandidate& c = candidates[i];

        int dynamic_side = bodies[c.point_proxy].moves ? c.point_proxy : c.field_proxy;
        state.islands[island_index(dynamic_side)].candidate_indices.push_back(i);
    }

    for (int i = 0; i < static_cast<int>(joints.size()); i++) {
        const SolverJoint& joint = joints[i];

        if (!bodies[joint.proxy_0].moves && !bodies[joint.proxy_1].moves) {
            continue;
        }

        int dynamic_side = bodies[joint.proxy_0].moves ? joint.proxy_0 : joint.proxy_1;
        state.islands[island_index(dynamic_side)].joint_indices.push_back(i);
    }

    parallel_for(0, state.islands_used, [&](size_t i) {
        solve_island(proxies, state.field_kinds, state.proxy_shapes, bodies, candidates, ropes, rope_touches, joints, state.islands[i], settings, delta_time);
    });

    // one event per touching pair, the deepest point speaks for the manifold

    for (size_t i = 0; i < candidates.size();) {
        size_t end = i;

        const ContactCandidate* best = nullptr;
        float approach = 0.f;
        float tangent = 0.f;

        while (end < candidates.size()
            && candidates[end].point_proxy == candidates[i].point_proxy
            && candidates[end].field_proxy == candidates[i].field_proxy) {
            const ContactCandidate& c = candidates[end];

            if (c.active || c.impulse_n > 0.f) {
                if (!best || c.depth > best->depth) {
                    best = &c;
                }

                approach = std::max(approach, -c.vn_rest);
                tangent = std::max(tangent, c.vt_rest);
            }

            end += 1;
        }

        if (best) {
            const SolverBody& pb = bodies[best->point_proxy];
            const SolverBody& fb = bodies[best->field_proxy];

            godot::Vector2 world = body_point_world(pb, best->local_point);

            PhysicsContact contact;
            contact.entity_0 = proxies[best->point_proxy].entity;
            contact.entity_1 = proxies[best->field_proxy].entity;
            contact.world_point = world;
            contact.normal = best->normal;
            contact.local_point_0 = best->local_point;
            contact.local_point_1 = body_world_to_local(fb, world);
            contact.depth = best->depth;
            contact.approach_speed = std::max(approach, 0.f);
            contact.tangent_speed = tangent;

            m_contacts.push_back(contact);
        }

        i = end;
    }

    IF_DEBUG {
        for (int i = 0; i < proxy_count; i++) {
            debug_render_fixed().axis_aligned_box(proxies[i].extended_box, DebugName_Physics_Broadphase_Overlap_World_Bounds);

            const SolverBody& b = bodies[i];

            if (proxies[i].sprite) {
                const Grid& grid = proxies[i].sprite->grid();

                for (const SpriteChunk* chunk : proxies[i].sprite->chunks().items()) {
                    for (const auto& [cell_pos, cell_index] : chunk->surface) {
                        godot::Vector2 local = grid.to_local_point_centered(chunk->gridPixelOffset + cell_pos);
                        debug_render_fixed().circle(body_point_world(b, local), 0.25f * b.cell_world, DebugName_Physics_Surface_Point);
                    }
                }
            }
        }

        for (const ProxyPair& pair : state.pairs) {
            debug_render_fixed().line(bodies[pair.proxy_0].com, bodies[pair.proxy_1].com, DebugName_Physics_Broadphase_Overlap_World_Pair_Line);
        }

        for (const ContactCandidate& c : candidates) {
            if (!c.active && c.impulse_n <= 0.f) {
                continue;
            }

            godot::Vector2 world = body_point_world(bodies[c.point_proxy], c.local_point);

            debug_render_fixed().circle(world, c.radius, DebugName_Physics_Contact_Point);
            debug_render_fixed().ray(world, c.normal * c.radius * 4.f, DebugName_Physics_Contact_Point_Normal);
        }
    }

    // write back

    for (int i = 0; i < proxy_count; i++) {
        const SolverBody& b = bodies[i];
        PhysicsBody& body = *proxies[i].body;

        if (body.inv_mass <= 0.f && !b.moves) {
            continue;
        }

        body.last_position = body.position;
        body.last_angle = body.angle;

        float linear_decay = 1.f / (1.f + delta_time * body.linear_damping);
        float angular_decay = 1.f / (1.f + delta_time * body.angular_damping);

        body.position = b.com - rotate_local_point(b.com_scaled, b.angle);
        body.angle = b.angle;
        body.linear_velocity = b.linear_velocity * linear_decay;
        body.angular_velocity = b.angular_velocity * angular_decay;
    }


    m_proxies.clear();
    m_shapes.clear();
}
