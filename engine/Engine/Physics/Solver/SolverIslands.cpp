#include "SolverInternal.h"


// island solve, the whole substep loop runs island local

void solve_island(const std::vector<PhysicsProxy>& proxies, const std::vector<FieldKind>& field_kinds,
                  const std::vector<const Collider*>& proxy_shapes, std::vector<SolverBody>& bodies,
                  std::vector<ContactCandidate>& candidates, std::vector<PhysicsRope>& ropes,
                  const std::vector<std::vector<int>>& rope_touches, const std::vector<SolverJoint>& joints,
                  const Island& island, const PhysicsSettings& settings, float delta_time) {

    float h = delta_time / glm::max(settings.substeps, 1);
    int position_iterations = glm::max(settings.position_iterations, 1);

    for (int substep = 0; substep < settings.substeps; substep++) {
        for (int body_index : island.body_indices) {
            SolverBody& b = bodies.at(body_index);

            b.prev_com = b.com;
            b.prev_angle = b.angle;
            b.bias_com = vec2(0.f);
            b.bias_angle = 0.f;

            if (b.inv_mass > 0.f) {
                b.linear_velocity += settings.gravity * h;
            }

            b.com += b.linear_velocity * h;
            b.angle += b.angular_velocity * h;
        }

        for (int rope_index : island.rope_indices) {
            PhysicsRope& rope = ropes.at(rope_index);

            for (size_t i = 0; i < rope.positions.size(); i++) {
                rope.prev_positions[i] = rope.positions[i];
                rope.bias[i] = vec2(0.f);
                rope.velocities[i] += settings.gravity * h;
                rope.positions[i] += rope.velocities[i] * h;
            }
        }

        for (int candidate_index : island.candidate_indices) {
            ContactCandidate& c = candidates.at(candidate_index);

            c.active = false;
            c.lambda_n = 0.f;
            c.impulse_n = 0.f;
            c.impulse_t = vec2(0.f);
        }

        for (int iteration = 0; iteration < position_iterations; iteration++) {
            for (int candidate_index : island.candidate_indices) {
                solve_contact_position(proxies, field_kinds, proxy_shapes, bodies, candidates.at(candidate_index), settings.friction, settings.max_depenetration_cells);
            }

            for (int joint_index : island.joint_indices) {
                solve_joint(bodies, joints.at(joint_index));
            }

            for (int rope_index : island.rope_indices) {
                PhysicsRope& rope = ropes.at(rope_index);

                solve_rope_long_range(bodies, rope);
                solve_rope_attach(bodies, rope, rope.anchor_a, 0);
                solve_rope_pin_to_rope(ropes, rope, rope.anchor_a, 0);
                solve_rope_segments(rope, settings.rope_stretch_compliance, settings.rope_min_length_factor, h);
                solve_rope_shape(bodies, rope, rope.shape_stiffness / (settings.substeps * position_iterations));
                solve_rope_attach(bodies, rope, rope.anchor_b, static_cast<int>(rope.positions.size()) - 1);
                solve_rope_pin_to_rope(ropes, rope, rope.anchor_b, static_cast<int>(rope.positions.size()) - 1);

                if (settings.rope_collide_sprites) {
                    rope.contacts.clear();

                    for (int proxy_index : rope_touches.at(rope_index)) {
                        solve_rope_collision(proxies, bodies, rope, proxy_index, settings.max_depenetration_cells);
                    }
                }
            }

            if (settings.rope_collide_ropes) {
                for (size_t a = 0; a < island.rope_indices.size(); a++) {
                    for (size_t b = a; b < island.rope_indices.size(); b++) {
                        solve_rope_rope_collision(ropes, island.rope_indices[a], island.rope_indices[b]);
                    }
                }
            }
        }

        for (int rope_index : island.rope_indices) {
            PhysicsRope& rope = ropes.at(rope_index);

            float rate = rope.damping >= 0.f ? rope.damping : settings.rope_damping;
            float decay = 1.f / (1.f + h * rate);

            for (size_t i = 0; i < rope.positions.size(); i++) {
                rope.velocities[i] = (rope.positions[i] - rope.prev_positions[i] - rope.bias[i]) / h * decay;
            }
        }

        for (int body_index : island.body_indices) {
            SolverBody& b = bodies.at(body_index);

            if (b.inv_mass <= 0.f) {
                continue;
            }

            b.linear_velocity = (b.com - b.bias_com - b.prev_com) / h;
            b.angular_velocity = (b.angle - b.bias_angle - b.prev_angle) / h;
        }

        for (int iteration = 0; iteration < glm::max(settings.velocity_iterations, 1); iteration++) {
            for (int candidate_index : island.candidate_indices) {
                solve_contact_velocity(bodies, candidates.at(candidate_index), settings, h);
            }

            for (int rope_index : island.rope_indices) {
                solve_rope_contact_velocity(bodies, ropes.at(rope_index));
            }
        }

        for (int candidate_index : island.candidate_indices) {
            solve_contact_restitution(bodies, candidates.at(candidate_index), settings);
        }
    }
}
