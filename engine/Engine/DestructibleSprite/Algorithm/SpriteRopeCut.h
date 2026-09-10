#pragma once

#include "DestructibleSprite/SpriteRope.h"

#include "Color.h"
#include "Math/Vector.h"
#include "Containers/UnionFind.h"

#include <godot_cpp/templates/pair.hpp>
#include <godot_cpp/templates/local_vector.hpp>

struct SpriteRopeCutResult {
    bool did_cut = false;

    godot::LocalVector<godot::Pair<godot::Vector2, Color4>> loose_pixels;

    godot::LocalVector<godot::Vector2i> anchor_cells;
};

UnionFind group_ropes_by_rope_anchors(const godot::LocalVector<SpriteRope>& ropes);

void remap_rope_anchor_indices(SpriteRope& rope, const godot::LocalVector<int>& remap, int count);

SpriteRopeCutResult cut_sprite_rope(SpriteRopeSet& set, int rope_index, int node_index);

SpriteRopeCutResult cut_sprite_rope_at(SpriteRopeSet& set, int rope_index, int segment, float t, float gap);

void compact_dead_sprite_ropes(godot::LocalVector<SpriteRope>& ropes);

godot::LocalVector<godot::LocalVector<SpriteRope>> extract_detached_rope_groups(SpriteRopeSet& set);
