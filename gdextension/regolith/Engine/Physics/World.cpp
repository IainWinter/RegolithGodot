#include "World.h"
#include "Physics/Solver/SolverInternal.h"


#include <algorithm>
#include <cassert>
#include <cmath>

PhysicsWorld::PhysicsWorld()
    : m_state(std::make_unique<PhysicsSolverState>()) {}

PhysicsWorld::~PhysicsWorld() = default;

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

std::vector<PhysicsProxy>& PhysicsWorld::proxies() {
    return m_proxies;
}

std::vector<PhysicsShapeEntry>& PhysicsWorld::shapes() {
    return m_shapes;
}

std::vector<PhysicsRope>& PhysicsWorld::ropes() {
    return m_ropes;
}

const std::vector<PhysicsContact>& PhysicsWorld::contacts() const {
    return m_contacts;
}

const std::vector<std::pair<godot::ObjectID, godot::ObjectID>>& PhysicsWorld::overlaps() const {
    return m_state->lowering_overlaps;
}

// scale drives the solver's cell size for margins and depenetration caps,
// shapes have no grid so keep it near the shape's own size
static vec2 shape_proxy_scale(float radius) {
    return vec2(glm::max(radius, 0.25f));
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
    b.bound_radius = length(proxy.scale) + 1e-3f;

    if (proxy.sprite) {
        b.cells = vec2(proxy.sprite->grid().cells);
        b.inv_inertia /= proxy.scale.x * proxy.scale.y;
    }

    else {
        b.cells = vec2(1.f);
    }

    // sdf sampling uses a scalar cell size, so the world cell must be square.
    // scale may be non-uniform (a wide sprite has more chunks across) as long
    // as scale/cells stays equal per axis, which keeps each cell square
    vec2 world_cell = proxy.scale * 2.f / b.cells;
    assert(fabsf(world_cell.x - world_cell.y) < 1e-4f && "PhysicsBody requires square world cells");

    b.cell_world = world_cell.x;

    bool still = length(body.linear_velocity) < 1e-9f && fabsf(body.angular_velocity) < 1e-9f;
    b.moves = body.inv_mass > 0.f || !still;

    b.bias_com = vec2(0.f);
    b.bias_angle = 0.f;

    return b;
}

static Island& state_take_island(PhysicsSolverState& state) {
    if (state.islands_used >= static_cast<int>(state.islands.size())) {
        state.islands.emplace_back();
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
        [[maybe_unused]] bool inserted = m_proxy_lookup_scratch.emplace(m_proxies[i].body, i).second;
        assert(inserted && "duplicate PhysicsBody* in PhysicsWorld::solve proxies");
    }

    // the shape collection. attach each collider to the proxy holding the
    // same body and fill the shape driven parts of the proxy contract:
    // uniform scale for square cells and a broadphase box covering the shape

    m_state->proxy_shapes.assign(m_proxies.size(), nullptr);

    for (PhysicsShapeEntry& entry : m_shapes) {
        Collider& collider = entry.collider;

        if (!collider.enabled || collider.shape == ColliderShape::None) {
            continue;
        }

        auto it = m_proxy_lookup_scratch.find(entry.body);

        if (it == m_proxy_lookup_scratch.end()) {
            continue;
        }

        int index = it->second;
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

                AxisAlignedBox box(body.position - vec2(collider.radius), body.position + vec2(collider.radius));
                proxy.extended_box = box.extend_box(body.linear_velocity * delta_time, 0.f);
                break;
            }

            case ColliderShape::Capsule: {
                collider.capsule_direction = safe_normalize(collider.capsule_direction);
                proxy.scale = shape_proxy_scale(collider.radius);

                vec2 axis = rotate_local_point(collider.capsule_direction, body.angle) * collider.capsule_half_length;
                vec2 points[2] = { body.position - axis, body.position + axis };

                AxisAlignedBox box(points, 2);
                box.min -= vec2(collider.radius);
                box.max += vec2(collider.radius);
                proxy.extended_box = box.extend_box(body.linear_velocity * delta_time, 0.f);
                break;
            }

            case ColliderShape::Plane: {
                // normal normalized here, d stays raw, the old iw convention.
                // planes are infinite so they always pass the broadphase
                collider.plane_normal = safe_normalize(collider.plane_normal);
                proxy.scale = vec2(0.5f);
                proxy.extended_box = AxisAlignedBox(vec2(-1e9f), vec2(1e9f));
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

        m_solver_joints_scratch.push_back({it_0->second, it_1->second, joint.local_0, joint.local_1, joint.type, joint.distance});
    }

    m_joints.clear();
    m_contacts.clear();

    PhysicsSolverState& state = *m_state;
    std::vector<PhysicsProxy>& proxies = m_proxies;
    std::vector<PhysicsRope>& ropes = m_ropes;
    const std::vector<SolverJoint>& joints = m_solver_joints_scratch;
    const PhysicsSettings& settings = m_settings;


    std::vector<SolverBody>& bodies = state.bodies;
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
        rope.velocities.resize(rope.positions.size(), vec2(0.f));
        rope.prev_positions.resize(rope.positions.size(), vec2(0.f));
        rope.bias.resize(rope.positions.size(), vec2(0.f));
    }

    find_pairs(proxies, bodies, state);
    gather_candidates(proxies, state.field_kinds, state.proxy_shapes, bodies, settings, delta_time, state);

    std::vector<ContactCandidate>& candidates = state.candidates;

    // sort so solve order stays deterministic across thread timing
    {

        std::sort(candidates.begin(), candidates.end(), [](const ContactCandidate& a, const ContactCandidate& b) {
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

    std::vector<std::vector<int>>& rope_touches = state.rope_touches;
    rope_touches.resize(rope_count);

    for (auto& touches : rope_touches) {
        touches.clear();
    }

    for (int rope_index = 0; rope_index < rope_count; rope_index++) {
        const PhysicsRope& rope = ropes.at(rope_index);

        if (rope.positions.empty()) {
            continue;
        }

        AxisAlignedBox rope_box(rope.positions.data(), static_cast<int>(rope.positions.size()));
        rope_box.min -= vec2(rope.segment_rest_length);
        rope_box.max += vec2(rope.segment_rest_length);

        for (int proxy_index = 0; proxy_index < proxy_count; proxy_index++) {
            bool anchored = rope.anchor_a.proxy_index == proxy_index || rope.anchor_b.proxy_index == proxy_index;

            if (anchored || rope_box.intersects_box(proxies.at(proxy_index).extended_box)) {
                rope_touches[rope_index].push_back(proxy_index);
            }
        }
    }

    // islands

    state.uf.reset(proxy_count + rope_count);
    UnionFindFixed& uf = state.uf;

    for (const ProxyPair& pair : state.pairs) {
        if (bodies.at(pair.proxy_0).moves && bodies.at(pair.proxy_1).moves) {
            uf.merge(pair.proxy_0, pair.proxy_1);
        }
    }

    // a joint writes both bodies, they must solve on one thread

    for (const SolverJoint& joint : joints) {
        if (bodies.at(joint.proxy_0).moves && bodies.at(joint.proxy_1).moves) {
            uf.merge(joint.proxy_0, joint.proxy_1);
        }
    }

    for (int rope_index = 0; rope_index < rope_count; rope_index++) {
        for (int proxy_index : rope_touches[rope_index]) {
            if (bodies.at(proxy_index).moves) {
                uf.merge(proxy_count + rope_index, proxy_index);
            }
        }
    }

    for (int i = 0; i < rope_count; i++) {
        const PhysicsRope& rope = ropes.at(i);

        if (rope.anchor_a.rope_index >= 0 && rope.anchor_a.rope_index < rope_count) {
            uf.merge(proxy_count + i, proxy_count + rope.anchor_a.rope_index);
        }

        if (rope.anchor_b.rope_index >= 0 && rope.anchor_b.rope_index < rope_count) {
            uf.merge(proxy_count + i, proxy_count + rope.anchor_b.rope_index);
        }
    }

    state.island_of.assign(proxy_count + rope_count, -1);
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
        if (bodies.at(i).moves) {
            state.islands[island_index(i)].body_indices.push_back(i);
        }
    }

    for (int i = 0; i < rope_count; i++) {
        state.islands[island_index(proxy_count + i)].rope_indices.push_back(i);
    }

    for (int i = 0; i < static_cast<int>(candidates.size()); i++) {
        const ContactCandidate& c = candidates.at(i);

        int dynamic_side = bodies.at(c.point_proxy).moves ? c.point_proxy : c.field_proxy;
        state.islands[island_index(dynamic_side)].candidate_indices.push_back(i);
    }

    for (int i = 0; i < static_cast<int>(joints.size()); i++) {
        const SolverJoint& joint = joints.at(i);

        if (!bodies.at(joint.proxy_0).moves && !bodies.at(joint.proxy_1).moves) {
            continue;
        }

        int dynamic_side = bodies.at(joint.proxy_0).moves ? joint.proxy_0 : joint.proxy_1;
        state.islands[island_index(dynamic_side)].joint_indices.push_back(i);
    }

    parallel_for(0, state.islands_used, [&](size_t i) {
        solve_island(proxies, state.field_kinds, state.proxy_shapes, bodies, candidates, ropes, rope_touches, joints, state.islands.at(i), settings, delta_time);
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

                approach = glm::max(approach, -c.vn_rest);
                tangent = glm::max(tangent, c.vt_rest);
            }

            end += 1;
        }

        if (best) {
            const SolverBody& pb = bodies.at(best->point_proxy);
            const SolverBody& fb = bodies.at(best->field_proxy);

            vec2 world = body_point_world(pb, best->local_point);

            PhysicsContact contact;
            contact.entity_0 = proxies.at(best->point_proxy).entity;
            contact.entity_1 = proxies.at(best->field_proxy).entity;
            contact.world_point = world;
            contact.normal = best->normal;
            contact.local_point_0 = best->local_point;
            contact.local_point_1 = body_world_to_local(fb, world);
            contact.depth = best->depth;
            contact.approach_speed = glm::max(approach, 0.f);
            contact.tangent_speed = tangent;

            m_contacts.push_back(contact);
        }

        i = end;
    }

    IF_DEBUG {
        for (int i = 0; i < proxy_count; i++) {
            debug_render_fixed().axis_aligned_box(proxies.at(i).extended_box, DebugName_Physics_Broadphase_Overlap_World_Bounds);

            const SolverBody& b = bodies.at(i);

            if (proxies.at(i).sprite) {
                const Grid& grid = proxies.at(i).sprite->grid();

                for (const SpriteChunk* chunk : proxies.at(i).sprite->chunks().items()) {
                    for (const auto& [cell_pos, cell_index] : chunk->surface) {
                        vec2 local = grid.to_local_point_centered(chunk->gridPixelOffset + cell_pos);
                        debug_render_fixed().circle(body_point_world(b, local), 0.25f * b.cell_world, DebugName_Physics_Surface_Point);
                    }
                }
            }
        }

        for (const ProxyPair& pair : state.pairs) {
            debug_render_fixed().line(bodies.at(pair.proxy_0).com, bodies.at(pair.proxy_1).com, DebugName_Physics_Broadphase_Overlap_World_Pair_Line);
        }

        for (const ContactCandidate& c : candidates) {
            if (!c.active && c.impulse_n <= 0.f) {
                continue;
            }

            vec2 world = body_point_world(bodies.at(c.point_proxy), c.local_point);

            debug_render_fixed().circle(world, c.radius, DebugName_Physics_Contact_Point);
            debug_render_fixed().ray(world, c.normal * c.radius * 4.f, DebugName_Physics_Contact_Point_Normal);
        }
    }

    // write back

    for (int i = 0; i < proxy_count; i++) {
        const SolverBody& b = bodies.at(i);
        PhysicsBody& body = *proxies.at(i).body;

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
