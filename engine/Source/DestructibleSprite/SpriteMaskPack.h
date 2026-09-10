#pragma once

#include "SpriteCell.h"

#include <inttypes.h>
#include <godot_cpp/templates/local_vector.hpp>

uint8_t pack_sprite_mask_cell(SpriteCellMaskType type, uint8_t cell_class, bool emissive);

SpriteCellMaskType packed_mask_type(uint8_t packed);

uint8_t packed_mask_class(uint8_t packed);

bool packed_mask_emissive(uint8_t packed);

godot::LocalVector<uint8_t> pack_sprite_mask_image(const uint8_t* mask_pixels, int width, int height);

godot::LocalVector<uint8_t> unpack_sprite_mask_image(const uint8_t* packed_cells, int width, int height);
