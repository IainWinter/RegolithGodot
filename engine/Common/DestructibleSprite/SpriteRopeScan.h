#pragma once

#include "Color.h"
#include "SpriteCell.h"

#include "Math/Vector.h"

#include <vector>

enum SpriteRopeAnchorType {
    SpriteRopeAnchorType_Free,
    SpriteRopeAnchorType_Cell,
    SpriteRopeAnchorType_Rope,
    SpriteRopeAnchorType_Entity,
};

struct [[Struct]] SpriteRopeAnchor {
    int type;
    ivec2 cell;
    int rope_index;
    int node_index;
    int cell_type = SpriteCellMaskType_Empty;
};

struct ScannedRope {
    SpriteRopeAnchor a;
    SpriteRopeAnchor b;
    Color4 color;
    std::vector<ivec2> path;
};

std::vector<ScannedRope> scan_sprite_ropes(const std::vector<SpriteCellMaskType>& mask, const std::vector<Color4>& pixels, int w, int h);
