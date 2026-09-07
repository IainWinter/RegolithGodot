#pragma once

#include "DestructibleSprite/Sprite.h"

#include "Math/Vector.h"

struct SpriteBurnProps {
    int strength = 255;
    int scorch_strength = 110;
    float damage_ratio = 0.65f;
    int damage = 1;
    float spread_odds = 1.f;
    bool spread_removes = false;
};

float sprite_heat_decay_interval();

uint16_t sprite_heat_decay_levels(int tick);

void sprite_burn_cell(Sprite& sprite, int chunk_index, int cell_index, int strength, int damage);

void sprite_burn_point(Sprite& sprite, ivec2 grid_point, int strength, int damage);

void sprite_burn_fracture(Sprite& sprite, ivec2 grid_point, const SpriteBurnProps& props);

void sprite_burn_radius(Sprite& sprite, ivec2 grid_point, int radius, const SpriteBurnProps& props);
