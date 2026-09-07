#pragma once

#include "DestructibleSprite/Sprite.h"
#include "Math/MathUtil.h"
#include "Constants.h"

#include <inttypes.h>
#include <vector>

// Signed distance to the sprite's structure in cell units, positive outside,
// negative inside, clamped to +-k_sdf_band_cells. The values live on each
// chunk's distance array from the chunk pool and each chunk computes its own
// in SpriteChunk::calc_distance_field from itself plus its 8 neighbors, so
// there is no ordering between chunks. The value at a cell is the distance at
// that cell's center. Rope display cells don't count as structure

// exact squared euclidean distance transform on a raw mask
std::vector<float> sprite_distance_field_compute(const uint8_t* filled, ivec2 size);

// rebuild every chunk's distance data
void sprite_distance_field_build(Sprite& sprite);

// recalc the dirty chunks and their neighbors after cells changed, the
// neighbors see the changed cells through their band overlap. the dirty set
// and their neighbors are unioned so a shared chunk is only recomputed once
void sprite_distance_field_update_chunks(Sprite& sprite, const std::vector<SpriteChunk*>& dirtyChunks);

// sampling lives in the header so the solver's hot loops can inline it

inline float sprite_distance_field_tap(const Sprite& sprite, ivec2 p) {
    auto [chunk_index, cell_index] = sprite.grid().to_chunk_cell_index(p);

    SpriteChunk* chunk = nullptr;

    if (!sprite.chunks().try_get(chunk_index, &chunk)) {
        return k_sdf_band_cells;
    }

    return chunk->distance[cell_index];
}

// bilinear sample at a fractional grid point. points outside the grid or in
// missing chunks read as the band. points off the grid edge also add their
// distance to the border
inline float sprite_distance_field_sample(const Sprite& sprite, vec2 gridPoint) {
    ivec2 size = sprite.grid().cells;

    vec2 p = gridPoint - 0.5f;

    vec2 lo(0.f);
    vec2 hi(vec2(size) - 1.f);

    vec2 clamped = glm::clamp(p, lo, hi);
    float border = distance(p, clamped);

    int x0 = static_cast<int>(floorf(clamped.x));
    int y0 = static_cast<int>(floorf(clamped.y));
    int x1 = glm::min(x0 + 1, size.x - 1);
    int y1 = glm::min(y0 + 1, size.y - 1);

    float tx = clamped.x - x0;
    float ty = clamped.y - y0;

    float v00 = sprite_distance_field_tap(sprite, ivec2(x0, y0));
    float v10 = sprite_distance_field_tap(sprite, ivec2(x1, y0));
    float v01 = sprite_distance_field_tap(sprite, ivec2(x0, y1));
    float v11 = sprite_distance_field_tap(sprite, ivec2(x1, y1));

    float v = (v00 * (1.f - tx) + v10 * tx) * (1.f - ty)
            + (v01 * (1.f - tx) + v11 * tx) * ty;

    return v + border;
}

// unit gradient in grid space via central differences, zero when the field
// is flat
inline vec2 sprite_distance_field_gradient(const Sprite& sprite, vec2 gridPoint) {
    constexpr float h = 0.5f;

    vec2 g(
        sprite_distance_field_sample(sprite, gridPoint + vec2(h, 0.f)) - sprite_distance_field_sample(sprite, gridPoint - vec2(h, 0.f)),
        sprite_distance_field_sample(sprite, gridPoint + vec2(0.f, h)) - sprite_distance_field_sample(sprite, gridPoint - vec2(0.f, h)));

    return safe_normalize(g);
}
