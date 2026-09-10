#include <godot_cpp/templates/pair.hpp>
#include "Grid.h"

#include <cmath>

Grid::Grid()
    : chunkSize(0)
    , chunks(0, 0)
    , cells(0, 0) {}

Grid::Grid(int chunkSize, godot::Vector2i chunkCount)
    : chunkSize(chunkSize)
    , chunks(chunkCount)
    , cells(chunkSize * chunkCount.x, chunkSize * chunkCount.y) {}

Grid Grid::from_cells(int chunkSize, godot::Vector2i cells) {
    godot::Vector2i chunks = godot::Vector2i((cells.x + chunkSize - 1) / chunkSize, (cells.y + chunkSize - 1) / chunkSize);
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

int Grid::to_chunk_index(godot::Vector2i chunkIndexPosition) const {
    return chunkIndexPosition.x + chunkIndexPosition.y * chunks.x;
}

godot::Vector2i Grid::to_chunk_index_position(int chunkIndex) const {
    return godot::Vector2i(chunkIndex % chunks.x, chunkIndex / chunks.x);
}

int Grid::to_cell_index(godot::Vector2i cellIndexPosition) const {
    return cellIndexPosition.x + cellIndexPosition.y * chunkSize;
}

godot::Vector2i Grid::to_cell_index_position(int cellIndex) const {
    return godot::Vector2i(cellIndex % chunkSize, cellIndex / chunkSize);
}

godot::Vector2 Grid::to_grid_point(godot::Vector2 localPoint) const {
    return godot::Vector2((localPoint.x + 1.f) * 0.5f * cells.x, (localPoint.y + 1.f) * 0.5f * cells.y);
}

godot::Vector2 Grid::to_local_scale(godot::Vector2 gridPoint) const {
    return godot::Vector2(gridPoint.x / cells.x * 2.f, gridPoint.y / cells.y * 2.f);
}

godot::Vector2 Grid::to_local_point(godot::Vector2 gridPoint) const {
    godot::Vector2 s = to_local_scale(gridPoint);
    return godot::Vector2(s.x - 1.f, s.y - 1.f);
}

godot::Vector2 Grid::to_local_point(godot::Vector2i gridIndexPosition) const {
    return godot::Vector2(
        static_cast<float>(gridIndexPosition.x) / cells.x * 2.f - 1.f,
        static_cast<float>(gridIndexPosition.y) / cells.y * 2.f - 1.f
    );
}

godot::Vector2 Grid::to_local_point(int chunkIndex, int cellIndex) const {
    return to_local_point(to_grid_index_position(chunkIndex, cellIndex));
}

godot::Vector2 Grid::to_local_point_centered(godot::Vector2 gridPoint) const {
    return to_local_point(godot::Vector2(gridPoint.x + 0.5f, gridPoint.y + 0.5f));
}

godot::Vector2 Grid::to_local_point_centered(godot::Vector2i gridIndexPosition) const {
    return to_local_point_centered(godot::Vector2(static_cast<float>(gridIndexPosition.x), static_cast<float>(gridIndexPosition.y)));
}

godot::Vector2 Grid::to_local_point_centered(int chunkIndex, int cellIndex) const {
    return to_local_point_centered(to_grid_index_position(chunkIndex, cellIndex));
}

int Grid::to_grid_index(godot::Vector2 localPoint) const {
    godot::Vector2i gridIndexPosition = to_grid_index_position(localPoint);
    return gridIndexPosition.x + gridIndexPosition.y * cells.x;
}

godot::Vector2i Grid::to_grid_index_position(godot::Vector2 localPoint) const {
    godot::Vector2 g = to_grid_point(localPoint);
    return godot::Vector2i(static_cast<int>(g.x), static_cast<int>(g.y));
}

godot::Vector2i Grid::to_grid_index_position(int chunkIndex, int cellIndex) const {
    godot::Vector2i chunkPos = to_chunk_index_position(chunkIndex);
    godot::Vector2i cellPos = to_cell_index_position(cellIndex);
    return to_grid_index_position(chunkPos, cellPos);
}

godot::Vector2i Grid::to_grid_index_position(godot::Vector2i chunkIndexPosition, godot::Vector2i cellIndexPosition) const {
    return godot::Vector2i(chunkIndexPosition.x * chunkSize + cellIndexPosition.x, chunkIndexPosition.y * chunkSize + cellIndexPosition.y);
}

godot::Pair<int, int> Grid::to_chunk_cell_index(godot::Vector2 gridPoint) const {
    return to_chunk_cell_index(godot::Vector2i(static_cast<int>(gridPoint.x), static_cast<int>(gridPoint.y)));
}

godot::Pair<int, int> Grid::to_chunk_cell_index(godot::Vector2i gridIndexPosition) const {
    auto [chunkIndexPosition, cellIndexPosition] = to_chunk_cell_index_positions(gridIndexPosition);

    return {to_chunk_index(chunkIndexPosition), to_cell_index(cellIndexPosition)};
}

godot::Pair<godot::Vector2i, godot::Vector2i> Grid::to_chunk_cell_index_positions(godot::Vector2i gridIndexPosition) const {
    return {
        godot::Vector2i(gridIndexPosition.x / chunkSize, gridIndexPosition.y / chunkSize),
        godot::Vector2i(gridIndexPosition.x % chunkSize, gridIndexPosition.y % chunkSize)
    };
}

godot::Pair<godot::Vector2, godot::Vector2> Grid::calc_fractional_difference(godot::Vector2 gridPoint) const {
    godot::Vector2i gridIndexPosition = godot::Vector2i(static_cast<int>(gridPoint.x), static_cast<int>(gridPoint.y));
    godot::Vector2i chunkIndexPosition = godot::Vector2i(gridIndexPosition.x / chunkSize, gridIndexPosition.y / chunkSize);

    godot::Vector2 chunkDiff = gridPoint - godot::Vector2(chunkIndexPosition.x * chunkSize, chunkIndexPosition.y * chunkSize);
    godot::Vector2 cellDiff = gridPoint - godot::Vector2(gridIndexPosition.x, gridIndexPosition.y);

    return {chunkDiff, cellDiff};
}

bool Grid::is_chunk_index_valid(int chunkIndex) const {
    return chunkIndex >= 0 && chunkIndex < total_chunks_in_grid();
}

bool Grid::is_chunk_index_position_valid(godot::Vector2i chunkIndexPosition) const {
    return chunkIndexPosition.x >= 0 && chunkIndexPosition.y >= 0 && chunkIndexPosition.x < chunks.x && chunkIndexPosition.y < chunks.y;
}

bool Grid::is_cell_index_valid(int cellIndex) const {
    return cellIndex >= 0 && cellIndex < total_cells_in_chunk();
}

bool Grid::is_cell_index_position_valid(godot::Vector2i cellIndexPosition) const {
    return cellIndexPosition.x >= 0 && cellIndexPosition.y >= 0 && cellIndexPosition.x < chunkSize && cellIndexPosition.y < chunkSize;
}

bool Grid::is_grid_index_valid(int gridIndex) const {
    return gridIndex >= 0 && gridIndex < total_cells_in_grid();
}

bool Grid::is_grid_index_position_valid(godot::Vector2i gridIndexPosition) const {
    return gridIndexPosition.x >= 0 && gridIndexPosition.y >= 0 && gridIndexPosition.x < cells.x && gridIndexPosition.y < cells.y;
}

GridCellNeighbors Grid::get_cell_neighbors_in_bordering_chunks(godot::Vector2i chunkIndexPosition, godot::Vector2i cellIndexPosition) const {
    GridCellNeighbors neighbors{};

    neighbors.dir.left = {cellIndexPosition.x == 0 && chunkIndexPosition.x != 0,
                          godot::Vector2i(chunkIndexPosition.x - 1, chunkIndexPosition.y),
                          godot::Vector2i(chunkSize - 1, cellIndexPosition.y)};

    neighbors.dir.right = {cellIndexPosition.x == chunkSize - 1 && chunkIndexPosition.x != chunks.x - 1,
                           godot::Vector2i(chunkIndexPosition.x + 1, chunkIndexPosition.y),
                           godot::Vector2i(0, cellIndexPosition.y)};

    neighbors.dir.bottom = {cellIndexPosition.y == 0 && chunkIndexPosition.y != 0,
                            godot::Vector2i(chunkIndexPosition.x, chunkIndexPosition.y - 1),
                            godot::Vector2i(cellIndexPosition.x, chunkSize - 1)};

    neighbors.dir.top = {cellIndexPosition.y == chunkSize - 1 && chunkIndexPosition.y != chunks.y - 1,
                         godot::Vector2i(chunkIndexPosition.x, chunkIndexPosition.y + 1),
                         godot::Vector2i(cellIndexPosition.x, 0)};

    return neighbors;
}
