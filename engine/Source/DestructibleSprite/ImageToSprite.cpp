#include "Containers/VectorUtil.h"
#include "ImageToSprite.h"

#include "DestructibleSprite/SpriteMaskPack.h"
#include "Math/MathUtil.h"

#include <climits>
#include <cmath>

static Color4 pixel_to_color4(const uint8_t* pixels, int channels, int index) {
    Color4 color;

    switch (channels) {
        case 1:
            color.r = pixels[index];
            color.g = uint8_t(0);
            color.b = uint8_t(0);
            color.a = uint8_t(255);
            break;
        case 2:
            color.r = pixels[index];
            color.g = pixels[index + 1];
            color.b = uint8_t(0);
            color.a = uint8_t(255);
            break;
        case 3:
            color.r = pixels[index];
            color.g = pixels[index + 1];
            color.b = pixels[index + 2];
            color.a = uint8_t(255);
            break;
        case 4:
            color.r = pixels[index];
            color.g = pixels[index + 1];
            color.b = pixels[index + 2];
            color.a = pixels[index + 3];
            break;
    }

    return color;
}

static SpriteCellMaskType color4_to_mask(Color4 color) {
    if (color.a == 0) {
        return SpriteCellMaskType_Empty;
    }

    if (color.r > 0 || color.g > 0 || color.b > 0) {
        return SpriteCellMaskType_Filled;
    }

    return SpriteCellMaskType_Empty;
}

static SpriteAssetCore flood_fill_core(const uint8_t* mask_cells, godot::LocalVector<bool>& floor_fill_state, int width, int height, int iseed,
                                     SpriteCellMaskType seed_type) {
    SpriteAssetCore r{};
    r.min = godot::Vector2i(INT_MAX, INT_MAX);
    r.max = godot::Vector2i(-INT_MAX, -INT_MAX);
    r.type = seed_type;

    godot::LocalVector<int> stack;
    stack.push_back(iseed);

    while (stack.size() > 0) {
        int index = stack[stack.size() - 1];
        stack.remove_at(stack.size() - 1);

        if (index < 0 || index >= width * height) { // guard out of bounds
            continue;
        }

        SpriteCellMaskType type = packed_mask_type(mask_cells[index]);

        if (type == seed_type && floor_fill_state[index]) {
            floor_fill_state[index] = false;

            int x = index % width;
            int y = index / width;

            bool atLeft = x == 0;
            bool atRight = x == width - 1;

            if (!atRight) {
                stack.push_back(index + 1);
            }

            if (!atLeft) {
                stack.push_back(index - 1);
            }

            stack.push_back(index + width);
            stack.push_back(index - width);

            // Add to result, keep track of the bounds of this island

            if (r.min.x > x)
                r.min.x = x;
            if (r.min.y > y)
                r.min.y = y;
            if (r.max.x < x)
                r.max.x = x;
            if (r.max.y < y)
                r.max.y = y;
        }
    }

    return r;
}

static Color4 normal_pixel_or_flat(const uint8_t* normal_pixels, int normal_channels, int ix, int iy, int width) {
    if (!normal_pixels) {
        return Color4{128, 128, 255, 255};
    }
    int idx = (ix + iy * width) * normal_channels;
    Color4 c;
    c.r = normal_pixels[idx];
    c.g = normal_channels > 1 ? normal_pixels[idx + 1] : uint8_t(128);
    c.b = normal_channels > 2 ? normal_pixels[idx + 2] : uint8_t(255);
    c.a = 255;
    return c;
}

template <typename T> static void image_to_chunks_iterator(SpriteAsset& asset, int width, int height, int channels, T&& func) {
    godot::Vector2i chunkDimensions = godot::Vector2i((width + k_cells_per_chunk - 1) / k_cells_per_chunk, (height + k_cells_per_chunk - 1) / k_cells_per_chunk);

    asset.chunkCount = chunkDimensions;
    asset.cellCount = godot::Vector2i(width, height);

    for (int cy = 0; cy < chunkDimensions.y; cy++) {
        for (int cx = 0; cx < chunkDimensions.x; cx++) {
            asset.chunks.push_back(SpriteAssetChunk{});
            SpriteAssetChunk& chunk = asset.chunks[asset.chunks.size() - 1];

            chunk.gridPixelOffset = godot::Vector2i(cx * k_cells_per_chunk, cy * k_cells_per_chunk);
            chunk.index = cx + cy * chunkDimensions.x;

            for (int y = 0; y < k_cells_per_chunk; y++) {
                for (int x = 0; x < k_cells_per_chunk; x++) {
                    int ix = x + cx * k_cells_per_chunk;
                    int iy = y + cy * k_cells_per_chunk;

                    if (ix >= width || iy >= height) {
                        continue;
                    }

                    int iindex = (ix + iy * width) * channels;
                    int cindex = x + y * k_cells_per_chunk;

                    func(chunk, iindex, cindex, godot::Vector2i(ix, iy));
                }
            }

            if (chunk.activePixelCount == 0) {
                asset.chunks.remove_at(asset.chunks.size() - 1);
            }
        }
    }

    asset.activePixelCount = 0;

    for (const SpriteAssetChunk& chunk : asset.chunks) {
        asset.activePixelCount += chunk.activePixelCount;
    }
}

SpriteAsset image_to_sprite_chunks(const uint8_t* pixels, int width, int height, int channels, const uint8_t* normal_pixels, int normal_channels) {
    SpriteAsset asset{};
    asset.has_normal = normal_pixels != nullptr;

    auto fill = [&](SpriteAssetChunk& chunk, int iindex, int cindex, godot::Vector2i gridIndexPosition) {
        if (asset.has_normal && chunk.normal.is_empty()) {
            vector_fill(chunk.normal, k_cells_per_chunk * k_cells_per_chunk,  Color4{128, 128, 255, 255});
        }

        Color4 color = pixel_to_color4(pixels, channels, iindex);

        if (color.r == 255 && color.g == 255 && color.b == 0) {
            asset.pixelOrigin = gridIndexPosition;
            chunk.color[cindex] = Color4{0, 0, 0, 0};
            chunk.mask[cindex] = SpriteCellMask(SpriteCellMaskType_Empty).get_bits();
            return;
        }

        SpriteCellMaskType mask = color4_to_mask(color);

        asset.groups[mask].activeCount += 1;
        asset.groups[mask].root_grid_index_position += gridIndexPosition;

        if (mask != SpriteCellMaskType_Empty) {
            chunk.activePixelCount += 1;
        }

        else {
            color.a = 0;
        }

        chunk.color[cindex] = color;
        chunk.mask[cindex] = SpriteCellMask(mask).get_bits();

        if (asset.has_normal) {
            chunk.normal[cindex] = normal_pixel_or_flat(normal_pixels, normal_channels, gridIndexPosition.x, gridIndexPosition.y, width);
        }
    };

    image_to_chunks_iterator(asset, width, height, channels, fill);

    return asset;
}

SpriteAsset image_with_mask_to_sprite_chunks(const uint8_t* pixels, int width, int height, const uint8_t* mask_cells, const uint8_t* normal_pixels, int normal_channels) {

    godot::LocalVector<bool> floor_fill_state; vector_fill(floor_fill_state, width * height, true);

    SpriteAsset asset{};
    asset.has_normal = normal_pixels != nullptr;

    auto fill = [&](SpriteAssetChunk& chunk, int iindex, int cindex, godot::Vector2i gridIndexPosition) {
        if (asset.has_normal && chunk.normal.is_empty()) {
            vector_fill(chunk.normal, k_cells_per_chunk * k_cells_per_chunk,  Color4{128, 128, 255, 255});
        }

        Color4 color;
        color.r = pixels[iindex];
        color.g = pixels[iindex + 1];
        color.b = pixels[iindex + 2];
        color.a = pixels[iindex + 3];

        if (color.r == 255 && color.g == 255 && color.b == 0) {
            asset.pixelOrigin = gridIndexPosition;
            chunk.color[cindex] = Color4{0, 0, 0, 0};
            chunk.mask[cindex] = SpriteCellMask(SpriteCellMaskType_Empty).get_bits();
            return;
        }

        int cell_index = iindex / 4;
        uint8_t packed = mask_cells[cell_index];

        SpriteCellMaskType mask = packed_mask_type(packed);
        bool needs_flood_fill = floor_fill_state[cell_index];

        // rope pixels only exist for the scan, they never enter the cell
        // grid. the runtime rope draws itself as a line

        if (mask == SpriteCellMaskType_Rope) {
            chunk.color[cindex] = Color4{0, 0, 0, 0};
            chunk.mask[cindex] = SpriteCellMask(SpriteCellMaskType_Empty).get_bits();
            return;
        }

        asset.groups[mask].activeCount += 1;
        asset.groups[mask].root_grid_index_position += gridIndexPosition;

        SpriteCellMask cell_mask(mask);
        if (mask != SpriteCellMaskType_Empty) {
            cell_mask.set_class(packed_mask_class(packed));
            cell_mask.set_emissive(packed_mask_emissive(packed));
        }

        chunk.color[cindex] = color;
        chunk.mask[cindex] = cell_mask.get_bits();

        if (asset.has_normal) {
            chunk.normal[cindex] = normal_pixel_or_flat(normal_pixels, normal_channels, gridIndexPosition.x, gridIndexPosition.y, width);
        }

        if (mask != SpriteCellMaskType_Empty) {
            chunk.activePixelCount += 1;

            if (mask != SpriteCellMaskType_Filled && needs_flood_fill) {
                SpriteAssetCore core = flood_fill_core(mask_cells, floor_fill_state, width, height, cell_index, mask);

                godot::Vector2i dims = godot::Vector2i(core.max.x - core.min.x + 1, core.max.y - core.min.y + 1);

                core.width = dims.x;
                core.height = dims.y;
                core.gridPointOffset = godot::Vector2((core.max.x + core.min.x + 1) * 0.5f, (core.max.y + core.min.y + 1) * 0.5f);

                vector_fill(core.color, dims.x * dims.y, Color4{});

                // copy colors of only the mask in the rectangle region
                int coreColorIndex = 0;
                for (int y = core.min.y; y <= core.max.y; y++) {
                    for (int x = core.min.x; x <= core.max.x; x++) {
                        int spritePixelIndex = (x + y * width) * 4;
                        if (packed_mask_type(mask_cells[x + y * width]) == mask) {
                            Color4& color = core.color[coreColorIndex];
                            color.r = pixels[spritePixelIndex];
                            color.g = pixels[spritePixelIndex + 1];
                            color.b = pixels[spritePixelIndex + 2];
                            color.a = pixels[spritePixelIndex + 3];

                            core.initialCellCount += 1;
                        }

                        coreColorIndex += 1;
                    }
                }

                asset.cores.push_back(core);
            }
        }
    };

    image_to_chunks_iterator(asset, width, height, 4, fill);

    // scan ropes from the whole mask at once so diagonal lines stay connected
    // and the editor preview (same scan) matches

    godot::LocalVector<SpriteCellMaskType> scan_mask; scan_mask.resize(width * height);
    godot::LocalVector<Color4> scan_pixels; scan_pixels.resize(width * height);

    for (int i = 0; i < width * height; i++) {
        scan_mask[i] = packed_mask_type(mask_cells[i]);
        scan_pixels[i] = Color4(pixels[i * 4 + 0], pixels[i * 4 + 1], pixels[i * 4 + 2], pixels[i * 4 + 3]);
    }

    for (const ScannedRope& scanned : scan_sprite_ropes(scan_mask, scan_pixels, width, height)) {
        SpriteAssetRope rope {};
        rope.anchor_a = scanned.a;
        rope.anchor_b = scanned.b;
        rope.color = scanned.color;
        rope.path = scanned.path;

        uint8_t rope_class = 0;

        for (godot::Vector2i p : scanned.path) {
            uint8_t c = packed_mask_class(mask_cells[p.x + p.y * width]) & 0b11;

            if (c > rope_class) {
                rope_class = c;
            }
        }

        rope.cell_class = rope_class;

        asset.ropes.push_back(std::move(rope));
    }

    return asset;
}