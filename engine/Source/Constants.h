#pragma once

// a chunk is the unit of storage, physics and the atlas. sprites are grids of
// chunks, one sim unit is one chunk wide
constexpr int k_cells_per_chunk = 32;

constexpr int k_cells_per_chunk_total = k_cells_per_chunk * k_cells_per_chunk;

// a chunk covers this much of a sprite's -1..1 local space at scale 1
constexpr float k_chunk_local_size = 0.5f;

constexpr float k_cell_local_size = k_chunk_local_size / k_cells_per_chunk;

// signed distance fields stored on chunks clamp to this many cells
constexpr float k_sdf_band_cells = 8.f;

constexpr int k_atlas_page_size = 1024;

// empty cells around every chunk in the atlas so a quad edge that lands on a
// slot boundary never samples the neighbour chunk. 1 each side, 2 between
constexpr int k_atlas_chunk_padding = 1;

constexpr int k_atlas_page_count = 8;

constexpr float k_sprite_density = 100.f;

constexpr float k_sprite_min_mass = 10.f;

constexpr int k_max_sprite_size = 4000;

// the game camera shows this many sim units top to bottom
constexpr float k_camera_height = 5.f;
