#pragma once

#include "SpriteChunk.h"
#include "FlatMap.h"

#include "Assets/SpriteAsset.h"

#include <stdint.h>

struct [[Struct]] SpriteMass {
    uint64_t sum_ix;
    uint64_t sum_iy;
    uint64_t sum_ix2;
    uint64_t sum_iy2;
    uint64_t active_cell_count;
};

struct SpriteMassInfo {
    vec2 center_of_mass;
    float inertia;
    float mass;
    float inv_inertia;
    float inv_mass;
};

SpriteMass sprite_mass_init(const Grid& grid, const FlatMap<SpriteChunk*>& chunks);

SpriteMass sprite_mass_init_from_asset(const SpriteAsset& asset);

SpriteMassInfo sprite_mass_get_info(const SpriteMass& mass, const Grid& grid);

SpriteMassInfo sprite_mass_get_info_from_asset(const SpriteAsset& asset);

void sprite_mass_add_cell(SpriteMass& mass, ivec2 grid_index_position);

void sprite_mass_remove_cell(SpriteMass& mass, ivec2 grid_index_position);
