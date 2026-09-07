#include "Grid.h"
#include "glm/geometric.hpp"
#include <cmath>

Grid::Grid()
    : chunkSize(0)
    , chunks(0)
    , cells(0) {}

Grid::Grid(int chunkSize, ivec2 chunkCount)
    : chunkSize(chunkSize)
    , chunks(chunkCount)
    , cells(chunkSize * chunkCount) {}

Grid Grid::from_cells(int chunkSize, ivec2 cells) {
    ivec2 chunks = (cells + chunkSize - 1) / chunkSize;
    return Grid(chunkSize, chunks);
}

int Grid::total_cells_in_chunk() const {
    return chunkSize * chunkSize;
}

int Grid::total_chunks_in_grid() const {
    return chunks.x * chunks.y;
}

int Grid::total_cells_in_grid() const {
    return cells.x * cells.y;
}

int Grid::to_chunk_index(ivec2 chunkIndexPosition) const {
    return chunkIndexPosition.x + chunkIndexPosition.y * chunks.x;
}

ivec2 Grid::to_chunk_index_position(int chunkIndex) const {
    return ivec2(chunkIndex % chunks.x, chunkIndex / chunks.x);
}

int Grid::to_cell_index(ivec2 cellIndexPosition) const {
    return cellIndexPosition.x + cellIndexPosition.y * chunkSize;
}

ivec2 Grid::to_cell_index_position(int cellIndex) const {
    return ivec2(cellIndex % chunkSize, cellIndex / chunkSize);
}

vec2 Grid::to_grid_point(vec2 localPoint) const {
    return (localPoint + 1.f) * 0.5f * vec2(cells); // + 0.5f;
}

vec2 Grid::to_local_scale(vec2 gridPoint) const {
    return gridPoint / vec2(cells) * 2.f;
}

vec2 Grid::to_local_point(vec2 gridPoint) const {
    return to_local_scale(gridPoint) - 1.f;
}

vec2 Grid::to_local_point(ivec2 gridIndexPosition) const {
    return vec2(gridIndexPosition) / vec2(cells) * 2.f - 1.f;
}

vec2 Grid::to_local_point(int chunkIndex, int cellIndex) const {
    return to_local_point(to_grid_index_position(chunkIndex, cellIndex));
}

vec2 Grid::to_local_point_centered(vec2 gridPoint) const {
    return to_local_point(gridPoint + vec2(0.5f));
}

vec2 Grid::to_local_point_centered(ivec2 gridIndexPosition) const {
    return to_local_point_centered(vec2(gridIndexPosition));
}

vec2 Grid::to_local_point_centered(int chunkIndex, int cellIndex) const {
    return to_local_point_centered(to_grid_index_position(chunkIndex, cellIndex));
}

int Grid::to_grid_index(vec2 localPoint) const {
    ivec2 gridIndexPosition = to_grid_index_position(localPoint);
    return gridIndexPosition.x + gridIndexPosition.y * cells.x;
}

ivec2 Grid::to_grid_index_position(vec2 localPoint) const {
    return ivec2(to_grid_point(localPoint));
}

ivec2 Grid::to_grid_index_position(int chunkIndex, int cellIndex) const {
    ivec2 chunkPos = to_chunk_index_position(chunkIndex);
    ivec2 cellPos = to_cell_index_position(cellIndex);
    return to_grid_index_position(chunkPos, cellPos);
}

ivec2 Grid::to_grid_index_position(ivec2 chunkIndexPosition, ivec2 cellIndexPosition) const {
    return chunkIndexPosition * chunkSize + cellIndexPosition;
}

std::pair<int, int> Grid::to_chunk_cell_index(vec2 gridPoint) const {
    return to_chunk_cell_index(ivec2(gridPoint));
}

std::pair<int, int> Grid::to_chunk_cell_index(ivec2 gridIndexPosition) const {
    auto [chunkIndexPosition, cellIndexPosition] = to_chunk_cell_index_positions(gridIndexPosition);

    return {to_chunk_index(chunkIndexPosition), to_cell_index(cellIndexPosition)};
}

std::pair<ivec2, ivec2> Grid::to_chunk_cell_index_positions(ivec2 gridIndexPosition) const {
    return {gridIndexPosition / chunkSize, gridIndexPosition % chunkSize};
}

std::pair<vec2, vec2> Grid::calc_fractional_difference(vec2 gridPoint) const {
    ivec2 gridIndexPosition = ivec2(gridPoint);
    ivec2 chunkIndexPosition = gridIndexPosition / chunkSize;

    vec2 chunkDiff = gridPoint - vec2(chunkIndexPosition * chunkSize);
    vec2 cellDiff = gridPoint - vec2(gridIndexPosition);

    return {chunkDiff, cellDiff};
}

bool Grid::is_chunk_index_valid(int chunkIndex) const {
    return chunkIndex >= 0 && chunkIndex < total_chunks_in_grid();
}

bool Grid::is_chunk_index_position_valid(ivec2 chunkIndexPosition) const {
    return chunkIndexPosition.x >= 0 && chunkIndexPosition.y >= 0 && chunkIndexPosition.x < chunks.x && chunkIndexPosition.y < chunks.y;
}

bool Grid::is_cell_index_valid(int cellIndex) const {
    return cellIndex >= 0 && cellIndex < total_cells_in_chunk();
}

bool Grid::is_cell_index_position_valid(ivec2 cellIndexPosition) const {
    return cellIndexPosition.x >= 0 && cellIndexPosition.y >= 0 && cellIndexPosition.x < chunkSize && cellIndexPosition.y < chunkSize;
}

bool Grid::is_grid_index_valid(int gridIndex) const {
    return gridIndex >= 0 && gridIndex < total_cells_in_grid();
}

bool Grid::is_grid_index_position_valid(ivec2 gridIndexPosition) const {
    return gridIndexPosition.x >= 0 && gridIndexPosition.y >= 0 && gridIndexPosition.x < cells.x && gridIndexPosition.y < cells.y;
}

GridCellNeighbors Grid::get_cell_neighbors_in_bordering_chunks(ivec2 chunkIndexPosition, ivec2 cellIndexPosition) const {
    GridCellNeighbors neighbors{};

    neighbors.dir.left = {cellIndexPosition.x == 0 && chunkIndexPosition.x != 0,
                          ivec2(chunkIndexPosition.x - 1, chunkIndexPosition.y),
                          ivec2(chunkSize - 1, cellIndexPosition.y)};

    neighbors.dir.right = {cellIndexPosition.x == chunkSize - 1 && chunkIndexPosition.x != chunks.x - 1,
                           ivec2(chunkIndexPosition.x + 1, chunkIndexPosition.y),
                           ivec2(0, cellIndexPosition.y)};

    neighbors.dir.bottom = {cellIndexPosition.y == 0 && chunkIndexPosition.y != 0,
                            ivec2(chunkIndexPosition.x, chunkIndexPosition.y - 1),
                            ivec2(cellIndexPosition.x, chunkSize - 1)};

    neighbors.dir.top = {cellIndexPosition.y == chunkSize - 1 && chunkIndexPosition.y != chunks.y - 1,
                         ivec2(chunkIndexPosition.x, chunkIndexPosition.y + 1),
                         ivec2(cellIndexPosition.x, 0)};

    return neighbors;
}