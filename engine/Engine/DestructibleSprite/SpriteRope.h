#pragma once

#include "Color.h"
#include "SpriteCell.h"
#include "DestructibleSprite/SpriteRopeScan.h"

#include "Coordinate/Grid.h"
#include <godot_cpp/core/object_id.hpp>
#include "Math/Vector.h"

#include <godot_cpp/templates/local_vector.hpp>

constexpr int k_rope_entity_min_pixels = 10;

struct SpriteRopeNode {
    godot::Vector2 position;
    godot::Vector2 last_position;
};

struct  SpriteRopeEntityAnchor {
    godot::ObjectID entity;
    godot::Vector2i cell;
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
    godot::LocalVector<godot::Vector2> rest_local;

    [[Member]]
    SpriteRopeEntityAnchor entity_a;

    [[Member]]
    SpriteRopeEntityAnchor entity_b;

    godot::LocalVector<SpriteRopeNode> nodes;
    godot::LocalVector<godot::Vector2> node_velocities;

    godot::LocalVector<float> rest_len;
    godot::LocalVector<uint8_t> node_health;

    float wiggle_phase = -1.f;
};

struct  SpriteRopeSet {
    godot::LocalVector<SpriteRope> ropes;
    float angle_stiffness = 0.35f;
    float damping = 0.08f;
    float node_mass = 0.1f;
    float wiggle = 3.f;
};

struct  SpriteRopeGrid {
    Grid grid;
};
