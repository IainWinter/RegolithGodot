#pragma once

#include "SpriteCell.h"

#include "ArrayView.h"
#include "FixedArray.h"

#include "Constants.h"

#include "glm/vec2.hpp"
using namespace glm;

#include <vector>
#include <array>
#include <climits>

// For max performance this uses the constant size for chunks

using FloodFillAdjacencyArray = FixedArray<int, k_cells_per_chunk>;

struct FloodFillResult {
    int seedIndex;
    std::vector<int> index;
    ivec2 min = ivec2( INT_MAX);
    ivec2 max = ivec2(-INT_MAX);

    FloodFillAdjacencyArray indexContinueUp;
    FloodFillAdjacencyArray indexContinueDown;
    FloodFillAdjacencyArray indexContinueLeft;
    FloodFillAdjacencyArray indexContinueRight;

    // Number of edges which have visited pixels on them
    int adjacencyCount;

    // Random data not needed, remove after splitcutter1 is removed
    int chunkIndex;

    // For tracking who should be the core
    std::array<int, SpriteCellMaskType_Count> typeCounts;

    bool operator==(const FloodFillResult& other) const {
        return seedIndex == other.seedIndex
            && index == other.index
            && min == other.min
            && max == other.max
            && indexContinueUp == other.indexContinueUp
            && indexContinueDown == other.indexContinueDown
            && indexContinueLeft == other.indexContinueLeft
            && indexContinueRight == other.indexContinueRight
            && adjacencyCount == other.adjacencyCount
            && chunkIndex == other.chunkIndex
            && typeCounts == other.typeCounts;
    }
};

// Much slower heap based for unknown sizes of chunk
FloodFillResult flood_fill(int seed, int id, int size, const SpriteCellMask* mask, int* working);

// Faster stack based for k_cells_per_chunk
FloodFillResult flood_fill32(int seed, int id, const SpriteCellMask* mask, int* working);