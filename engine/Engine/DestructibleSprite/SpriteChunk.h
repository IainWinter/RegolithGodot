#pragma once

#include "Color.h"
#include "Containers/ArrayView.h"
#include "Constants.h"
#include "Assets/SpriteAsset.h"
#include "SpriteCell.h"

#include "Coordinate/Grid.h"
#include "Math/Vector.h"

#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/templates/pair.hpp>

// Each chunk will store:
//  1. Color   RGBA     (4 bytes)   Host, Device             Read on host for effects 
//  2. Normal  RGB      (3 bytes)   Host?, Device            Could be read on host for effects
//  3. Mask    R        (1 byte)    Host, Device   (dynamic) If a cell is filled, reduce texture upload represents fill or non filled pixels on gpu
//  4. Cell    a struct (arbitrary) Host                     Info about joints and health

// this can all be compressed if storage becomes an issue

enum SpriteChunkState {
    SpriteChunkState_New,
    SpriteChunkState_Dirty,
    SpriteChunkState_Delete,
};

using SpriteChunkId = uint32_t;

class SpriteChunk;

struct SpriteChunkNeighbors {
    SpriteChunk* left;
    SpriteChunk* right;
    SpriteChunk* up;
    SpriteChunk* down;
};

// all 8 neighbors, the diagonals matter for the distance field
struct SpriteChunkNeighbors8 {
    SpriteChunk* chunks[9]; // [(x + 1) + (y + 1) * 3], center is self

    SpriteChunk*& at(int dx, int dy) {
        return chunks[(dx + 1) + (dy + 1) * 3];
    }

    SpriteChunk* at(int dx, int dy) const {
        return chunks[(dx + 1) + (dy + 1) * 3];
    }
};

class SpriteChunk {
public:
    void reset();

    void remove_cell(int cellIndex);

    void repair_cell(int cellIndex);

    void calc_surface(const Grid& grid, const SpriteChunkNeighbors& neighbors);

    // rebuild this chunk's distance data from its own cells plus up to one
    // band into the neighbors. writes only this chunk, so chunks can recalc
    // in any order or in parallel. exact because the band is smaller than a
    // chunk, structure further away than the band never shows up in here
    void calc_distance_field(const Grid& grid, const SpriteChunkNeighbors8& neighbors);

public:
    SpriteChunkId id;
    int index;
    
    godot::Vector2i gridPixelOffset;
    godot::Vector3i atlasPixelOffset;
    godot::Vector3 uvwOffset;

    int activePixelCount;

    ArrayView<Color4> color;
    ArrayView<Color4> normal;
    ArrayView<SpriteCellMask> mask;

    // signed distance to the sprite's structure in cell units, positive
    // outside, clamped to +-k_sdf_band_cells. rebuilt by sprite_distance_field_build
    ArrayView<float> distance;

    // corner and round cells, the physics sample points
    godot::LocalVector<godot::Pair<godot::Vector2i, int>> surface;
};