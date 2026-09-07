#include "SolverInternal.h"


// Bodies sharing a joint with different joint_level or collision_priority skip collision
static bool bodies_should_collide(const PhysicsBody& a, const PhysicsBody& b) {
    if (a.joint_level == b.joint_level && a.collision_priority == b.collision_priority) {
        return true;
    }

    for (const PhysicsJoint& ja : a.joints) {
        for (const PhysicsJoint& jb : b.joints) {
            if (ja.id == jb.id) {
                return false;
            }
        }
    }

    return true;
}

void find_pairs(const std::vector<PhysicsProxy>& proxies, const std::vector<SolverBody>& bodies,
                PhysicsSolverState& state) {

    state.pairs.clear();
    state.lowering_overlaps.clear();
    state.broadphase.clear();

    std::vector<int>& overlapping = state.broadphase_overlapping;

    for (int proxy_index = 0; proxy_index < static_cast<int>(proxies.size()); proxy_index++) {
        const PhysicsProxy& proxy = proxies.at(proxy_index);

        overlapping.clear();
        state.broadphase.query(proxy.extended_box, overlapping);

        for (const int& overlap_index : overlapping) {
            if (!bodies.at(proxy_index).moves && !bodies.at(overlap_index).moves) {
                continue;
            }

            const PhysicsProxy& other = proxies.at(overlap_index);

            // a body trying to lower its priority phases through everything it
            // overlaps, but the overlap is recorded so it can settle once clear
            if (proxy.body->attempt_lower_priority || other.body->attempt_lower_priority) {
                state.lowering_overlaps.push_back({proxy.entity, other.entity});
                continue;
            }

            if (!bodies_should_collide(*proxy.body, *other.body)) {
                continue;
            }

            state.pairs.push_back({proxy_index, overlap_index});
        }

        state.broadphase.insert(proxy.extended_box, proxy_index);
    }

    IF_DEBUG {
        debug_render_fixed().axis_aligned_area_tree(state.broadphase, DebugName_Physics_Broadphase_Tree);
    }
}
