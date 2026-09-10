#pragma once

#include "SpriteCell.h"

#include "Containers/ArrayView.h"
#include "Containers/FixedArray.h"

#include "Constants.h"

#include "Math/Vector.h"

#include <godot_cpp/templates/local_vector.hpp>

#include <climits>

// For max performance this uses the constant size for chunks

using FloodFillAdjacencyArray = FixedArray<int, k_cells_per_chunk>;

struct FloodFillResult {
    int seedIndex;
    godot::LocalVector<int> index;
    godot::Vector2i min = godot::Vector2i( INT_MAX,  INT_MAX);
    godot::Vector2i max = godot::Vector2i(-INT_MAX, -INT_MAX);

    FloodFillAdjacencyArray indexContinueUp;
    FloodFillAdjacencyArray indexContinueDown;
    FloodFillAdjacencyArray indexContinueLeft;
    FloodFillAdjacencyArray indexContinueRight;

    // Number of edges which have visited pixels on them
    int adjacencyCount;

    // Random data not needed, remove after splitcutter1 is removed
    int chunkIndex;

    // For tracking who should be the core
    int typeCounts[SpriteCellMaskType_Count];

    bool operator==(const FloodFillResult& other) const {
        if (seedIndex != other.seedIndex
            || min != other.min
            || max != other.max
            || indexContinueUp != other.indexContinueUp
            || indexContinueDown != other.indexContinueDown
            || indexContinueLeft != other.indexContinueLeft
            || indexContinueRight != other.indexContinueRight
            || adjacencyCount != other.adjacencyCount
            || chunkIndex != other.chunkIndex) {
            return false;
        }
        if (index.size() != other.index.size()) return false;
        for (uint32_t i = 0; i < index.size(); i++) if (index[i] != other.index[i]) return false;
        for (int i = 0; i < SpriteCellMaskType_Count; i++) if (typeCounts[i] != other.typeCounts[i]) return false;
        return true;
    }
};

// Much slower heap based for unknown sizes of chunk
FloodFillResult flood_fill(int seed, int id, int size, const SpriteCellMask* mask, int* working);

// Faster stack based for k_cells_per_chunk
FloodFillResult flood_fill32(int seed, int id, const SpriteCellMask* mask, int* working);
