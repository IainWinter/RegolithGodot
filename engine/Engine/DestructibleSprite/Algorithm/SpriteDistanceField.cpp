#include <algorithm>
#include "SpriteDistanceField.h"

#include "DestructibleSprite/Sprite.h"
#include "Math/MathUtil.h"
#include "Constants.h"

#include <cmath>
#include <godot_cpp/templates/hash_set.hpp>

static constexpr float k_edt_inf = 1e20f;

// Felzenszwalb-Huttenlocher 1d squared distance transform along one line
static void edt_1d(const float* f, float* d, int* v, float* z, int n) {
    int k = 0;
    v[0] = 0;
    z[0] = -k_edt_inf;
    z[1] = k_edt_inf;

    for (int q = 1; q < n; q++) {
        float s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.f * q - 2.f * v[k]);

        while (s <= z[k]) {
            k -= 1;
            s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.f * q - 2.f * v[k]);
        }

        k += 1;
        v[k] = q;
        z[k] = s;
        z[k + 1] = k_edt_inf;
    }

    k = 0;

    for (int q = 0; q < n; q++) {
        while (z[k + 1] < q) {
            k += 1;
        }

        float dq = static_cast<float>(q - v[k]);
        d[q] = dq * dq + f[v[k]];
    }
}

// squared distance to the nearest zero cell, rows then columns
static void edt_squared(godot::LocalVector<float>& field, godot::Vector2i size) {
    int n = std::max(size.x, size.y);

    godot::LocalVector<float> f; f.resize(n);
    godot::LocalVector<float> d; d.resize(n);
    godot::LocalVector<int> v; v.resize(n);
    godot::LocalVector<float> z; z.resize(n + 1);

    for (int y = 0; y < size.y; y++) {
        edt_1d(&field[y * size.x], d.ptr(), v.ptr(), z.ptr(), size.x);

        for (int x = 0; x < size.x; x++) {
            field[x + y * size.x] = d[x];
        }
    }

    for (int x = 0; x < size.x; x++) {
        for (int y = 0; y < size.y; y++) {
            f[y] = field[x + y * size.x];
        }

        edt_1d(f.ptr(), d.ptr(), v.ptr(), z.ptr(), size.y);

        for (int y = 0; y < size.y; y++) {
            field[x + y * size.x] = d[y];
        }
    }
}

godot::LocalVector<float> sprite_distance_field_compute(const uint8_t* filled, godot::Vector2i size) {
    int total = size.x * size.y;

    godot::LocalVector<float> outside; outside.resize(total);
    godot::LocalVector<float> inside; inside.resize(total);

    for (int i = 0; i < total; i++) {
        outside[i] = filled[i] ? 0.f : k_edt_inf;
        inside[i] = filled[i] ? k_edt_inf : 0.f;
    }

    edt_squared(outside, size);
    edt_squared(inside, size);

    godot::LocalVector<float> field; field.resize(total);

    for (int i = 0; i < total; i++) {
        float signed_distance = filled[i] ? 0.5f - sqrtf(inside[i]) : sqrtf(outside[i]) - 0.5f;

        field[i] = clamp(signed_distance, -k_sdf_band_cells, k_sdf_band_cells);
    }

    return field;
}

static SpriteChunkNeighbors8 gather_neighbors(const Sprite& sprite, int chunkIndex) {
    const Grid& grid = sprite.grid();

    godot::Vector2i cp = grid.to_chunk_index_position(chunkIndex);

    SpriteChunkNeighbors8 neighbors {};

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            godot::Vector2i p = cp + godot::Vector2i(dx, dy);

            if (!grid.is_chunk_index_position_valid(p)) {
                continue;
            }

            SpriteChunk* chunk = nullptr;
            sprite.chunks().try_get(grid.to_chunk_index(p), &chunk);

            neighbors.at(dx, dy) = chunk;
        }
    }

    return neighbors;
}

void sprite_distance_field_build(Sprite& sprite) {
    for (SpriteChunk* chunk : sprite.chunks().items()) {
        chunk->calc_distance_field(sprite.grid(), gather_neighbors(sprite, chunk->index));
    }
}

void sprite_distance_field_update_chunks(Sprite& sprite, const godot::LocalVector<SpriteChunk*>& dirtyChunks) {
    const Grid& grid = sprite.grid();

    godot::HashSet<int> affected;

    for (const SpriteChunk* dirtyChunk : dirtyChunks) {
        godot::Vector2i cp = grid.to_chunk_index_position(dirtyChunk->index);

        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                godot::Vector2i p = cp + godot::Vector2i(dx, dy);

                if (!grid.is_chunk_index_position_valid(p)) {
                    continue;
                }

                int neighborIndex = grid.to_chunk_index(p);
                SpriteChunk* chunk = nullptr;

                if (sprite.chunks().try_get(neighborIndex, &chunk) && chunk) {
                    affected.insert(neighborIndex);
                }
            }
        }
    }

    for (int chunkIndex : affected) {
        SpriteChunk* chunk = nullptr;

        if (sprite.chunks().try_get(chunkIndex, &chunk) && chunk) {
            chunk->calc_distance_field(grid, gather_neighbors(sprite, chunkIndex));
        }
    }
}

