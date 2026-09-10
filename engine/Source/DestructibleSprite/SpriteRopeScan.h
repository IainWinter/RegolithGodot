#pragma once

#include "Color.h"
#include "SpriteCell.h"

#include "Math/Vector.h"

#include <godot_cpp/templates/local_vector.hpp>

enum SpriteRopeAnchorType {
    SpriteRopeAnchorType_Free,
    SpriteRopeAnchorType_Cell,
    SpriteRopeAnchorType_Rope,
    SpriteRopeAnchorType_Entity,
};

struct  SpriteRopeAnchor {
    int type;
    godot::Vector2i cell;
    int rope_index;
    int node_index;
    int cell_type = SpriteCellMaskType_Empty;
};

struct ScannedRope {
    SpriteRopeAnchor a;
    SpriteRopeAnchor b;
    Color4 color;
    godot::LocalVector<godot::Vector2i> path;
};

godot::LocalVector<ScannedRope> scan_sprite_ropes(const godot::LocalVector<SpriteCellMaskType>& mask, const godot::LocalVector<Color4>& pixels, int w, int h);
