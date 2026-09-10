#include "SpritePhysics.h"

#include "Math/MathUtil.h"



#include <cmath>

// sprite to solver mapping

PhysicsProxy sprite_physics_create_proxy(godot::ObjectID entity, Transform& transform, PhysicsBody& body, Sprite& sprite,
                                         float delta_time) {
    Transform body_transform = body.transform(transform.scale);

    AxisAlignedBox box = body_transform
        .bounds()
        .extend_box(body.linear_velocity * delta_time, body.angular_velocity * delta_time);

    Sprite* field = sprite.grid().total_cells_in_grid() > 0 ? &sprite : nullptr;

    return {entity, &body, field, body_transform.scale, box};
}

// sprite rope mapping, chain state in and solved state out

PhysicsRope sprite_physics_create_rope(const SpriteRope& rope, SpriteRopeSet& set, int owner_proxy, float delta_time) {
    PhysicsRope out;
    out.owner_proxy = owner_proxy;

    float node_mass = std::max(set.node_mass, 1e-4f);
    out.node_inv_mass = 1.f / node_mass;

    // the set damping is a per tick fraction, turn it into a rate
    float damping_fraction = clamp(set.damping, 0.f, 0.99f);
    out.damping = damping_fraction / ((1.f - damping_fraction) * delta_time);
    out.rest_lengths = rope.rest_len;
    out.segment_rest_length = rope.rest_len.is_empty() ? 0.f : rope.rest_len[0];

    int n = static_cast<int>(rope.nodes.size());

    if (static_cast<int>(rope.rest_local.size()) == n && owner_proxy >= 0) {
        out.rest_locals = rope.rest_local;
        out.shape_stiffness = clamp(set.angle_stiffness, 0.f, 1.f);
    }

    bool has_velocities = static_cast<int>(rope.node_velocities.size()) == n;

    for (int i = 0; i < n; i++) {
        godot::Vector2 velocity = has_velocities
            ? rope.node_velocities[i]
            : (rope.nodes[i].position - rope.nodes[i].last_position) / delta_time;

        out.positions.push_back(rope.nodes[i].position);
        out.velocities.push_back(velocity);
        out.prev_positions.push_back(rope.nodes[i].position);
    }

    return out;
}

// the drive is an acceleration, sized so the sway lands around a few pixels
// no matter the period. the phase walks down the chain so the wave travels

constexpr float s_wiggle_sway_pixels = 3.f;
constexpr float s_wiggle_node_phase = 0.9f;
constexpr float s_two_pi = 6.2831853f;

void sprite_physics_wiggle_rope(PhysicsRope& rope, float period, float amount, float phase, float time, float delta_time) {
    int n = (int)rope.positions.size();

    if (period <= 0.f || amount <= 0.f || phase < 0.f || n < 2) {
        return;
    }

    float omega = s_two_pi / period;
    float accel = amount * s_wiggle_sway_pixels * 2.f * rope.radius * omega * omega;

    for (int i = 0; i < n; i++) {
        int segment = std::min(i, n - 2);
        godot::Vector2 dir = rope.positions[segment + 1] - rope.positions[segment];
        float len = (dir).length();

        if (len < 1e-6f) {
            continue;
        }

        godot::Vector2 perp = godot::Vector2(-dir.y, dir.x) / len;

        rope.velocities[i] += perp * accel * sinf(omega * time + phase - s_wiggle_node_phase * (float)i) * delta_time;
    }
}

void sprite_physics_apply_rope(const PhysicsRope& solved, SpriteRope& rope, float delta_time) {
    // last_position keeps the real pre solve pose so the render lerp only
    // travels positions the node actually visited. deriving it back from the
    // velocity misses the bias part of the correction and makes tangled ropes
    // visually snap through space for a frame

    for (size_t i = 0; i < solved.positions.size(); i++) {
        rope.nodes[i].last_position = rope.nodes[i].position;
        rope.nodes[i].position = solved.positions[i];
    }

    if (rope.node_velocities.size() == solved.positions.size()) {
        rope.node_velocities = solved.velocities;
    }
}
