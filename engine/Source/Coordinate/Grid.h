#pragma once

#include "Result.h"
#include "Math/Vector.h"

#include <godot_cpp/templates/pair.hpp>

struct GridCellNeighbors {
    struct ChunkCellIndexPosition {
        bool exists;
        godot::Vector2i chunkIndexPosition;
        godot::Vector2i cellIndexPosition;
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
struct  Grid {
    int chunkSize;
    godot::Vector2i chunks;
    godot::Vector2i cells;

    Grid();

    Grid(int chunkSize, godot::Vector2i chunks);

    static Grid from_cells(int chunkSize, godot::Vector2i cells);

    // Counts

    int total_cells_in_chunk() const;

    int total_chunks_in_grid() const;

    int total_cells_in_grid() const;

    // Sort these

    int to_chunk_index(godot::Vector2i chunkIndexPosition) const;

    godot::Vector2i to_chunk_index_position(int chunkIndex) const;

    int to_cell_index(godot::Vector2i cellIndexPosition) const;

    godot::Vector2i to_cell_index_position(int cellIndex) const;

    godot::Vector2 to_grid_point(godot::Vector2 localPoint) const;

    godot::Vector2 to_local_scale(godot::Vector2 gridPoint) const;

    godot::Vector2 to_local_point(godot::Vector2 gridPoint) const;

    godot::Vector2 to_local_point(godot::Vector2i gridIndexPosition) const;

    godot::Vector2 to_local_point(int chunkIndex, int cellIndex) const;

    godot::Vector2 to_local_point_centered(godot::Vector2 gridPoint) const;

    godot::Vector2 to_local_point_centered(godot::Vector2i gridIndexPosition) const;

    godot::Vector2 to_local_point_centered(int chunkIndex, int cellIndex) const;

    int to_grid_index(godot::Vector2 localPoint) const;

    godot::Vector2i to_grid_index_position(godot::Vector2 localPoint) const;

    godot::Vector2i to_grid_index_position(int chunkIndex, int cellIndex) const;

    godot::Vector2i to_grid_index_position(godot::Vector2i chunkIndexPosition, godot::Vector2i cellIndexPosition) const;

    godot::Pair<int, int> to_chunk_cell_index(godot::Vector2 gridPoint) const;

    godot::Pair<int, int> to_chunk_cell_index(godot::Vector2i gridIndexPosition) const;

    godot::Pair<godot::Vector2i, godot::Vector2i> to_chunk_cell_index_positions(godot::Vector2i gridIndexPosition) const;

    godot::Pair<godot::Vector2, godot::Vector2> calc_fractional_difference(godot::Vector2 gridPoint) const;

    bool is_chunk_index_valid(int chunkIndex) const;

    bool is_chunk_index_position_valid(godot::Vector2i chunkIndexPosition) const;

    bool is_cell_index_valid(int cellIndex) const;

    bool is_cell_index_position_valid(godot::Vector2i cellIndexPosition) const;

    bool is_grid_index_valid(int gridIndex) const;

    bool is_grid_index_position_valid(godot::Vector2i gridIndexPosition) const;

    GridCellNeighbors get_cell_neighbors_in_bordering_chunks(godot::Vector2i chunkIndexPosition, godot::Vector2i cellIndexPosition) const;
};
