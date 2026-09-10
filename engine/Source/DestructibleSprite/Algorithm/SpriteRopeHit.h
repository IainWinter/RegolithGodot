#pragma once

#include "DestructibleSprite/SpriteRope.h"

#include "Coordinate/Transform.h"

struct Grid;

struct SpriteRopeHitResult {
    int rope_index = -1;
    int segment_index = -1;
    float segment_t = 0.f;
    int node_index = -1;
    godot::Vector2 position = godot::Vector2(0.f, 0.f);
    float along = 0.f;
};

bool find_rope_hit_segment(const SpriteRopeSet& set, godot::Vector2 a, godot::Vector2 b, float radius, SpriteRopeHitResult* hit);

bool find_rope_hit_point(const SpriteRopeSet& set, godot::Vector2 point, float radius, SpriteRopeHitResult* hit);

float sprite_rope_radius(const Transform& transform, const Grid& grid);

float sprite_rope_group_pixels(const godot::LocalVector<SpriteRope>& ropes);
