#pragma once

#include "AssetMetadata.h"
#include "Constants.h"
#include "Color.h"
#include "SpriteCell.h"
#include "DestructibleSprite/SpriteRopeScan.h"

#include "Math/Vector.h"

#include <array>
#include <vector>
#include <string_view>

// end sprite enum stuff

struct [[Struct]] SpriteAssetCore {
    ivec2 min;
    ivec2 max;
    int width;
    int height;
    vec2 gridPointOffset;
    SpriteCellMaskType type;
    int initialCellCount;
    std::vector<Color4> color;

    // add the list of cell indices which belong to this core
};

struct [[Struct]] SpriteAssetRope {
    SpriteRopeAnchor anchor_a;
    SpriteRopeAnchor anchor_b;
    Color4 color;
    std::vector<ivec2> path; // ordered cells from a to b
    uint8_t cell_class = 0; // armor class carried from the source cells
};

struct [[Struct]] SpriteAssetChunk {
    std::array<Color4, k_cells_per_chunk * k_cells_per_chunk> color;
    std::array<SpriteCellMaskBits, k_cells_per_chunk * k_cells_per_chunk> mask; // cant store bitfields in serializer
    std::vector<Color4> normal; // empty when sprite has no normal texture

    int index;
    int activePixelCount;
    ivec2 gridPixelOffset;
};

struct [[Struct]] SpriteAssetCellGroup {
    int activeCount;
    ivec2 root_grid_index_position;
};

struct [[Struct]] SpriteAsset {
    AssetMetadata metadata;

    std::vector<SpriteAssetChunk> chunks;
    std::vector<SpriteAssetCore> cores;
    std::vector<SpriteAssetRope> ropes;

    std::array<SpriteAssetCellGroup, SpriteCellMaskType_Count> groups;
    int activePixelCount;

    ivec2 chunkCount;
    ivec2 cellCount;

    // Pixel position of a yellow (255,255,0) marker in the source image.
    // Used to align the sprite's origin to the spawn position.
    // {-1,-1} means no origin was found.
    ivec2 pixelOrigin = ivec2(-1, -1);

    bool has_normal = false;
};
