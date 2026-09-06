#pragma once

#include "Color.h"
#include "SpriteCell.h"
#include "DestructibleSprite/SpriteRopeScan.h"

#include "Coordinate/Grid.h"
#include <godot_cpp/core/object_id.hpp>
#include "Math/Vector.h"

#include <vector>

constexpr int k_rope_entity_min_pixels = 10;

struct SpriteRopeNode {
    vec2 position;
    vec2 last_position;
};

struct [[Struct]] SpriteRopeEntityAnchor {
    godot::ObjectID entity;
    ivec2 cell;
};

struct [[Struct, ManualMembers]] SpriteRope {
    [[Member]]
    SpriteRopeAnchor a;

    [[Member]]
    SpriteRopeAnchor b;

    [[Member]]
    Color4 color;

    [[Member]]
    uint8_t cell_class = 0;

    [[Member]]
    float wiggle_amount = 1.f;

    [[Member]]
    std::vector<vec2> rest_local;

    [[Member]]
    SpriteRopeEntityAnchor entity_a;

    [[Member]]
    SpriteRopeEntityAnchor entity_b;

    std::vector<SpriteRopeNode> nodes;
    std::vector<vec2> node_velocities;

    std::vector<float> rest_len;
    std::vector<uint8_t> node_health;

    float wiggle_phase = -1.f;
};

struct [[Component]] SpriteRopeSet {
    std::vector<SpriteRope> ropes;
    float angle_stiffness = 0.35f;
    float damping = 0.08f;
    float node_mass = 0.1f;
    float wiggle = 3.f;
};

struct [[Component]] SpriteRopeGrid {
    Grid grid;
};
