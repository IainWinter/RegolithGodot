#include "Containers/VectorUtil.h"
#include "SpriteRopeSpawn.h"

#include "DestructibleSprite/Algorithm/SpriteRopeCut.h"
#include "Math/Random.h"
#include "Containers/UnionFind.h"

#include <godot_cpp/templates/hash_map.hpp>
#include <cmath>
#include <cstdint>



constexpr int k_rope_node_stride = 8;

SpriteRopeSet sprite_rope_set_from_asset(const Grid& grid, const SpriteAsset& asset) {
    SpriteRopeSet set {};

    int rope_count = static_cast<int>(asset.ropes.size());

    godot::LocalVector<godot::LocalVector<bool>> keep; keep.resize(rope_count);

    for (int r = 0; r < rope_count; r++) {
        int n = static_cast<int>(asset.ropes[r].path.size());
        vector_fill(keep[r], n, false);

        for (int i = 0; i < n; i += k_rope_node_stride) {
            keep[r][i] = true;
        }

        if (n > 0) {
            keep[r][0] = true;
            keep[r][n - 1] = true;
        }
    }

    auto keep_anchor_node = [&](const SpriteRopeAnchor& anchor) {
        if (anchor.type != SpriteRopeAnchorType_Rope) {
            return;
        }

        if (anchor.rope_index >= 0 && anchor.rope_index < rope_count
         && anchor.node_index >= 0 && anchor.node_index < static_cast<int>(keep[anchor.rope_index].size())) {
            keep[anchor.rope_index][anchor.node_index] = true;
        }
    };

    for (const SpriteAssetRope& rope_asset : asset.ropes) {
        keep_anchor_node(rope_asset.anchor_a);
        keep_anchor_node(rope_asset.anchor_b);
    }

    godot::LocalVector<godot::LocalVector<int>> remap; remap.resize(rope_count);

    for (int r = 0; r < rope_count; r++) {
        vector_fill(remap[r], keep[r].size(), 0);
        int kept = 0;

        for (int i = 0; i < static_cast<int>(keep[r].size()); i++) {
            remap[r][i] = kept;

            if (keep[r][i]) {
                kept += 1;
            }
        }
    }

    auto remap_anchor = [&](SpriteRopeAnchor& anchor) {
        if (anchor.type != SpriteRopeAnchorType_Rope) {
            return;
        }

        if (anchor.rope_index >= 0 && anchor.rope_index < rope_count
         && anchor.node_index >= 0 && anchor.node_index < static_cast<int>(remap[anchor.rope_index].size())) {
            anchor.node_index = remap[anchor.rope_index][anchor.node_index];
        }
    };

    for (int r = 0; r < rope_count; r++) {
        const SpriteAssetRope& rope_asset = asset.ropes[r];

        SpriteRope rope {};
        rope.a = rope_asset.anchor_a;
        rope.b = rope_asset.anchor_b;
        rope.color = rope_asset.color;
        rope.cell_class = rope_asset.cell_class;

        remap_anchor(rope.a);
        remap_anchor(rope.b);

        for (int i = 0; i < static_cast<int>(rope_asset.path.size()); i++) {
            if (keep[r][i]) {
                rope.rest_local.push_back(grid.to_local_point_centered(rope_asset.path[i]));
            }
        }

        set.ropes.push_back(rope);
    }

    return set;
}

void sprite_rope_init_runtime(const Transform& transform, godot::LocalVector<SpriteRope>& ropes) {
    for (SpriteRope& rope : ropes) {
        int n = static_cast<int>(rope.rest_local.size());

        if (n < 2) {
            continue;
        }

        if (rope.wiggle_phase < 0.f) {
            rope.wiggle_phase = random_float_max(6.2831853f);
        }

        if (static_cast<int>(rope.nodes.size()) != n) {
            rope.nodes.resize(n);
            vector_fill(rope.rest_len, n - 1,  0.f);

            if (static_cast<int>(rope.node_health.size()) != n) {
                vector_fill(rope.node_health, n,  rope.cell_class + 1);
            }

            for (int i = 0; i < n; i++) {
                godot::Vector2 p = transform.to_world_point(rope.rest_local[i]);
                rope.nodes[i].position = p;
                rope.nodes[i].last_position = p;
            }

            for (int i = 0; i + 1 < n; i++) {
                rope.rest_len[i] = (rope.nodes[i].position).distance_to(rope.nodes[i + 1].position);
            }
        }

        if (static_cast<int>(rope.node_velocities.size()) != n) {
            vector_fill(rope.node_velocities, n,  godot::Vector2(0.f, 0.f));
        }
    }
}

static bool cell_filled(const Sprite& sprite, godot::Vector2i cell) {
    const Grid& grid = sprite.grid();

    if (!grid.is_grid_index_position_valid(cell)) {
        return false;
    }

    auto [chunk_index, cell_index] = grid.to_chunk_cell_index(cell);

    return sprite.is_chunk_active(chunk_index) && sprite.is_cell_active(chunk_index, cell_index);
}

bool sprite_rope_anchor_cell_alive(const Sprite& sprite, godot::Vector2i cell) {
    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            if (cell_filled(sprite, cell + godot::Vector2i(ox, oy))) {
                return true;
            }
        }
    }

    return false;
}

void sprite_rope_release_destroyed_anchors(const Sprite& sprite, godot::LocalVector<SpriteRope>& ropes) {
    for (SpriteRope& rope : ropes) {
        SpriteRopeAnchor* anchors[2] = {&rope.a, &rope.b};

        for (SpriteRopeAnchor* anchor : anchors) {
            if (anchor->type == SpriteRopeAnchorType_Cell && !sprite_rope_anchor_cell_alive(sprite, anchor->cell)) {
                anchor->type = SpriteRopeAnchorType_Free;
            }
        }
    }
}

godot::LocalVector<godot::LocalVector<SpriteRope>> sprite_rope_resolve_after_commit(godot::ObjectID owner, const Transform& transform, const Sprite& sprite,
                                                                       SpriteRopeSet& set, godot::LocalVector<SpriteRopeSplitTarget>& splits) {
    godot::LocalVector<SpriteRope>& ropes = set.ropes;
    int n = static_cast<int>(ropes.size());

    if (n == 0) {
        return {};
    }

    auto anchor_in_self = [&](godot::Vector2i cell) {
        return sprite_rope_anchor_cell_alive(sprite, cell);
    };

    auto anchor_in_split = [&](godot::Vector2i cell, size_t j) {
        return sprite_rope_anchor_cell_alive(*splits[j].sprite, cell - splits[j].grid_min);
    };

    // group ropes that hang off each other, then move each group onto the
    // split holding its connection cells. anchors still on this body become
    // entity anchors, the rope chain itself ties the split to this body in
    // the solver

    UnionFind groups = group_ropes_by_rope_anchors(ropes);

    godot::HashMap<int, size_t> target;

    for (int i = 0; i < n; i++) {
        int root = groups.find(i);

        if (target.has(root)) {
            continue;
        }

        const SpriteRopeAnchor* anchors[2] = {&ropes[i].a, &ropes[i].b};

        for (const SpriteRopeAnchor* anchor : anchors) {
            if (anchor->type != SpriteRopeAnchorType_Cell || anchor_in_self(anchor->cell)) {
                continue;
            }

            for (size_t j = 0; j < splits.size(); j++) {
                if (anchor_in_split(anchor->cell, j)) {
                    target.insert(root, j);
                    break;
                }
            }
        }
    }

    for (const auto& [root, j] : target) {
        SpriteRopeSplitTarget& split = splits[j];

        godot::LocalVector<int> members;

        for (int i = 0; i < n; i++) {
            if (groups.find(i) == root) {
                members.push_back(i);
            }
        }

        godot::LocalVector<int> remap; vector_fill(remap, n, -1);
        int base = static_cast<int>(split.ropes->ropes.size());

        for (size_t k = 0; k < members.size(); k++) {
            remap[members[k]] = base + static_cast<int>(k);
        }

        for (int i : members) {
            SpriteRope rope = std::move(ropes[i]);

            for (godot::Vector2& rest : rope.rest_local) {
                rest = split.transform->to_local_point(transform.to_world_point(rest));
            }

            remap_rope_anchor_indices(rope, remap, n);

            SpriteRopeAnchor* anchors[2] = {&rope.a, &rope.b};

            for (SpriteRopeAnchor* anchor : anchors) {
                if (anchor->type != SpriteRopeAnchorType_Cell) {
                    continue;
                }

                if (anchor_in_split(anchor->cell, j)) {
                    anchor->cell -= split.grid_min;
                }

                else if (anchor_in_self(anchor->cell)) {
                    // the rope still holds onto this body. keep following the
                    // cell through an entity anchor

                    SpriteRopeEntityAnchor& entity_anchor = anchor == &rope.a ? rope.entity_a : rope.entity_b;
                    entity_anchor.entity = owner;
                    entity_anchor.cell = anchor->cell;

                    anchor->type = SpriteRopeAnchorType_Entity;
                }

                else {
                    anchor->type = SpriteRopeAnchorType_Free;
                }
            }

            split.ropes->ropes.push_back(std::move(rope));

            ropes[i].rest_local.clear();
            ropes[i].a.type = SpriteRopeAnchorType_Free;
            ropes[i].b.type = SpriteRopeAnchorType_Free;
        }
    }

    compact_dead_sprite_ropes(ropes);

    sprite_rope_release_destroyed_anchors(sprite, ropes);

    // groups holding onto nothing break off on their own

    return extract_detached_rope_groups(set);
}

void sprite_rope_group_to_pixels(const godot::LocalVector<SpriteRope>& ropes, const Grid& grid, const Transform& transform, const PhysicsBody* body, godot::LocalVector<SpriteRopePixel>& out) {
    float neg_sin = sinf(-transform.angle);
    float neg_cos = cosf(-transform.angle);

    for (const SpriteRope& rope : ropes) {
        int n = static_cast<int>(rope.rest_local.size());

        if (n == 0) {
            continue;
        }

        bool live = static_cast<int>(rope.nodes.size()) == n;
        bool moving = static_cast<int>(rope.node_velocities.size()) == n;

        auto node_world = [&](int i) {
            return live ? rope.nodes[i].position : transform.to_world_point(rope.rest_local[i]);
        };

        auto node_velocity = [&](int i) {
            if (moving) {
                return rope.node_velocities[i];
            }

            return body ? body->velocity_at_local_point(transform.to_local_point(node_world(i))) : godot::Vector2(0.f, 0.f);
        };

        godot::Vector2i last_cell(INT32_MIN, INT32_MIN);

        auto emit = [&](godot::Vector2 grid_point, godot::Vector2 velocity) {
            godot::Vector2 f = grid_point.floor();
            godot::Vector2i cell = godot::Vector2i((int)f.x, (int)f.y);

            if (cell == last_cell) {
                return;
            }

            last_cell = cell;

            godot::Vector2 world = transform.to_world_point(grid.to_local_point_centered(cell));
            out.push_back({world, velocity, transform.angle, rope.color});
        };

        if (n == 1) {
            emit(grid.to_grid_point(transform.to_local_point(node_world(0), neg_sin, neg_cos)), node_velocity(0));
            continue;
        }

        for (int i = 0; i + 1 < n; i++) {
            godot::Vector2 a = grid.to_grid_point(transform.to_local_point(node_world(i), neg_sin, neg_cos));
            godot::Vector2 b = grid.to_grid_point(transform.to_local_point(node_world(i + 1), neg_sin, neg_cos));
            godot::Vector2 va = node_velocity(i);
            godot::Vector2 vb = node_velocity(i + 1);

            godot::Vector2 d = b - a;
            int steps = std::max(1, static_cast<int>(ceilf(std::max(fabsf(d.x), fabsf(d.y)) * 2.f)));

            for (int s = 0; s <= steps; s++) {
                float t = s / static_cast<float>(steps);
                emit(((a) * (1.f - (t)) + (b) * (t)), ((va) * (1.f - (t)) + (vb) * (t)));
            }
        }
    }
}
