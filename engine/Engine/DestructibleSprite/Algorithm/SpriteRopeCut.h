#pragma once

#include "DestructibleSprite/SpriteRope.h"

#include "Color.h"
#include "Math/Vector.h"
#include "UnionFind.h"

#include <utility>
#include <vector>

struct SpriteRopeCutResult {
    bool did_cut = false;

    std::vector<std::pair<vec2, Color4>> loose_pixels;

    std::vector<ivec2> anchor_cells;
};

UnionFind group_ropes_by_rope_anchors(const std::vector<SpriteRope>& ropes);

void remap_rope_anchor_indices(SpriteRope& rope, const std::vector<int>& remap, int count);

SpriteRopeCutResult cut_sprite_rope(SpriteRopeSet& set, int rope_index, int node_index);

SpriteRopeCutResult cut_sprite_rope_at(SpriteRopeSet& set, int rope_index, int segment, float t, float gap);

void compact_dead_sprite_ropes(std::vector<SpriteRope>& ropes);

std::vector<std::vector<SpriteRope>> extract_detached_rope_groups(SpriteRopeSet& set);
