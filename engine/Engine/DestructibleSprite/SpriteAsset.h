#pragma once

#include "Constants.h"
#include "Color.h"
#include "SpriteCell.h"
#include "SpriteRopeScan.h"

#include "Math/Vector.h"


#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/string.hpp>

// end sprite enum stuff

struct  SpriteAssetCore {
    godot::Vector2i min;
    godot::Vector2i max;
    int width;
    int height;
    godot::Vector2 gridPointOffset;
    SpriteCellMaskType type;
    int initialCellCount;
    godot::LocalVector<Color4> color;

    // add the list of cell indices which belong to this core
};

struct  SpriteAssetRope {
    SpriteRopeAnchor anchor_a;
    SpriteRopeAnchor anchor_b;
    Color4 color;
    godot::LocalVector<godot::Vector2i> path; // ordered cells from a to b
    uint8_t cell_class = 0; // armor class carried from the source cells
};

struct  SpriteAssetChunk {
    Color4 color[k_cells_per_chunk * k_cells_per_chunk];
    SpriteCellMaskBits mask[k_cells_per_chunk * k_cells_per_chunk];
    godot::LocalVector<Color4> normal;

    int index;
    int activePixelCount;
    godot::Vector2i gridPixelOffset;
};

struct  SpriteAssetCellGroup {
    int activeCount;
    godot::Vector2i root_grid_index_position;
};

struct  SpriteAsset {
    godot::LocalVector<SpriteAssetChunk> chunks;
    godot::LocalVector<SpriteAssetCore> cores;
    godot::LocalVector<SpriteAssetRope> ropes;

    SpriteAssetCellGroup groups[SpriteCellMaskType_Count];
    int activePixelCount;

    godot::Vector2i chunkCount;
    godot::Vector2i cellCount;

    // Pixel position of a yellow (255,255,0) marker in the source image.
    // Used to align the sprite's origin to the spawn position.
    // {-1,-1} means no origin was found.
    godot::Vector2i pixelOrigin = godot::Vector2i(-1, -1);

    bool has_normal = false;
};
