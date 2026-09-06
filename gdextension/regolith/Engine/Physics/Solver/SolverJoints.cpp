#include "SolverInternal.h"

#include <cmath>

// joints, solved like rope attaches so momentum carries through

static void solve_joint_axis(SolverBody& b0, SolverBody& b1, vec2 p0, vec2 p1, vec2 n, float c) {
    vec2 r_0 = p0 - b0.com;
    vec2 r_1 = p1 - b1.com;

    float w = body_inverse_mass_at(b0, r_0, n) + body_inverse_mass_at(b1, r_1, n);

    if (w <= 0.f) {
        return;
    }

    float lambda = c / w;

    body_apply_correction(b0, n * lambda, r_0);
    body_apply_correction(b1, n * -lambda, r_1);
}

void solve_joint(std::vector<SolverBody>& bodies, const SolverJoint& joint) {
    SolverBody& b0 = bodies.at(joint.proxy_0);
    SolverBody& b1 = bodies.at(joint.proxy_1);

    if (joint.type == PhysicsWorldJointType_Pin) {
        // one axis at a time, the error is re derived so rotation from the
        // first axis feeds the second
        vec2 axes[2] = {vec2(1.f, 0.f), vec2(0.f, 1.f)};

        for (const vec2& axis : axes) {
            vec2 p0 = body_point_world(b0, joint.local_0);
            vec2 p1 = body_point_world(b1, joint.local_1);

            float c = dot(p1 - p0, axis);

            if (fabsf(c) < 1e-9f) {
                continue;
            }

            solve_joint_axis(b0, b1, p0, p1, axis, c);
        }

        return;
    }

    vec2 p0 = body_point_world(b0, joint.local_0);
    vec2 p1 = body_point_world(b1, joint.local_1);

    auto [n, len] = safe_normalize_distance(p1 - p0);

    if (len < 1e-9f) {
        return;
    }

    if (joint.type == PhysicsWorldJointType_Distance && len <= joint.distance) {
        return;
    }

    if (joint.type == PhysicsWorldJointType_PushDistance && len >= joint.distance) {
        return;
    }

    solve_joint_axis(b0, b1, p0, p1, n, len - joint.distance);
}
