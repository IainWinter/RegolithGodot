#include "RopeFeed.h"
#include "RegolithSprite.h"

#include "DestructibleSprite/Algorithm/SpritePhysics.h"
#include "DestructibleSprite/Algorithm/SpriteRopeHit.h"
#include "DestructibleSprite/Algorithm/SpriteRopeSpawn.h"

#include <godot_cpp/core/object.hpp>

#include <godot_cpp/templates/hash_map.hpp>

using namespace godot;

// entity anchors follow a cell on another sprite, they let go once that
// sprite is gone or the cell and its neighbours are destroyed
static void release_dead_entity_anchors(godot::LocalVector<SpriteRope>& ropes) {
    auto alive = [](const SpriteRopeEntityAnchor& anchor) {
        RegolithSprite* far = Object::cast_to<RegolithSprite>(ObjectDB::get_instance(anchor.entity));
        return far && far->is_loaded() && sprite_rope_anchor_cell_alive(far->sprite(), anchor.cell);
    };

    for (SpriteRope& rope : ropes) {
        if (rope.a.type == SpriteRopeAnchorType_Entity && !alive(rope.entity_a)) {
            rope.entity_a.entity = ObjectID();
            rope.a.type = SpriteRopeAnchorType_Free;
        }

        if (rope.b.type == SpriteRopeAnchorType_Entity && !alive(rope.entity_b)) {
            rope.entity_b.entity = ObjectID();
            rope.b.type = SpriteRopeAnchorType_Free;
        }
    }
}

void feed_ropes(PhysicsWorld& physics, const godot::LocalVector<RegolithSprite*>& sprites, float time, float delta_time, godot::LocalVector<SpriteRope*>& sources) {
    godot::LocalVector<PhysicsProxy>& proxies = physics.proxies();
    godot::LocalVector<PhysicsRope>& solver_ropes = physics.ropes();
    solver_ropes.clear();

    godot::HashMap<const PhysicsBody*, int> proxy_of;

    for (int i = 0; i < static_cast<int>(proxies.size()); i++) {
        proxy_of[proxies[i].body] = i;
    }

    auto proxy_index_of = [&](RegolithSprite* node) {
        auto it = proxy_of.find(&node->body());
        return it == proxy_of.end() ? -1 : it->value;
    };

    for (RegolithSprite* node : sprites) {
        if (!node->has_ropes()) {
            continue;
        }

        const Grid& grid = node->rope_grid();

        if (grid.cells.x <= 0 || grid.cells.y <= 0) {
            continue;
        }

        SpriteRopeSet& rope_set = node->ropes();
        godot::LocalVector<SpriteRope>& ropes = rope_set.ropes;

        release_dead_entity_anchors(ropes);

        Transform true_transform = node->body().transform(node->transform().scale);
        sprite_rope_init_runtime(true_transform, ropes);

        int own_proxy = proxy_index_of(node);
        int base = static_cast<int>(solver_ropes.size());

        auto rope_anchor_valid = [&](const SpriteRopeAnchor& anchor) {
            return anchor.type == SpriteRopeAnchorType_Rope
                && anchor.rope_index >= 0 && anchor.rope_index < static_cast<int>(ropes.size());
        };

        godot::LocalVector<int> incoming; vector_fill(incoming, ropes.size(), 0);

        for (const SpriteRope& rope : ropes) {
            if (rope_anchor_valid(rope.a)) {
                incoming[rope.a.rope_index] += 1;
            }

            if (rope_anchor_valid(rope.b)) {
                incoming[rope.b.rope_index] += 1;
            }
        }

        godot::LocalVector<uint8_t> owner_rooted; vector_fill(owner_rooted, ropes.size(), 0);

        for (size_t i = 0; i < ropes.size(); i++) {
            owner_rooted[i] = ropes[i].a.type == SpriteRopeAnchorType_Cell || ropes[i].b.type == SpriteRopeAnchorType_Cell;
        }

        for (bool changed = true; changed; ) {
            changed = false;

            for (size_t i = 0; i < ropes.size(); i++) {
                if (owner_rooted[i]) {
                    continue;
                }

                bool from_a = rope_anchor_valid(ropes[i].a) && owner_rooted[ropes[i].a.rope_index];
                bool from_b = rope_anchor_valid(ropes[i].b) && owner_rooted[ropes[i].b.rope_index];

                if (from_a || from_b) {
                    owner_rooted[i] = 1;
                    changed = true;
                }
            }
        }

        godot::LocalVector<int> solver_index; vector_fill(solver_index, ropes.size(), -1);

        for (int rope_i = 0; rope_i < static_cast<int>(ropes.size()); rope_i++) {
            SpriteRope& rope = ropes[rope_i];
            int n = static_cast<int>(rope.nodes.size());

            if (n < 2 || static_cast<int>(rope.rest_len.size()) != n - 1) {
                continue;
            }

            solver_index[rope_i] = static_cast<int>(solver_ropes.size());

            PhysicsRope out = sprite_physics_create_rope(rope, rope_set, own_proxy, delta_time);

            out.radius = sprite_rope_radius(node->transform(), grid);

            sprite_physics_wiggle_rope(out, rope_set.wiggle, rope.wiggle_amount, rope.wiggle_phase, time, delta_time);

            bool held = incoming[rope_i] > 0;

            auto resolve = [&](const SpriteRopeAnchor& anchor, const SpriteRopeEntityAnchor& entity_anchor, PhysicsRopeAnchor& out_anchor) {
                if (anchor.type == SpriteRopeAnchorType_Cell && own_proxy != -1) {
                    out_anchor = {own_proxy, grid.to_local_point_centered(anchor.cell)};
                    held = true;
                }

                else if (anchor.type == SpriteRopeAnchorType_Entity && entity_anchor.entity.is_valid()) {
                    RegolithSprite* far = Object::cast_to<RegolithSprite>(ObjectDB::get_instance(entity_anchor.entity));
                    int far_proxy = far && far->is_loaded() ? proxy_index_of(far) : -1;

                    if (far_proxy != -1 && far->sprite().grid().total_cells_in_grid() > 0) {
                        out_anchor = {far_proxy, far->sprite().grid().to_local_point_centered(entity_anchor.cell)};
                        held = true;
                    }
                }

                else if (rope_anchor_valid(anchor)) {
                    out_anchor.rope_index = base + anchor.rope_index;
                    out_anchor.node_index = anchor.node_index;
                    held = true;
                }
            };

            resolve(rope.a, rope.entity_a, out.anchor_a);
            resolve(rope.b, rope.entity_b, out.anchor_b);

            if (!held && own_proxy != -1 && !rope.rest_local.is_empty()) {
                out.anchor_a = {own_proxy, rope.rest_local[0]};
            }

            else if (!owner_rooted[rope_i]) {
                out.rest_locals.clear();
                out.shape_stiffness = 0.f;
            }

            solver_ropes.push_back(std::move(out));
            sources.push_back(&rope);
        }

        for (int rope_i = 0; rope_i < static_cast<int>(ropes.size()); rope_i++) {
            if (solver_index[rope_i] == -1) {
                continue;
            }

            PhysicsRope& out = solver_ropes[solver_index[rope_i]];

            PhysicsRopeAnchor* anchors[2] = {&out.anchor_a, &out.anchor_b};
            const SpriteRopeAnchor* set_anchors[2] = {&ropes[rope_i].a, &ropes[rope_i].b};

            for (int k = 0; k < 2; k++) {
                if (anchors[k]->rope_index < 0) {
                    continue;
                }

                int target = solver_index[set_anchors[k]->rope_index];

                anchors[k]->rope_index = target;

                if (target == -1) {
                    anchors[k]->node_index = 0;
                }
            }
        }
    }
}
