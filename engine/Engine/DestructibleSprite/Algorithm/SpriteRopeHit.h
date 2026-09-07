#pragma once

#include "DestructibleSprite/SpriteRope.h"

#include "Coordinate/Transform.h"

struct Grid;

struct SpriteRopeHitResult {
    int rope_index = -1;
    int segment_index = -1;
    float segment_t = 0.f;
    int node_index = -1;
    vec2 position = vec2(0.f);
    float along = 0.f;
};

bool find_rope_hit_segment(const SpriteRopeSet& set, vec2 a, vec2 b, float radius, SpriteRopeHitResult* hit);

bool find_rope_hit_point(const SpriteRopeSet& set, vec2 point, float radius, SpriteRopeHitResult* hit);

float sprite_rope_radius(const Transform& transform, const Grid& grid);

float sprite_rope_group_pixels(const std::vector<SpriteRope>& ropes);
