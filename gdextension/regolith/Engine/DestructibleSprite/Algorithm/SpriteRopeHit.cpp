#include "SpriteRopeHit.h"

#include "Constants.h"
#include "Coordinate/Grid.h"
#include "Math/MathUtil.h"

#include "glm/geometric.hpp"

float sprite_rope_radius(const Transform& transform, const Grid& grid) {
    return grid.cells.x > 0 ? transform.scale.x / (float)grid.cells.x : 0.f;
}

float sprite_rope_group_pixels(const std::vector<SpriteRope>& ropes) {
    float length = 0.f;

    for (const SpriteRope& rope : ropes) {
        for (size_t i = 0; i + 1 < rope.rest_local.size(); i++) {
            length += distance(rope.rest_local[i], rope.rest_local[i + 1]);
        }
    }

    return length / k_cell_local_size;
}

bool find_rope_hit_segment(const SpriteRopeSet& set, vec2 a, vec2 b, float radius, SpriteRopeHitResult* hit) {
    const std::vector<SpriteRope>& ropes = set.ropes;

    bool found = false;
    float best_along = 2.f;

    for (size_t rope_i = 0; rope_i < ropes.size(); rope_i++) {
        const SpriteRope& rope = ropes[rope_i];
        int n = (int)rope.nodes.size();

        for (int i = 0; i + 1 < n; i++) {
            vec2 r0 = rope.nodes[i].position;
            vec2 r1 = rope.nodes[i + 1].position;

            float s, t;
            closest_segment_segment(a, b, r0, r1, &s, &t);

            vec2 on_query = a + (b - a) * s;
            vec2 on_rope = r0 + (r1 - r0) * t;

            if (distance(on_query, on_rope) > radius) {
                continue;
            }

            if (s < best_along) {
                best_along = s;
                found = true;

                hit->rope_index = (int)rope_i;
                hit->segment_index = i;
                hit->segment_t = t;
                hit->node_index = t < 0.5f ? i : i + 1;
                hit->position = on_rope;
                hit->along = s;
            }
        }
    }

    return found;
}

bool find_rope_hit_point(const SpriteRopeSet& set, vec2 point, float radius, SpriteRopeHitResult* hit) {
    const std::vector<SpriteRope>& ropes = set.ropes;

    bool found = false;
    float best_dist = radius;

    for (size_t rope_i = 0; rope_i < ropes.size(); rope_i++) {
        const SpriteRope& rope = ropes[rope_i];
        int n = (int)rope.nodes.size();

        for (int i = 0; i + 1 < n; i++) {
            vec2 r0 = rope.nodes[i].position;
            vec2 r1 = rope.nodes[i + 1].position;

            float t = closest_t_on_segment(r0, r1, point);
            vec2 on_rope = r0 + (r1 - r0) * t;

            float d = distance(point, on_rope);

            if (d > best_dist) {
                continue;
            }

            best_dist = d;
            found = true;

            hit->rope_index = (int)rope_i;
            hit->segment_index = i;
            hit->segment_t = t;
            hit->node_index = t < 0.5f ? i : i + 1;
            hit->position = on_rope;
            hit->along = 0.f;
        }
    }

    return found;
}
