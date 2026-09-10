#include <algorithm>
#include "SolverInternal.h"

#include "DestructibleSprite/Algorithm/SpriteDistanceField.h"


#include <cmath>

// flat gradient falls back to pushing away from the field body's com
godot::Vector2 contact_normal(const PhysicsProxy& proxy, const SolverBody& fb, godot::Vector2 grid, godot::Vector2 world) {
    godot::Vector2 g = sprite_distance_field_gradient(*proxy.sprite, grid);

    if ((g).dot(g) > 1e-12f) {
        return rotate_local_point(g, fb.angle);
    }

    godot::Vector2 n = safe_normalize(world - fb.com);

    if ((n).dot(n) < 1e-12f) {
        n = godot::Vector2(0.f, 1.f);
    }

    return n;
}

// ---------------------------------------------------------------------------
// fields. every collidable proxy is a field of one kind, classified once per
// solve, and every contact query goes through the same sample call

FieldKind field_kind_of(const PhysicsProxy& proxy, const Collider* shape) {
    if (proxy.sprite) {
        return FieldKind_Sprite;
    }

    if (!shape) {
        return FieldKind_None;
    }

    switch (shape->shape) {
        case ColliderShape::Circle: {
            return FieldKind_Circle;
        }

        case ColliderShape::Capsule: {
            return FieldKind_Capsule;
        }

        case ColliderShape::Plane: {
            return FieldKind_Plane;
        }

        default: {
            return FieldKind_None;
        }
    }
}

// signed distance from a world point to the field surface, and the surface
// normal there. the point's own radius is subtracted by the caller
FieldSample field_sample(const PhysicsProxy& fp, const Collider* shape, const SolverBody& fb, FieldKind kind, godot::Vector2 world) {
    switch (kind) {
        case FieldKind_Sprite: {
            godot::Vector2 grid = body_world_to_grid(fb, world);
            return { sprite_distance_field_sample(*fp.sprite, grid) * fb.cell_world, contact_normal(fp, fb, grid, world) };
        }

        case FieldKind_Circle: {
            godot::Vector2 d = world - fb.com;
            float dist = (d).length();
            godot::Vector2 n = dist > 1e-6f ? d / dist : godot::Vector2(0.f, 1.f);
            return { dist - shape->radius, n };
        }

        case FieldKind_Capsule: {
            godot::Vector2 axis = rotate_local_point(shape->capsule_direction, fb.angle) * shape->capsule_half_length;
            godot::Vector2 a = fb.com - axis;
            godot::Vector2 ab = axis * 2.f;

            float t = clamp((world - a).dot(ab) / std::max((ab).dot(ab), 1e-9f), 0.f, 1.f);
            godot::Vector2 closest = a + ab * t;

            godot::Vector2 d = world - closest;
            float dist = (d).length();
            godot::Vector2 n = dist > 1e-6f ? d / dist : godot::Vector2(0.f, 1.f);
            return { dist - shape->radius, n };
        }

        case FieldKind_Plane: {
            // normal normalized at the collection step, d raw, the old iw convention
            return { (shape->plane_normal).dot(world) - shape->plane_d, shape->plane_normal };
        }

        default: {
            return { 1e9f, godot::Vector2(0.f, 1.f) };
        }
    }
}

// how a proxy probes fields: a lone circle probes as one point, a sprite
// probes with its surface cells
enum PointKind {
    PointKind_None,
    PointKind_Circle,
    PointKind_Surface,
};

static PointKind point_kind_of(const PhysicsProxy& proxy, const Collider* shape) {
    if (proxy.sprite) {
        return PointKind_Surface;
    }

    if (shape && shape->shape == ColliderShape::Circle && shape->radius > 0.f) {
        return PointKind_Circle;
    }

    return PointKind_None;
}

static bool pair_collides(PointKind point, FieldKind field) {
    if (point == PointKind_None || field == FieldKind_None) {
        return false;
    }

    // surface cells only probe sprite fields, sprite vs shape is not needed yet
    if (point == PointKind_Surface && field != FieldKind_Sprite) {
        return false;
    }

    return true;
}

// ---------------------------------------------------------------------------
// candidates, gathered once per tick with a margin, re-evaluated every substep

static ContactCandidate make_candidate(int point_proxy, int field_proxy, godot::Vector2 local_point, float radius,
                                       float separation, godot::Vector2 normal, godot::Vector2 v_rel, bool sensor) {
    ContactCandidate candidate;
    candidate.point_proxy = point_proxy;
    candidate.field_proxy = field_proxy;
    candidate.local_point = local_point;
    candidate.radius = radius;
    candidate.vn_rest = (normal).dot(v_rel);
    candidate.vt_rest = (v_rel - normal * candidate.vn_rest).length();
    candidate.normal = normal;
    candidate.lambda_n = 0.f;
    candidate.depth = 0.f;
    candidate.separation = separation;
    candidate.impulse_n = 0.f;
    candidate.impulse_t = godot::Vector2(0.f, 0.f);
    candidate.active = false;
    candidate.sensor = sensor;
    return candidate;
}

static void gather_candidates_one_way(const godot::LocalVector<PhysicsProxy>& proxies, const godot::LocalVector<FieldKind>& field_kinds,
                                      const godot::LocalVector<const Collider*>& proxy_shapes, const godot::LocalVector<SolverBody>& bodies,
                                      int point_proxy, int field_proxy, const PhysicsSettings& settings, float delta_time,
                                      godot::LocalVector<ContactCandidate>& out) {
    const PhysicsProxy& pp = proxies[point_proxy];
    const PhysicsProxy& fp = proxies[field_proxy];

    const Collider* p_shape = proxy_shapes[point_proxy];
    const Collider* f_shape = proxy_shapes[field_proxy];

    PointKind point = point_kind_of(pp, p_shape);
    FieldKind field = field_kinds[field_proxy];

    if (!pair_collides(point, field)) {
        return;
    }

    const SolverBody& pb = bodies[point_proxy];
    const SolverBody& fb = bodies[field_proxy];

    float rel_speed = (pb.linear_velocity - fb.linear_velocity).length()
                    + fabsf(pb.angular_velocity) * pb.bound_radius
                    + fabsf(fb.angular_velocity) * fb.bound_radius;

    float margin = settings.contact_margin_cells * fb.cell_world + rel_speed * delta_time;
    bool sensor = (p_shape && p_shape->sensor) || (f_shape && f_shape->sensor);

    if (point == PointKind_Circle) {
        godot::Vector2 world = pb.com;

        FieldSample sample = field_sample(fp, f_shape, fb, field, world);
        float separation = sample.separation - p_shape->radius;

        if (separation >= margin) {
            return;
        }

        godot::Vector2 v_rel = body_velocity_at(pb, godot::Vector2(0.f, 0.f)) - body_velocity_at(fb, world - fb.com);

        out.push_back(make_candidate(point_proxy, field_proxy, pp.body->center_of_mass, p_shape->radius, separation, sample.normal, v_rel, sensor));
        return;
    }

    float radius = 0.5f * pb.cell_world;

    float p_sin = sinf(pb.angle);
    float p_cos = cosf(pb.angle);

    struct Hit {
        ContactCandidate candidate;
        float separation;
        godot::Vector2 world;
    };

    godot::LocalVector<Hit> hits[k_contact_sectors];

    // chunk level broadphase, a chunk only contributes surface points when
    // its world box can reach the field body's box

    AxisAlignedBox reach = fp.extended_box;
    reach.min -= godot::Vector2(margin, margin);
    reach.max += godot::Vector2(margin, margin);

    const Grid& grid_p = pp.sprite->grid();

    for (const SpriteChunk* chunk : pp.sprite->chunks().items()) {
        godot::Vector2 chunk_lo = grid_p.to_local_point(godot::Vector2(chunk->gridPixelOffset));
        godot::Vector2 chunk_hi = grid_p.to_local_point(godot::Vector2((float)(chunk->gridPixelOffset.x + grid_p.chunkSize), (float)(chunk->gridPixelOffset.y + grid_p.chunkSize)));

        godot::Vector2 corners[4] = {
            pb.com + rotate_local_point(chunk_lo * pb.scale - pb.com_scaled, p_sin, p_cos),
            pb.com + rotate_local_point(godot::Vector2(chunk_hi.x, chunk_lo.y) * pb.scale - pb.com_scaled, p_sin, p_cos),
            pb.com + rotate_local_point(chunk_hi * pb.scale - pb.com_scaled, p_sin, p_cos),
            pb.com + rotate_local_point(godot::Vector2(chunk_lo.x, chunk_hi.y) * pb.scale - pb.com_scaled, p_sin, p_cos),
        };

        AxisAlignedBox chunk_box(corners, 4);

        if (!chunk_box.intersects_box(reach)) {
            continue;
        }

        for (const auto& [cell_pos, cell_index] : chunk->surface) {
            godot::Vector2 local = grid_p.to_local_point_centered(chunk->gridPixelOffset + cell_pos);

            godot::Vector2 world = pb.com + rotate_local_point(local * pb.scale - pb.com_scaled, p_sin, p_cos);

            FieldSample sample = field_sample(fp, f_shape, fb, field, world);
            float separation = sample.separation - radius;

            if (separation >= margin) {
                continue;
            }

            godot::Vector2 v_rel = body_velocity_at(pb, world - pb.com) - body_velocity_at(fb, world - fb.com);

            int sector = static_cast<int>(floorf((atan2f(sample.normal.y, sample.normal.x) + 3.14159265f) / 6.2831853f * static_cast<float>(k_contact_sectors))) & (k_contact_sectors - 1);

            hits[sector].push_back({make_candidate(point_proxy, field_proxy, local, radius, separation, sample.normal, v_rel, sensor), separation, world});
        }
    }

    // per normal direction keep only the manifold ends plus the deepest point

    for (int sector = 0; sector < k_contact_sectors; sector++) {
        const godot::LocalVector<Hit>& bucket = hits[sector];

        if (bucket.is_empty()) {
            continue;
        }

        float angle = (sector + 0.5f) / static_cast<float>(k_contact_sectors) * 6.2831853f - 3.14159265f;
        godot::Vector2 tangent(-sinf(angle), cosf(angle));

        int lo = 0;
        int hi = 0;
        int deep = 0;

        for (int i = 1; i < static_cast<int>(bucket.size()); i++) {
            if ((bucket[i].world).dot(tangent) < (bucket[lo].world).dot(tangent)) {
                lo = i;
            }

            if ((bucket[i].world).dot(tangent) > (bucket[hi].world).dot(tangent)) {
                hi = i;
            }

            if (bucket[i].separation < bucket[deep].separation) {
                deep = i;
            }
        }

        out.push_back(bucket[lo].candidate);

        if (hi != lo) {
            out.push_back(bucket[hi].candidate);
        }

        if (deep != lo && deep != hi) {
            out.push_back(bucket[deep].candidate);
        }
    }
}

void gather_candidates(const godot::LocalVector<PhysicsProxy>& proxies,
                       const godot::LocalVector<FieldKind>& field_kinds, const godot::LocalVector<const Collider*>& proxy_shapes,
                       const godot::LocalVector<SolverBody>& bodies, const PhysicsSettings& settings, float delta_time,
                       PhysicsSolverState& state) {

    // each pair writes into its own bucket, the buckets concat once at the end
    // so the parallel gather does not contend on a mutex
    state.candidates.clear();
    state.candidates_per_pair.resize(state.pairs.size());

    for (auto& bucket : state.candidates_per_pair) {
        bucket.clear();
    }

    parallel_for(0, state.pairs.size(), [&](size_t i) {

        const ProxyPair& pair = state.pairs[i];
        godot::LocalVector<ContactCandidate>& local = state.candidates_per_pair[i];

        // corner points sample both ways, a corner on either body finds the other's field
        gather_candidates_one_way(proxies, field_kinds, proxy_shapes, bodies, pair.proxy_0, pair.proxy_1, settings, delta_time, local);
        gather_candidates_one_way(proxies, field_kinds, proxy_shapes, bodies, pair.proxy_1, pair.proxy_0, settings, delta_time, local);
    });

    size_t total = 0;

    for (const auto& bucket : state.candidates_per_pair) {
        total += bucket.size();
    }

    state.candidates.reserve(total);

    for (const auto& bucket : state.candidates_per_pair) {
        for (const ContactCandidate& c : bucket) state.candidates.push_back(c);
    }
}

// ---------------------------------------------------------------------------
// contact solve

void solve_contact_position(const godot::LocalVector<PhysicsProxy>& proxies, const godot::LocalVector<FieldKind>& field_kinds,
                            const godot::LocalVector<const Collider*>& proxy_shapes, godot::LocalVector<SolverBody>& bodies,
                            ContactCandidate& c, float friction, float max_depenetration_cells) {
    SolverBody& pb = bodies[c.point_proxy];
    SolverBody& fb = bodies[c.field_proxy];

    const PhysicsProxy& fp = proxies[c.field_proxy];

    godot::Vector2 world = body_point_world(pb, c.local_point);

    FieldSample sample = field_sample(fp, proxy_shapes[c.field_proxy], fb, field_kinds[c.field_proxy], world);
    float separation = sample.separation - c.radius;

    c.separation = separation;
    c.normal = sample.normal;

    if (separation >= 0.f) {
        return;
    }

    if (c.sensor) {
        c.active = true;
        c.depth = std::max(c.depth, -separation);
        return;
    }

    separation = std::max(separation, -max_depenetration_cells * fb.cell_world);

    godot::Vector2 normal = c.normal;

    godot::Vector2 r_p = world - pb.com;
    godot::Vector2 r_f = world - fb.com;

    float w_p = body_inverse_mass_at(pb, r_p, normal);
    float w_f = body_inverse_mass_at(fb, r_f, normal);
    float w = w_p + w_f;

    if (w <= 0.f) {
        return;
    }

    float lambda = -separation / w;

    c.active = true;
    c.lambda_n += lambda;
    c.depth = std::max(c.depth, -separation);

    body_apply_bias_correction(pb, normal * lambda, r_p);
    body_apply_bias_correction(fb, normal * -lambda, r_f);

    // static friction

    godot::Vector2 p_prev = body_point_world(pb, c.local_point, pb.prev_com, pb.prev_angle);
    godot::Vector2 f_local = body_world_to_local(fb, world);
    godot::Vector2 f_prev = body_point_world(fb, f_local, fb.prev_com, fb.prev_angle);

    godot::Vector2 delta = (world - p_prev) - (world - f_prev);
    godot::Vector2 tangential = delta - normal * (delta).dot(normal);

    auto [t_dir, t_len] = safe_normalize_distance(tangential);

    if (t_len < 1e-9f) {
        return;
    }

    float w_pt = body_inverse_mass_at(pb, r_p, t_dir);
    float w_ft = body_inverse_mass_at(fb, r_f, t_dir);
    float w_t = w_pt + w_ft;

    if (w_t <= 0.f) {
        return;
    }

    // clamped, partial holds stop stacks from ratcheting sideways
    float lambda_t = std::min(t_len / w_t, friction * c.lambda_n);

    if (lambda_t > 0.f) {
        body_apply_bias_correction(pb, t_dir * -lambda_t, r_p);
        body_apply_bias_correction(fb, t_dir * lambda_t, r_f);
    }
}

// one sequential impulse iteration with accumulated clamping
void solve_contact_velocity(godot::LocalVector<SolverBody>& bodies, ContactCandidate& c, const PhysicsSettings& settings,
                            float substep_time) {
    if (c.sensor) {
        return;
    }

    SolverBody& pb = bodies[c.point_proxy];
    SolverBody& fb = bodies[c.field_proxy];

    godot::Vector2 world = body_point_world(pb, c.local_point);
    godot::Vector2 r_p = world - pb.com;
    godot::Vector2 r_f = world - fb.com;

    godot::Vector2 normal = c.normal;
    godot::Vector2 v_rel = body_velocity_at(pb, r_p) - body_velocity_at(fb, r_f);

    float vn = (normal).dot(v_rel);

    float w_n = body_inverse_mass_at(pb, r_p, normal) + body_inverse_mass_at(fb, r_f, normal);

    if (w_n <= 0.f) {
        return;
    }

    // speculative while a gap remains, approach no faster than closes the gap
    float target_vn = c.separation > 0.f ? -c.separation / substep_time : 0.f;
    float delta_n = (target_vn - vn) / w_n;

    float old_n = c.impulse_n;
    c.impulse_n = std::max(old_n + delta_n, 0.f);
    delta_n = c.impulse_n - old_n;

    body_apply_velocity(pb, normal * delta_n, r_p);
    body_apply_velocity(fb, normal * -delta_n, r_f);

    // coulomb friction

    v_rel = body_velocity_at(pb, r_p) - body_velocity_at(fb, r_f);
    godot::Vector2 vt = v_rel - normal * (normal).dot(v_rel);

    auto [t_dir, t_speed] = safe_normalize_distance(vt);

    if (t_speed < 1e-9f) {
        return;
    }

    float w_t = body_inverse_mass_at(pb, r_p, t_dir) + body_inverse_mass_at(fb, r_f, t_dir);

    if (w_t <= 0.f) {
        return;
    }

    godot::Vector2 old_t = c.impulse_t;
    godot::Vector2 new_t = old_t - t_dir * (t_speed / w_t);

    float max_t = settings.friction * c.impulse_n;
    float len_t = (new_t).length();

    if (len_t > max_t) {
        new_t *= len_t > 1e-9f ? max_t / len_t : 0.f;
    }

    c.impulse_t = new_t;

    godot::Vector2 delta_t = new_t - old_t;

    body_apply_velocity(pb, delta_t, r_p);
    body_apply_velocity(fb, delta_t * -1.f, r_f);
}

// runs after the normal solve so the speculative bound can't eat the bounce
void solve_contact_restitution(godot::LocalVector<SolverBody>& bodies, ContactCandidate& c, const PhysicsSettings& settings) {
    if (c.sensor || c.impulse_n <= 0.f || settings.restitution <= 0.f) {
        return;
    }

    if (-c.vn_rest <= settings.restitution_threshold) {
        return;
    }

    SolverBody& pb = bodies[c.point_proxy];
    SolverBody& fb = bodies[c.field_proxy];

    godot::Vector2 world = body_point_world(pb, c.local_point);
    godot::Vector2 r_p = world - pb.com;
    godot::Vector2 r_f = world - fb.com;

    godot::Vector2 v_rel = body_velocity_at(pb, r_p) - body_velocity_at(fb, r_f);

    float vn = (c.normal).dot(v_rel);
    float target = -settings.restitution * c.vn_rest;

    if (vn >= target) {
        return;
    }

    float w_n = body_inverse_mass_at(pb, r_p, c.normal) + body_inverse_mass_at(fb, r_f, c.normal);

    if (w_n <= 0.f) {
        return;
    }

    float delta = (target - vn) / w_n;

    c.impulse_n += delta;

    body_apply_velocity(pb, c.normal * delta, r_p);
    body_apply_velocity(fb, c.normal * -delta, r_f);
}
