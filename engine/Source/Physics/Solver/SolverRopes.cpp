#include <algorithm>
#include "SolverInternal.h"

#include "DestructibleSprite/Algorithm/SpriteDistanceField.h"

#include "DebugLineList.h"

PhysicsRope physics_create_rope(godot::Vector2 world_a, godot::Vector2 world_b, int node_count, float slack) {
    PhysicsRope rope;

    node_count = std::max(node_count, 2);

    for (int i = 0; i < node_count; i++) {
        float t = i / static_cast<float>(node_count - 1);
        rope.positions.push_back(((world_a) * (1.f - (t)) + (world_b) * (t)));
        rope.velocities.push_back(godot::Vector2(0.f, 0.f));
        rope.prev_positions.push_back(rope.positions[rope.positions.size() - 1]);
    }

    rope.segment_rest_length = (world_a).distance_to(world_b) * slack / (node_count - 1);

    return rope;
}

void solve_rope_attach(godot::LocalVector<SolverBody>& bodies, PhysicsRope& rope, const PhysicsRopeAnchor& anchor,
                       int particle) {
    if (anchor.proxy_index < 0) {
        return;
    }

    SolverBody& b = bodies[anchor.proxy_index];

    bool one_way = anchor.proxy_index == rope.owner_proxy && !rope.externally_pushed;

    godot::Vector2 target = body_point_world(b, anchor.local_point);
    godot::Vector2 p = rope.positions[particle];

    auto [n, c] = safe_normalize_distance(p - target);

    if (c < 1e-9f) {
        return;
    }

    godot::Vector2 r = target - b.com;

    float w_particle = rope.node_inv_mass;
    float w_body = one_way ? 0.f : body_inverse_mass_at(b, r, n);
    float w = w_particle + w_body;

    if (w <= 0.f) {
        return;
    }

    float lambda = c / w;

    rope.positions[particle] -= n * (lambda * w_particle);

    if (!one_way) {
        body_apply_correction(b, n * lambda, r);
    }
}

static float rope_segment_rest(const PhysicsRope& rope, size_t i) {
    return rope.rest_lengths.is_empty() ? rope.segment_rest_length : rope.rest_lengths[i];
}

static float rope_total_rest(const PhysicsRope& rope) {
    if (rope.rest_lengths.is_empty()) {
        return rope.segment_rest_length * (static_cast<int>(rope.positions.size()) - 1);
    }

    float total = 0.f;

    for (float rest : rope.rest_lengths) {
        total += rest;
    }

    return total;
}

void solve_rope_pin_to_rope(godot::LocalVector<PhysicsRope>& ropes, PhysicsRope& rope,
                            const PhysicsRopeAnchor& anchor, int particle) {
    if (anchor.rope_index < 0 || anchor.rope_index >= static_cast<int>(ropes.size())) {
        return;
    }

    PhysicsRope& other = ropes[anchor.rope_index];

    if (other.positions.is_empty()) {
        return;
    }

    int node = clamp(anchor.node_index, 0, static_cast<int>(other.positions.size()) - 1);

    godot::Vector2 p = rope.positions[particle];
    godot::Vector2 q = other.positions[node];

    auto [n, c] = safe_normalize_distance(p - q);

    if (c < 1e-9f) {
        return;
    }

    float w_p = rope.node_inv_mass;
    float w_q = other.node_inv_mass;
    float w = w_p + w_q;

    if (w <= 0.f) {
        return;
    }

    float lambda = c / w;

    rope.positions[particle] -= n * (lambda * w_p);
    other.positions[node] += n * (lambda * w_q);
}

void solve_rope_long_range(godot::LocalVector<SolverBody>& bodies, PhysicsRope& rope) {
    if (rope.anchor_a.proxy_index < 0 || rope.anchor_b.proxy_index < 0) {
        return;
    }

    SolverBody& ba = bodies[rope.anchor_a.proxy_index];
    SolverBody& bb = bodies[rope.anchor_b.proxy_index];

    godot::Vector2 pa = body_point_world(ba, rope.anchor_a.local_point);
    godot::Vector2 pb = body_point_world(bb, rope.anchor_b.local_point);

    float total_rest = rope_total_rest(rope);

    auto [n, len] = safe_normalize_distance(pb - pa);

    if (len <= total_rest) {
        return;
    }

    float c = len - total_rest;

    godot::Vector2 r_a = pa - ba.com;
    godot::Vector2 r_b = pb - bb.com;

    bool one_way_a = rope.anchor_a.proxy_index == rope.owner_proxy && !rope.externally_pushed;
    bool one_way_b = rope.anchor_b.proxy_index == rope.owner_proxy && !rope.externally_pushed;

    float w_a = one_way_a ? 0.f : body_inverse_mass_at(ba, r_a, n);
    float w_b = one_way_b ? 0.f : body_inverse_mass_at(bb, r_b, n);
    float w = w_a + w_b;

    if (w <= 0.f) {
        return;
    }

    float lambda = c / w;

    if (!one_way_a) {
        body_apply_correction(ba, n * lambda, r_a);
    }

    if (!one_way_b) {
        body_apply_correction(bb, n * -lambda, r_b);
    }
}

void solve_rope_segments(PhysicsRope& rope, float compliance, float min_length_factor, float substep_time) {
    float alpha = compliance / (substep_time * substep_time);

    for (size_t i = 0; i + 1 < rope.positions.size(); i++) {
        godot::Vector2 d = rope.positions[i + 1] - rope.positions[i];

        auto [n, len] = safe_normalize_distance(d);

        float rest = rope_segment_rest(rope, i);
        float min_len = rest * min_length_factor;

        float c;

        if (len > rest) {
            c = len - rest;
        }

        else if (len < min_len) {
            c = len - min_len;
        }

        else {
            continue;
        }

        float w = rope.node_inv_mass * 2.f + alpha;

        if (w <= 0.f) {
            continue;
        }

        float lambda = c / w;

        rope.positions[i] += n * (lambda * rope.node_inv_mass);
        rope.positions[i + 1] -= n * (lambda * rope.node_inv_mass);
    }
}

void solve_rope_shape(const godot::LocalVector<SolverBody>& bodies, PhysicsRope& rope, float stiffness) {
    int n = static_cast<int>(rope.positions.size());

    if (stiffness <= 0.f || static_cast<int>(rope.rest_locals.size()) != n) {
        return;
    }

    if (rope.owner_proxy < 0 || rope.owner_proxy >= static_cast<int>(bodies.size())) {
        return;
    }

    const SolverBody& ob = bodies[rope.owner_proxy];

    for (int i = 0; i < n; i++) {
        godot::Vector2 aim = body_point_world(ob, rope.rest_locals[i]);
        godot::Vector2 delta = (aim - rope.positions[i]) * stiffness;

        rope.positions[i] += delta;
        rope.bias[i] += delta;
    }
}

static bool rope_particle_skips_proxy(const PhysicsRope& rope, int particle, int proxy_index) {
    int last = static_cast<int>(rope.positions.size()) - 1;

    if (rope.anchor_a.proxy_index == proxy_index && particle <= 1) {
        return true;
    }

    if (rope.anchor_b.proxy_index == proxy_index && particle >= last - 1) {
        return true;
    }

    return false;
}

void solve_rope_collision(const godot::LocalVector<PhysicsProxy>& proxies, godot::LocalVector<SolverBody>& bodies,
                          PhysicsRope& rope, int proxy_index, float max_depenetration_cells) {
    const PhysicsProxy& proxy = proxies[proxy_index];

    if (!proxy.sprite) {
        return;
    }

    SolverBody& fb = bodies[proxy_index];

    bool one_way = proxy_index == rope.owner_proxy && !rope.externally_pushed;

    float radius = rope.radius > 0.f ? rope.radius : 0.5f * fb.cell_world;

    int count = static_cast<int>(rope.positions.size());

    for (int i = 0; i + 1 < count; i++) {
        bool skip_a = rope_particle_skips_proxy(rope, i, proxy_index);
        bool skip_b = rope_particle_skips_proxy(rope, i + 1, proxy_index);

        if (skip_a && skip_b) {
            continue;
        }

        AxisAlignedBox segment_box(rope.positions[i], rope.positions[i + 1]);
        segment_box.min -= godot::Vector2(radius, radius);
        segment_box.max += godot::Vector2(radius, radius);

        if (!segment_box.intersects_box(proxy.extended_box)) {
            continue;
        }

        float t_min = skip_a ? 0.5f : 0.f;
        float t_max = skip_b ? 0.5f : 1.f;

        float seg_len = (rope.positions[i]).distance_to(rope.positions[i + 1]);
        int steps = std::max(1, static_cast<int>(seg_len * (t_max - t_min) / fb.cell_world) + 1);

        int s_end = (i + 2 < count && !skip_b) ? steps - 1 : steps;

        float deepest = 0.f;
        godot::Vector2 deepest_normal = godot::Vector2(0.f, 0.f);
        godot::Vector2 deepest_point = godot::Vector2(0.f, 0.f);
        float deepest_t = 0.f;

        for (int s = 0; s <= s_end; s++) {
            float t = (t_min) * (1.f - (s / static_cast<float>(steps))) + (t_max) * (s / static_cast<float>(steps));

            godot::Vector2 p = ((rope.positions[i]) * (1.f - (t)) + (rope.positions[i + 1]) * (t));
            godot::Vector2 grid = body_world_to_grid(fb, p);

            float separation = sprite_distance_field_sample(*proxy.sprite, grid) * fb.cell_world - radius;

            if (separation >= 0.f) {
                continue;
            }

            separation = std::max(separation, -max_depenetration_cells * fb.cell_world);

            if (!one_way) {
                rope.externally_pushed = true;
            }

            godot::Vector2 normal = contact_normal(proxy, fb, grid, p);
            godot::Vector2 r = p - fb.com;

            float w_a = skip_a ? 0.f : rope.node_inv_mass * (1.f - t) * (1.f - t);
            float w_b = skip_b ? 0.f : rope.node_inv_mass * t * t;
            float w_body = one_way ? 0.f : body_inverse_mass_at(fb, r, normal);
            float w = w_a + w_b + w_body;

            if (w <= 0.f) {
                continue;
            }

            float lambda = -separation / w;

            debug_render_fixed().circle(p, radius * 0.5f, DebugName_Physics_Contact_Point);
            debug_render_fixed().ray(p, normal * -separation, DebugName_Physics_Contact_Point_Normal);

            if (!skip_a) {
                godot::Vector2 delta = normal * (lambda * rope.node_inv_mass * (1.f - t));

                rope.positions[i] += delta;
                rope.bias[i] += delta;
            }

            if (!skip_b) {
                godot::Vector2 delta = normal * (lambda * rope.node_inv_mass * t);

                rope.positions[i + 1] += delta;
                rope.bias[i + 1] += delta;
            }

            if (!one_way) {
                body_apply_bias_correction(fb, normal * -lambda, r);
            }

            if (separation < deepest) {
                deepest = separation;
                deepest_normal = normal;
                deepest_point = p;
                deepest_t = t;
            }
        }

        // one velocity contact per segment. the position pass samples at cell
        // resolution, feeding every sample to the velocity solve would let a
        // long segment hit the body far harder than a short one

        if (deepest < 0.f) {
            rope.contacts.push_back(PhysicsRopeContact {
                .proxy_index = proxy_index,
                .node_a = skip_a ? -1 : i,
                .node_b = skip_b ? -1 : i + 1,
                .weight_a = 1.f - deepest_t,
                .weight_b = deepest_t,
                .normal = deepest_normal,
                .point = deepest_point,
                .one_way = one_way,
            });
        }
    }
}

void solve_rope_contact_velocity(godot::LocalVector<SolverBody>& bodies, PhysicsRope& rope) {
    for (const PhysicsRopeContact& contact : rope.contacts) {
        SolverBody& fb = bodies[contact.proxy_index];

        float w_a = contact.node_a >= 0 ? contact.weight_a : 0.f;
        float w_b = contact.node_b >= 0 ? contact.weight_b : 0.f;

        godot::Vector2 rope_velocity = godot::Vector2(0.f, 0.f);

        if (contact.node_a >= 0) {
            rope_velocity += rope.velocities[contact.node_a] * w_a;
        }

        if (contact.node_b >= 0) {
            rope_velocity += rope.velocities[contact.node_b] * w_b;
        }

        godot::Vector2 r = contact.point - fb.com;
        godot::Vector2 relative = rope_velocity - body_velocity_at(fb, r);

        float vn = (relative).dot(contact.normal);

        if (vn >= 0.f) {
            continue;
        }

        float w_rope = rope.node_inv_mass * (w_a * w_a + w_b * w_b);
        float w_body = contact.one_way ? 0.f : body_inverse_mass_at(fb, r, contact.normal);
        float w = w_rope + w_body;

        if (w <= 0.f) {
            continue;
        }

        float impulse = -vn / w;

        if (contact.node_a >= 0) {
            rope.velocities[contact.node_a] += contact.normal * (impulse * rope.node_inv_mass * w_a);
        }

        if (contact.node_b >= 0) {
            rope.velocities[contact.node_b] += contact.normal * (impulse * rope.node_inv_mass * w_b);
        }

        if (!contact.one_way) {
            body_apply_velocity(fb, contact.normal * -impulse, r);
        }
    }
}

static bool rope_rope_segments_tied(const PhysicsRope& ra, int i, int index_b, int j, int count_a) {
    const PhysicsRopeAnchor* anchors[2] = {&ra.anchor_a, &ra.anchor_b};
    int ends[2] = {0, count_a - 2};

    for (int k = 0; k < 2; k++) {
        if (anchors[k]->rope_index != index_b) {
            continue;
        }

        if (abs(i - ends[k]) <= 1 && abs(j - anchors[k]->node_index) <= 1) {
            return true;
        }
    }

    return false;
}

void solve_rope_rope_collision(godot::LocalVector<PhysicsRope>& ropes, int index_a, int index_b) {
    PhysicsRope& ra = ropes[index_a];
    PhysicsRope& rb = ropes[index_b];

    if (ra.radius <= 0.f || rb.radius <= 0.f) {
        return;
    }

    float sum_radius = ra.radius + rb.radius;
    bool self = index_a == index_b;

    int count_a = static_cast<int>(ra.positions.size());
    int count_b = static_cast<int>(rb.positions.size());

    if (!self) {
        AxisAlignedBox box_a(ra.positions.ptr(), count_a);
        AxisAlignedBox box_b(rb.positions.ptr(), count_b);

        box_a.min -= godot::Vector2(sum_radius, sum_radius);
        box_a.max += godot::Vector2(sum_radius, sum_radius);

        if (!box_a.intersects_box(box_b)) {
            return;
        }
    }

    bool maybe_tied = !self
        && (ra.anchor_a.rope_index == index_b || ra.anchor_b.rope_index == index_b
         || rb.anchor_a.rope_index == index_a || rb.anchor_b.rope_index == index_a);

    for (int i = 0; i + 1 < count_a; i++) {
        int j_begin = self ? i + 2 : 0;

        for (int j = j_begin; j + 1 < count_b; j++) {
            if (maybe_tied) {
                if (rope_rope_segments_tied(ra, i, index_b, j, count_a) || rope_rope_segments_tied(rb, j, index_a, i, count_b)) {
                    continue;
                }
            }

            float s, t;
            closest_segment_segment(ra.positions[i], ra.positions[i + 1], rb.positions[j], rb.positions[j + 1], &s, &t);

            godot::Vector2 pa = ((ra.positions[i]) * (1.f - (s)) + (ra.positions[i + 1]) * (s));
            godot::Vector2 pb = ((rb.positions[j]) * (1.f - (t)) + (rb.positions[j + 1]) * (t));

            auto [n, dist] = safe_normalize_distance(pa - pb);

            float depth = sum_radius - dist;

            if (depth <= 0.f) {
                continue;
            }

            if (ra.owner_proxy != rb.owner_proxy) {
                ra.externally_pushed = true;
                rb.externally_pushed = true;
            }

            if (dist < 1e-6f) {
                n = godot::Vector2(0.f, 1.f);
            }

            float w_a = ra.node_inv_mass * ((1.f - s) * (1.f - s) + s * s);
            float w_b = rb.node_inv_mass * ((1.f - t) * (1.f - t) + t * t);
            float w = w_a + w_b;

            if (w <= 0.f) {
                continue;
            }

            float lambda = depth / w;

            ra.positions[i] += n * (lambda * ra.node_inv_mass * (1.f - s));
            ra.positions[i + 1] += n * (lambda * ra.node_inv_mass * s);
            rb.positions[j] -= n * (lambda * rb.node_inv_mass * (1.f - t));
            rb.positions[j + 1] -= n * (lambda * rb.node_inv_mass * t);
        }
    }
}
