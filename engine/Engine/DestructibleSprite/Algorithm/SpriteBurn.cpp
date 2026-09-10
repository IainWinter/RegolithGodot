#include "SpriteBurn.h"

#include "Math/MathUtil.h"
#include "Math/Random.h"

#include <math.h>

static const int k_max_heat = 15;

static const float k_heat_decay_tick = 0.25f;
static const float k_heat_decay_seconds = 60.f;
static const float k_heat_decay_exponent = 4.f;

static float heat_decay_weight(int heat) {
    float lower = float(heat - 1);
    float upper = float(heat);

    if (lower < 1.f) {
        lower = 1.f;
        upper = 2.f;
    }

    float power = k_heat_decay_exponent - 1.f;

    return 1.f / powf(lower, power) - 1.f / powf(upper, power);
}

struct HeatDecayTable {
    int periods[k_max_heat + 1] = {};

    HeatDecayTable() {
        float total = 0.f;

        for (int heat = 1; heat <= k_max_heat; heat++) {
            total += heat_decay_weight(heat);
        }

        for (int heat = 1; heat <= k_max_heat; heat++) {
            float seconds = k_heat_decay_seconds * heat_decay_weight(heat) / total;
            int ticks = int(seconds / k_heat_decay_tick + 0.5f);

            periods[heat] = ticks < 1 ? 1 : ticks;
        }
    }
};

static const HeatDecayTable& heat_decay_table() {
    static HeatDecayTable table;

    return table;
}

float sprite_heat_decay_interval() {
    return k_heat_decay_tick;
}

uint16_t sprite_heat_decay_levels(int tick) {
    const HeatDecayTable& table = heat_decay_table();

    uint16_t levels = 0;

    for (int heat = 1; heat <= k_max_heat; heat++) {
        if (tick % table.periods[heat] == 0) {
            levels |= static_cast<uint16_t>(1u << heat);
        }
    }

    return levels;
}

static const int k_fracture_size = 9;
static const int k_fracture_radius = k_fracture_size / 2;

static const char* const k_fracture_patterns[][k_fracture_size] = {
    {
        "....#....",
        "...#.....",
        "...#..#..",
        "....##...",
        "....#....",
        "...#.#...",
        "..#...#..",
        "..#....#.",
        ".#.......",
    },
    {
        "#........",
        ".#.......",
        "..#..#...",
        "..##.#...",
        "....#....",
        "...#.##..",
        "..#....#.",
        ".#.......",
        "........#",
    },
    {
        "#.......#",
        ".#.....#.",
        "..#...#..",
        "...#.#...",
        "....#....",
        "...#.#...",
        "..#...#..",
        ".#.......",
        "#........",
    },
    {
        ".........",
        "#........",
        ".##......",
        "...#..#..",
        "...##.#..",
        ".....##..",
        "....#..##",
        "...#.....",
        ".........",
    },
};

static const int k_fracture_pattern_count = sizeof(k_fracture_patterns) / sizeof(k_fracture_patterns[0]);

static godot::Vector2i rotate_fracture_offset(godot::Vector2i offset, int rotation) {
    switch (rotation) {
        case 1: return godot::Vector2i(offset.y, -offset.x);
        case 2: return godot::Vector2i(-offset.x, -offset.y);
        case 3: return godot::Vector2i(-offset.y, offset.x);
    }

    return offset;
}

static void burn_offset(Sprite& sprite, godot::Vector2i grid_point, godot::Vector2i offset, int distance, int radius, const SpriteBurnProps& props) {
    godot::Vector2i point = grid_point + offset;

    if (!sprite.grid().is_grid_index_position_valid(point)) {
        return;
    }

    auto [chunk_index, cell_index] = sprite.grid().to_chunk_cell_index(point);

    SpriteCell cell = sprite.get_cell(chunk_index, cell_index);

    if (cell.type.is_empty()) {
        return;
    }

    float falloff = 1.f - distance / float(radius + 1);

    bool damage = random_bool_weighted(props.damage_ratio * falloff);

    if (damage && !props.spread_removes && cell.type.get_class() == 0) {
        damage = false;
    }

    int strength = int((damage ? props.strength : props.scorch_strength) * falloff);

    sprite_burn_cell(sprite, chunk_index, cell_index, strength, damage ? props.damage : 0);
}

void sprite_burn_cell(Sprite& sprite, int chunk_index, int cell_index, int strength, int damage) {
    SpriteCell cell = sprite.get_cell(chunk_index, cell_index);

    if (cell.type.is_empty()) {
        return;
    }

    int heat = strength * k_max_heat / 255;

    if (heat > k_max_heat) {
        heat = k_max_heat;
    }

    if (cell.type.is_core_type()) {
        heat = 0;
    }

    if (heat > cell.type.get_heat()) {
        cell.type.set_heat(static_cast<uint8_t>(heat));

        sprite.write_display_cell(chunk_index, cell_index, cell.color, cell.type);
    }

    for (int i = 0; i < damage; i++) {
        sprite.damage_cell(chunk_index, cell_index);
    }
}

void sprite_burn_point(Sprite& sprite, godot::Vector2i grid_point, int strength, int damage) {
    auto [chunk_index, cell_index] = sprite.grid().to_chunk_cell_index(grid_point);

    sprite_burn_cell(sprite, chunk_index, cell_index, strength, damage);
}

void sprite_burn_fracture(Sprite& sprite, godot::Vector2i grid_point, const SpriteBurnProps& props) {
    sprite_burn_point(sprite, grid_point, props.strength, props.damage);

    const char* const* pattern = k_fracture_patterns[random_int_max(k_fracture_pattern_count)];
    int rotation = random_int_max(4);

    for (int y = 0; y < k_fracture_size; y++) {
        for (int x = 0; x < k_fracture_size; x++) {
            if (pattern[y][x] != '#') {
                continue;
            }

            godot::Vector2i offset = rotate_fracture_offset(godot::Vector2i(x - k_fracture_radius, y - k_fracture_radius), rotation);

            if (offset.x == 0 && offset.y == 0) {
                continue;
            }

            int distance = abs(offset.x) > abs(offset.y) ? abs(offset.x) : abs(offset.y);

            burn_offset(sprite, grid_point, offset, distance, k_fracture_radius, props);
        }
    }
}

void sprite_burn_radius(Sprite& sprite, godot::Vector2i grid_point, int radius, const SpriteBurnProps& props) {
    sprite_burn_point(sprite, grid_point, props.strength, props.damage);

    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            if (x == 0 && y == 0) {
                continue;
            }

            if (!random_bool_weighted(props.spread_odds)) {
                continue;
            }

            godot::Vector2i offset = godot::Vector2i(x, y);
            int distance = abs(x) > abs(y) ? abs(x) : abs(y);

            burn_offset(sprite, grid_point, offset, distance, radius, props);
        }
    }
}
