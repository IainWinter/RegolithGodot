#pragma once

#include "Result.h"

#include "glm/vec2.hpp"
using namespace glm;

struct GridCellNeighbors {
    struct ChunkCellIndexPosition {
        bool exists;
        ivec2 chunkIndexPosition;
        ivec2 cellIndexPosition;
    };

    union {
        ChunkCellIndexPosition cells[4];

        struct {
            ChunkCellIndexPosition left;
            ChunkCellIndexPosition right;
            ChunkCellIndexPosition bottom;
            ChunkCellIndexPosition top;
        } dir;
    };
};

/*
 * A grid which spans a Transform.
 *
 * Some terms:

 * 1d:
 *  - chunkIndex: (0) -> (chunks.x * chunks.y) 1d index of chunk
 *  - cellIndex: (0) -> (cells.x * cells.y) 1d index of cell within a single chunk
 *  - gridIndex: (0) -> (chunks.x * chunks.y * cells.x * cells.y) 1d index of cell within the grid
 *
 * 2d:
 *  - cellIndexPosition: (0, 0) -> (cells.x, cells.y) integer which spans a single chunks
 *  - chunkIndexPosition: (0, 0) -> (chunks.x, chunks.y) integer which spans chunks
 *  - gridIndexPosition: (0, 0) -> (w, h) integer which spans the grid
 *
 * 2d floating:
 *  - localPoint: (-1, -1) -> (1, 1) floating point which spans the grid
 *  - gridPoint: (0, 0) -> (w, h) floating point which spans the grid
 *
 * Translations:
 *  - localPoint -> gridPoint
 *  - localPoint -> gridIndexPosition
 *  - (chunkIndex, cellIndex) -> gridPoint
 *  - (chunkIndex, cellIndex) -> gridIndexPosition
*/
struct [[Struct]] Grid {
    int chunkSize;
    ivec2 chunks;
    ivec2 cells;

    Grid();

    Grid(int chunkSize, ivec2 chunks);

    static Grid from_cells(int chunkSize, ivec2 cells);

    // Counts

    int total_cells_in_chunk() const;

    int total_chunks_in_grid() const;

    int total_cells_in_grid() const;

    // Sort these

    int to_chunk_index(ivec2 chunkIndexPosition) const;

    ivec2 to_chunk_index_position(int chunkIndex) const;

    int to_cell_index(ivec2 cellIndexPosition) const;

    ivec2 to_cell_index_position(int cellIndex) const;

    vec2 to_grid_point(vec2 localPoint) const;

    vec2 to_local_scale(vec2 gridPoint) const;

    vec2 to_local_point(vec2 gridPoint) const;

    vec2 to_local_point(ivec2 gridIndexPosition) const;

    vec2 to_local_point(int chunkIndex, int cellIndex) const;

    vec2 to_local_point_centered(vec2 gridPoint) const;

    vec2 to_local_point_centered(ivec2 gridIndexPosition) const;

    vec2 to_local_point_centered(int chunkIndex, int cellIndex) const;

    int to_grid_index(vec2 localPoint) const;

    ivec2 to_grid_index_position(vec2 localPoint) const;

    ivec2 to_grid_index_position(int chunkIndex, int cellIndex) const;

    ivec2 to_grid_index_position(ivec2 chunkIndexPosition, ivec2 cellIndexPosition) const;

    std::pair<int, int> to_chunk_cell_index(vec2 gridPoint) const;

    std::pair<int, int> to_chunk_cell_index(ivec2 gridIndexPosition) const;

    std::pair<ivec2, ivec2> to_chunk_cell_index_positions(ivec2 gridIndexPosition) const;

    std::pair<vec2, vec2> calc_fractional_difference(vec2 gridPoint) const;

    bool is_chunk_index_valid(int chunkIndex) const;

    bool is_chunk_index_position_valid(ivec2 chunkIndexPosition) const;

    bool is_cell_index_valid(int cellIndex) const;

    bool is_cell_index_position_valid(ivec2 cellIndexPosition) const;

    bool is_grid_index_valid(int gridIndex) const;

    bool is_grid_index_position_valid(ivec2 gridIndexPosition) const;

    GridCellNeighbors get_cell_neighbors_in_bordering_chunks(ivec2 chunkIndexPosition, ivec2 cellIndexPosition) const;
};
