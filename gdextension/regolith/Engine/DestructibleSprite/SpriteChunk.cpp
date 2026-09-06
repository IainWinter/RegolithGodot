#include "SpriteChunk.h"

#include "Algorithm/MarchingSquares.h"
#include "Algorithm/SpriteDistanceField.h"
#include "Constants.h"
#include "Math/MathUtil.h"

#include "glm/geometric.hpp"

void SpriteChunk::reset() {
    surface = {};
}

void SpriteChunk::remove_cell(int cellIndex) {
    activePixelCount -= 1;
    mask[cellIndex].set_removed(true);
}

void SpriteChunk::repair_cell(int cellIndex) {
    activePixelCount += 1;
    mask[cellIndex].set_removed(false);
}

void SpriteChunk::calc_surface(const Grid& grid, const SpriteChunkNeighbors& neighbors) {
    surface = {};

    auto is_filled = [&](int index, bool at_edge, const SpriteChunk* neighbor, int neighbor_index) {
        SpriteCellMask m = at_edge ? (neighbor ? neighbor->mask[neighbor_index] : SpriteCellMask()) : mask[index];
        return m.is_filled();
    };

    int size = grid.chunkSize;

    for (int x = 0; x < size; x++) {
        for (int y = 0; y < size; y++) {
            int cellIndex = x + y * size;

            if (mask[cellIndex].is_empty()) {
                continue;
            }

            int cellIndexUp = cellIndex + size;
            int cellIndexDown = cellIndex - size;
            int cellIndexLeft = cellIndex - 1;
            int cellIndexRight = cellIndex + 1;

            bool atUp = y == size - 1;
            bool atDown = y == 0;
            bool atLeft = x == 0;
            bool atRight = x == size - 1;

            bool up = is_filled(cellIndexUp, atUp, neighbors.up, edge_index_up(x, y, size));
            bool down = is_filled(cellIndexDown, atDown, neighbors.down, edge_index_down(x, y, size));
            bool left = is_filled(cellIndexLeft, atLeft, neighbors.left, edge_index_left(x, y, size));
            bool right = is_filled(cellIndexRight, atRight, neighbors.right, edge_index_right(x, y, size));

            // flat edge runs and interiors are not sample points
            constexpr bool points[16] = {
                true, true, true, true,
                true, true, true, false,
                true, true, true, false,
                true, false, false, false,
            };

            int infoIndex = (up << 3) | (down << 2) | (left << 1) | (right << 0);

            if (points[infoIndex]) {
                surface.emplace_back(ivec2(x, y), cellIndex);
            }
        }
    }
}
void SpriteChunk::calc_distance_field(const Grid& grid, const SpriteChunkNeighbors8& neighbors) {
    int band = static_cast<int>(k_sdf_band_cells) + 1;
    int cs = grid.chunkSize;

    ivec2 size(cs + 2 * band);
    ivec2 window_min = gridPixelOffset - band;

    std::vector<uint8_t> filled(size.x * size.y, 0u);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            const SpriteChunk* chunk = dx == 0 && dy == 0 ? this : neighbors.at(dx, dy);

            if (!chunk) {
                continue;
            }

            ivec2 lo = glm::max(window_min, chunk->gridPixelOffset);
            ivec2 hi = glm::min(window_min + size, chunk->gridPixelOffset + ivec2(cs));

            for (int y = lo.y; y < hi.y; y++) {
                for (int x = lo.x; x < hi.x; x++) {
                    ivec2 cell = ivec2(x, y) - chunk->gridPixelOffset;
                    SpriteCellMask cell_mask = chunk->mask[cell.x + cell.y * cs];

                    if (!cell_mask.is_filled()) {
                        continue;
                    }

                    ivec2 p = ivec2(x, y) - window_min;
                    filled[p.x + p.y * size.x] = 1u;
                }
            }
        }
    }

    std::vector<float> field = sprite_distance_field_compute(filled.data(), size);

    for (int y = 0; y < cs; y++) {
        for (int x = 0; x < cs; x++) {
            distance[x + y * cs] = field[(x + band) + (y + band) * size.x];
        }
    }
}
