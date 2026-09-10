#pragma once

#include "SpriteAsset.h"

SpriteAsset image_to_sprite_chunks(const uint8_t* pixels, int width, int height, int channels, const uint8_t* normal_pixels = nullptr, int normal_channels = 0);

SpriteAsset image_with_mask_to_sprite_chunks(const uint8_t* pixels, int width, int height, const uint8_t* mask_cells, const uint8_t* normal_pixels = nullptr, int normal_channels = 0);