#pragma once

#include "DestructibleSprite/SpriteAsset.h"
#include "DestructibleSprite/Sprite.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/vector2i.hpp>

// Godot images in and out of the engine's sprite data. the mask image is the
// same size as the color image, its colors pick each cell's type and class

SpriteAsset sprite_asset_from_images(const godot::Ref<godot::Image>& color, const godot::Ref<godot::Image>& mask, bool* mask_mismatch = nullptr);

SpriteAsset sprite_asset_blank(godot::Vector2i size);

godot::Ref<godot::Image> sprite_color_image(const Sprite& sprite);

godot::Ref<godot::Image> sprite_mask_image(const Sprite& sprite);
