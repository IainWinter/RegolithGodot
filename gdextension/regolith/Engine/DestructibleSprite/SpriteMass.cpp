#include "SpriteMass.h"

constexpr static float s_mass_per_cell = 1.f / k_cells_per_chunk_total;

constexpr static float s_inertia_per_cell = (2.f / 3.f) 
                                          * (1.f / k_cells_per_chunk_total) 
                                          * (k_cell_local_size / 2.f) 
                                          * (k_cell_local_size / 2.f);

SpriteMass sprite_mass_init(const Grid& grid, const FlatMap<SpriteChunk*>& chunks) {
    SpriteMass mass{};

    for (const SpriteChunk* chunk : chunks.items()) {
        for (int i = 0; i < grid.total_cells_in_chunk(); i++) {
            if (chunk->mask[i].is_empty()) {
                continue;
            }

            ivec2 cell = grid.to_grid_index_position(chunk->index, i);

            mass.sum_ix += cell.x;
            mass.sum_iy += cell.y;
            mass.sum_ix2 += cell.x * cell.x;
            mass.sum_iy2 += cell.y * cell.y;
            mass.active_cell_count += 1;
        }
    }

    return mass;
}

SpriteMassInfo sprite_mass_get_info(const SpriteMass& mass, const Grid& grid) {
    if (mass.active_cell_count == 0) {
        return {};
    }

    SpriteMassInfo info{};

    float n = static_cast<float>(mass.active_cell_count);
    float s = k_cell_local_size;
    float s2 = s * s;

    float cx = (mass.sum_ix / n + 0.5f) * s;
    float cy = (mass.sum_iy / n + 0.5f) * s;

    float sum_x2 = (mass.sum_ix2 + mass.sum_ix + 0.25f * n) * s2;
    float sum_y2 = (mass.sum_iy2 + mass.sum_iy + 0.25f * n) * s2;

    float sum_r2 = sum_x2 + sum_y2;
    float offset_term = sum_r2 - n * (cx*cx + cy*cy);

    info.inertia = n * s_inertia_per_cell + s_mass_per_cell * offset_term;
    info.mass = n * s_mass_per_cell;
    info.center_of_mass = grid.to_local_point_centered(vec2(mass.sum_ix, mass.sum_iy) / n);
    info.inv_mass = 1.f / info.mass;
    info.inv_inertia = 1.f / info.inertia;

    return info;
}

void sprite_mass_add_cell(SpriteMass& mass, ivec2 grid_index_position) {
    mass.sum_ix += grid_index_position.x;
    mass.sum_iy += grid_index_position.y;
    mass.sum_ix2 += grid_index_position.x * grid_index_position.x;
    mass.sum_iy2 += grid_index_position.y * grid_index_position.y;
    mass.active_cell_count += 1;
}

void sprite_mass_remove_cell(SpriteMass& mass, ivec2 grid_index_position) {
    mass.sum_ix -= grid_index_position.x;
    mass.sum_iy -= grid_index_position.y;
    mass.sum_ix2 -= grid_index_position.x * grid_index_position.x;
    mass.sum_iy2 -= grid_index_position.y * grid_index_position.y;
    mass.active_cell_count -= 1;
}

SpriteMass sprite_mass_init_from_asset(const SpriteAsset& asset) {
    SpriteMass mass{};
    for (const SpriteAssetChunk& chunk : asset.chunks) {
        for (int ly = 0; ly < k_cells_per_chunk; ly++) {
            for (int lx = 0; lx < k_cells_per_chunk; lx++) {
                int i = lx + ly * k_cells_per_chunk;
                if (SpriteCellMask(chunk.mask[i]).is_empty()) {
                    continue;
                }
                int gx = chunk.gridPixelOffset.x + lx;
                int gy = chunk.gridPixelOffset.y + ly;
                mass.sum_ix += gx;
                mass.sum_iy += gy;
                mass.sum_ix2 += gx * gx;
                mass.sum_iy2 += gy * gy;
                mass.active_cell_count += 1;
            }
        }
    }
    return mass;
}

SpriteMassInfo sprite_mass_get_info_from_asset(const SpriteAsset& asset) {
    Grid grid(k_cells_per_chunk, asset.chunkCount);
    SpriteMass m = sprite_mass_init_from_asset(asset);
    return sprite_mass_get_info(m, grid);
}