#include "Containers/VectorUtil.h"
#include "SpriteRopeCut.h"

#include "Constants.h"
#include "Math/MathUtil.h"



#include <godot_cpp/templates/hash_map.hpp>

constexpr float s_cut_kick = 2.f * k_cell_local_size;
constexpr int s_cut_kick_nodes = 3;

UnionFind group_ropes_by_rope_anchors(const godot::LocalVector<SpriteRope>& ropes) {
    int n = (int)ropes.size();

    UnionFind groups;

    for (int i = 0; i < n; i++) {
        groups.find(i);

        const SpriteRopeAnchor* anchors[2] = {&ropes[i].a, &ropes[i].b};

        for (const SpriteRopeAnchor* anchor : anchors) {
            if (anchor->type == SpriteRopeAnchorType_Rope && anchor->rope_index >= 0 && anchor->rope_index < n) {
                groups.unite(i, anchor->rope_index);
            }
        }
    }

    return groups;
}

void remap_rope_anchor_indices(SpriteRope& rope, const godot::LocalVector<int>& remap, int count) {
    SpriteRopeAnchor* anchors[2] = {&rope.a, &rope.b};

    for (SpriteRopeAnchor* anchor : anchors) {
        if (anchor->type != SpriteRopeAnchorType_Rope) {
            continue;
        }

        if (anchor->rope_index >= 0 && anchor->rope_index < count && remap[anchor->rope_index] != -1) {
            anchor->rope_index = remap[anchor->rope_index];
        }

        else {
            anchor->type = SpriteRopeAnchorType_Free;
        }
    }
}

static SpriteRope slice_rope(const SpriteRope& rope, int begin, int end) {
    SpriteRope piece;
    piece.a.type = SpriteRopeAnchorType_Free;
    piece.b.type = SpriteRopeAnchorType_Free;
    piece.color = rope.color;
    piece.cell_class = rope.cell_class;
    piece.wiggle_phase = rope.wiggle_phase;
    piece.wiggle_amount = 0.f;

    if (begin >= end) {
        return piece;
    }

    vector_assign_range(piece.rest_local, rope.rest_local.ptr() + begin, rope.rest_local.ptr() + end);

    if ((int)rope.nodes.size() >= end) {
        vector_assign_range(piece.nodes, rope.nodes.ptr() + begin, rope.nodes.ptr() + end);
    }

    if ((int)rope.node_velocities.size() >= end) {
        vector_assign_range(piece.node_velocities, rope.node_velocities.ptr() + begin, rope.node_velocities.ptr() + end);
    }

    if ((int)rope.node_health.size() >= end) {
        vector_assign_range(piece.node_health, rope.node_health.ptr() + begin, rope.node_health.ptr() + end);
    }

    if ((int)rope.rest_len.size() >= end - 1 && begin < end - 1) {
        vector_assign_range(piece.rest_len, rope.rest_len.ptr() + begin, rope.rest_len.ptr() + (end - 1));
    }

    return piece;
}

static void kick_piece_from_cut(SpriteRope& piece, godot::Vector2 cut_position, bool cut_at_front) {
    int n = (int)piece.nodes.size();

    if (n == 0) {
        return;
    }

    for (int k = 0; k < s_cut_kick_nodes && k < n; k++) {
        int i = cut_at_front ? k : n - 1 - k;

        godot::Vector2 dir = piece.nodes[i].position - cut_position;
        float d = (dir).length();

        if (d < 1e-6f) {
            continue;
        }

        float falloff = 1.f - (float)k / (float)s_cut_kick_nodes;

        piece.nodes[i].last_position -= dir / d * s_cut_kick * falloff;

        if (i < (int)piece.node_velocities.size()) {
            piece.node_velocities[i] += dir / d * s_cut_kick * falloff * 60.f;
        }
    }
}

void compact_dead_sprite_ropes(godot::LocalVector<SpriteRope>& ropes) {
    int n = (int)ropes.size();

    godot::LocalVector<int> remap; vector_fill(remap, n, -1);
    int next = 0;

    for (int i = 0; i < n; i++) {
        if (ropes[i].rest_local.size() >= 2) {
            remap[i] = next;
            next += 1;
        }
    }

    for (SpriteRope& rope : ropes) {
        remap_rope_anchor_indices(rope, remap, n);
    }

    int write = 0;

    for (int i = 0; i < n; i++) {
        if (remap[i] == -1) {
            continue;
        }

        if (write != i) {
            ropes[write] = std::move(ropes[i]);
        }

        write += 1;
    }

    ropes.resize(write);
}

SpriteRopeCutResult cut_sprite_rope(SpriteRopeSet& set, int rope_index, int node_index) {
    SpriteRopeCutResult result;

    godot::LocalVector<SpriteRope>& ropes = set.ropes;

    if (rope_index < 0 || rope_index >= (int)ropes.size()) {
        return result;
    }

    SpriteRope rope = std::move(ropes[rope_index]);

    int n = (int)rope.rest_local.size();

    if (n < 2) {
        ropes[rope_index] = std::move(rope);
        return result;
    }

    node_index = clamp(node_index, 0, n - 1);

    SpriteRope head = slice_rope(rope, 0, node_index);
    SpriteRope tail = slice_rope(rope, node_index + 1, n);

    head.a = rope.a;
    head.entity_a = rope.entity_a;
    tail.b = rope.b;
    tail.entity_b = rope.entity_b;

    bool head_alive = head.rest_local.size() >= 2;
    bool tail_alive = tail.rest_local.size() >= 2;

    if ((int)rope.nodes.size() == n) {
        godot::Vector2 cut_position = rope.nodes[node_index].position;

        kick_piece_from_cut(head, cut_position, false);
        kick_piece_from_cut(tail, cut_position, true);
    }

    int tail_index = (int)ropes.size();

    auto remap_anchor = [&](SpriteRopeAnchor& anchor) {
        if (anchor.type != SpriteRopeAnchorType_Rope || anchor.rope_index != rope_index) {
            return;
        }

        if (anchor.node_index < node_index && head_alive) {
            return;
        }

        if (anchor.node_index > node_index && tail_alive) {
            anchor.rope_index = tail_index;
            anchor.node_index -= node_index + 1;
            return;
        }

        anchor.type = SpriteRopeAnchorType_Free;
    };

    for (int i = 0; i < (int)ropes.size(); i++) {
        if (i == rope_index) {
            continue;
        }

        remap_anchor(ropes[i].a);
        remap_anchor(ropes[i].b);
    }

    auto drop_as_pixels = [&](const SpriteRope& piece) {
        for (const SpriteRopeNode& node : piece.nodes) {
            result.loose_pixels.push_back({node.position, piece.color});
        }
    };

    if ((int)rope.nodes.size() == n) {
        result.loose_pixels.push_back({rope.nodes[node_index].position, rope.color});
    }

    if (!head_alive) {
        drop_as_pixels(head);
    }

    if (!tail_alive) {
        drop_as_pixels(tail);
    }

    ropes[rope_index] = std::move(head);
    ropes.push_back(std::move(tail));

    compact_dead_sprite_ropes(ropes);

    if (rope.a.type == SpriteRopeAnchorType_Cell) {
        result.anchor_cells.push_back(rope.a.cell);
    }

    if (rope.b.type == SpriteRopeAnchorType_Cell) {
        result.anchor_cells.push_back(rope.b.cell);
    }

    result.did_cut = true;

    return result;
}

static void insert_rope_node(SpriteRope& rope, int segment, float t) {
    auto lerp_at = [&](const auto& list, int i) {
        return lerp(list[i], list[i + 1], t);
    };

    rope.rest_local.insert(segment + 1, lerp_at(rope.rest_local, segment));

    if ((int)rope.nodes.size() > segment + 1) {
        SpriteRopeNode node;
        node.position = lerp(rope.nodes[segment].position, rope.nodes[segment + 1].position, t);
        node.last_position = lerp(rope.nodes[segment].last_position, rope.nodes[segment + 1].last_position, t);
        rope.nodes.insert(segment + 1, node);
    }

    if ((int)rope.node_velocities.size() > segment + 1) {
        rope.node_velocities.insert(segment + 1, lerp_at(rope.node_velocities, segment));
    }

    if ((int)rope.node_health.size() > segment + 1) {
        uint8_t health = std::max(rope.node_health[segment], rope.node_health[segment + 1]);
        rope.node_health.insert(segment + 1, health);
    }

    if ((int)rope.rest_len.size() > segment) {
        float rest = rope.rest_len[segment];
        rope.rest_len[segment] = rest * t;
        rope.rest_len.insert(segment + 1, rest * (1.f - t));
    }
}

SpriteRopeCutResult cut_sprite_rope_at(SpriteRopeSet& set, int rope_index, int segment, float t, float gap) {
    godot::LocalVector<SpriteRope>& ropes = set.ropes;

    if (rope_index < 0 || rope_index >= (int)ropes.size()) {
        return SpriteRopeCutResult {};
    }

    SpriteRope& rope = ropes[rope_index];

    int n = (int)rope.rest_local.size();

    if (n < 2) {
        return SpriteRopeCutResult {};
    }

    segment = clamp(segment, 0, n - 2);
    t = clamp(t, 0.f, 1.f);

    float len = (int)rope.nodes.size() == n
        ? (rope.nodes[segment].position).distance_to(rope.nodes[segment + 1].position)
        : ((int)rope.rest_len.size() > segment ? rope.rest_len[segment] : 0.f);

    float half = len > 1e-6f ? clamp(0.5f * gap / len, 0.005f, 0.45f) : 0.45f;

    if (t <= 2.f * half) {
        return cut_sprite_rope(set, rope_index, segment);
    }

    if (t >= 1.f - 2.f * half) {
        return cut_sprite_rope(set, rope_index, segment + 1);
    }

    insert_rope_node(rope, segment, t + half);
    insert_rope_node(rope, segment, t / (t + half));
    insert_rope_node(rope, segment, (t - half) / t);

    for (int i = 0; i < (int)ropes.size(); i++) {
        if (i == rope_index) {
            continue;
        }

        SpriteRopeAnchor* anchors[2] = {&ropes[i].a, &ropes[i].b};

        for (SpriteRopeAnchor* anchor : anchors) {
            if (anchor->type == SpriteRopeAnchorType_Rope && anchor->rope_index == rope_index && anchor->node_index > segment) {
                anchor->node_index += 3;
            }
        }
    }

    return cut_sprite_rope(set, rope_index, segment + 2);
}

godot::LocalVector<godot::LocalVector<SpriteRope>> extract_detached_rope_groups(SpriteRopeSet& set) {
    godot::LocalVector<SpriteRope>& ropes = set.ropes;
    int n = (int)ropes.size();

    UnionFind groups = group_ropes_by_rope_anchors(ropes);

    godot::HashMap<int, bool> anchored;

    for (int i = 0; i < n; i++) {
        int root = groups.find(i);

        bool held = ropes[i].a.type == SpriteRopeAnchorType_Cell || ropes[i].b.type == SpriteRopeAnchorType_Cell
                 || ropes[i].a.type == SpriteRopeAnchorType_Entity || ropes[i].b.type == SpriteRopeAnchorType_Entity;

        if (held) {
            anchored[root] = true;
        }

        else {
            anchored.insert(root, false);
        }
    }

    godot::HashMap<int, godot::LocalVector<int>> detached_members;

    for (int i = 0; i < n; i++) {
        int root = groups.find(i);

        if (!anchored[root]) {
            detached_members[root].push_back(i);
        }
    }

    godot::LocalVector<godot::LocalVector<SpriteRope>> detached;

    if (detached_members.is_empty()) {
        return detached;
    }

    godot::LocalVector<int> remap; vector_fill(remap, n, -1);

    for (auto& [root, members] : detached_members) {
        for (size_t k = 0; k < members.size(); k++) {
            remap[members[k]] = (int)k;
        }
    }

    for (auto& [root, members] : detached_members) {
        godot::LocalVector<SpriteRope> group;
        group.reserve(members.size());

        for (int i : members) {
            SpriteRope rope = std::move(ropes[i]);

            remap_rope_anchor_indices(rope, remap, n);

            group.push_back(std::move(rope));

            ropes[i].rest_local.clear();
            ropes[i].a.type = SpriteRopeAnchorType_Free;
            ropes[i].b.type = SpriteRopeAnchorType_Free;
        }

        detached.push_back(std::move(group));
    }

    compact_dead_sprite_ropes(ropes);

    return detached;
}
