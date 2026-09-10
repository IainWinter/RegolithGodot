#pragma once

#include "DestructibleSprite/Sprite.h"
#include "DestructibleSprite/SpriteRope.h"

#include "DestructibleSprite/SpriteAsset.h"
#include "Physics/Body.h"
#include "Coordinate/Grid.h"
#include "Coordinate/Transform.h"

#include <godot_cpp/core/object_id.hpp>

#include <godot_cpp/templates/local_vector.hpp>

// ropes scanned from the mask become chains. one node every stride cells
// plus the ends and any node another rope ties onto
SpriteRopeSet sprite_rope_set_from_asset(const Grid& grid, const SpriteAsset& asset);

// first tick setup, nodes start at their rest pose in world space
void sprite_rope_init_runtime(const Transform& transform, godot::LocalVector<SpriteRope>& ropes);

// a cell anchor holds while any cell in the 3x3 around it is still filled
bool sprite_rope_anchor_cell_alive(const Sprite& sprite, godot::Vector2i cell);

// cell anchors whose cell was destroyed come loose
void sprite_rope_release_destroyed_anchors(const Sprite& sprite, godot::LocalVector<SpriteRope>& ropes);

// a piece cut off by a commit. its grid starts at grid_min in the source grid
struct SpriteRopeSplitTarget {
    const Transform* transform;
    const Sprite* sprite;
    godot::Vector2i grid_min;
    SpriteRopeSet* ropes;
};

// after a commit. rope groups anchored in a piece move onto it, their anchors
// still on the source become entity anchors so the chain ties the two bodies.
// anchors on destroyed cells come loose, dead ropes are compacted, and groups
// holding onto nothing are pulled out and returned for the caller to spawn
// as their own rope bodies
godot::LocalVector<godot::LocalVector<SpriteRope>> sprite_rope_resolve_after_commit(godot::ObjectID owner, const Transform& transform, const Sprite& sprite,
                                                                       SpriteRopeSet& set, godot::LocalVector<SpriteRopeSplitTarget>& splits);

// a rope node turned loose, position and velocity in world units
struct SpriteRopePixel {
    godot::Vector2 position;
    godot::Vector2 velocity;
    float angle;
    Color4 color;
};

// every cell the ropes are drawn over becomes a pixel, moving as its
// segment was or with the body it hung off. the engine only burst the
// nodes, this walks the cells between them so nothing drawn vanishes
void sprite_rope_group_to_pixels(const godot::LocalVector<SpriteRope>& ropes, const Grid& grid, const Transform& transform, const PhysicsBody* body, godot::LocalVector<SpriteRopePixel>& out);
