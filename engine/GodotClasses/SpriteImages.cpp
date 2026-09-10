#include <algorithm>
#include "SpriteImages.h"

#include "DestructibleSprite/ImageToSprite.h"
#include "DestructibleSprite/SpriteMaskPack.h"

#include <string.h>
#include <godot_cpp/templates/local_vector.hpp>

using namespace godot;

SpriteAsset sprite_asset_from_images(const Ref<Image>& color, const Ref<Image>& mask, bool* mask_mismatch) {
    if (mask_mismatch) {
        *mask_mismatch = false;
    }

    Ref<Image> image = color->duplicate();
    image->convert(Image::FORMAT_RGBA8);
    PackedByteArray data = image->get_data();

    bool mask_fits = mask.is_valid() && mask->get_width() == image->get_width() && mask->get_height() == image->get_height();

    if (mask.is_valid() && !mask_fits && mask_mismatch) {
        *mask_mismatch = true;
    }

    if (!mask_fits) {
        return image_to_sprite_chunks(data.ptr(), image->get_width(), image->get_height(), 4);
    }

    Ref<Image> mask_image = mask->duplicate();
    mask_image->convert(Image::FORMAT_RGBA8);
    PackedByteArray mask_data = mask_image->get_data();
    godot::LocalVector<uint8_t> cells = pack_sprite_mask_image(mask_data.ptr(), mask_image->get_width(), mask_image->get_height());

    return image_with_mask_to_sprite_chunks(data.ptr(), image->get_width(), image->get_height(), cells.ptr());
}

SpriteAsset sprite_asset_blank(Vector2i size) {
    godot::LocalVector<uint8_t> pixels; vector_fill(pixels, static_cast<size_t>(size.x) * size.y * 4, 0);
    return image_to_sprite_chunks(pixels.ptr(), size.x, size.y, 4);
}

Ref<Image> sprite_color_image(const Sprite& sprite) {
    godot::Vector2i size = sprite.cell_dim().max(godot::Vector2i(1, 1));
    const Grid& grid = sprite.grid();

    PackedByteArray data;
    data.resize(static_cast<int64_t>(size.x) * size.y * 4);
    data.fill(0);
    uint8_t* out = data.ptrw();

    for (SpriteChunk* chunk : sprite.chunks().items()) {
        for (int i = 0; i < grid.total_cells_in_chunk(); i++) {
            if (!chunk->mask[i].is_filled()) {
                continue;
            }

            godot::Vector2i cell = grid.to_grid_index_position(chunk->index, i);

            if (cell.x >= size.x || cell.y >= size.y) {
                continue;
            }

            Color4 color = chunk->color[i];
            size_t at = (static_cast<size_t>(cell.y) * size.x + cell.x) * 4;
            out[at] = color.r;
            out[at + 1] = color.g;
            out[at + 2] = color.b;
            out[at + 3] = color.a;
        }
    }

    return Image::create_from_data(size.x, size.y, false, Image::FORMAT_RGBA8, data);
}

Ref<Image> sprite_mask_image(const Sprite& sprite) {
    godot::Vector2i size = sprite.cell_dim().max(godot::Vector2i(1, 1));
    const Grid& grid = sprite.grid();

    godot::LocalVector<uint8_t> packed; vector_fill(packed, static_cast<size_t>(size.x) * size.y, 0);

    for (SpriteChunk* chunk : sprite.chunks().items()) {
        for (int i = 0; i < grid.total_cells_in_chunk(); i++) {
            const SpriteCellMask& mask = chunk->mask[i];

            if (!mask.is_filled()) {
                continue;
            }

            godot::Vector2i cell = grid.to_grid_index_position(chunk->index, i);

            if (cell.x >= size.x || cell.y >= size.y) {
                continue;
            }

            packed[static_cast<size_t>(cell.y) * size.x + cell.x] = pack_sprite_mask_cell(mask.get_type(), mask.get_class(), mask.get_emissive());
        }
    }

    godot::LocalVector<uint8_t> pixels = unpack_sprite_mask_image(packed.ptr(), size.x, size.y);

    PackedByteArray data;
    data.resize(static_cast<int64_t>(pixels.size()));
    memcpy(data.ptrw(), pixels.ptr(), pixels.size());

    return Image::create_from_data(size.x, size.y, false, Image::FORMAT_RGBA8, data);
}
