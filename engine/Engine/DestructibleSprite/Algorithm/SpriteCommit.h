#pragma once

#include "DestructibleSprite/Sprite.h"

#include <godot_cpp/templates/local_vector.hpp>


struct SpriteCommitProxy {
    Sprite* sprite;
    const Transform* transform;
};

// runs every proxy's commit calc across the thread pool, then recomputes the
// surface of every dirty chunk from all sprites in one parallel pass over all
// chunks at once. the returned results line up with proxies by index
godot::LocalVector<SpriteCommitResult> sprite_commit_all(const godot::LocalVector<SpriteCommitProxy>& proxies, const SpriteCommitConfig& config);

// copy the sprite's current mass onto its body
void sprite_commit_sync_mass(const Sprite& sprite, PhysicsBody& body);

// build the rigid body for a piece cut from a source body, inheriting its
// velocity
PhysicsBody sprite_commit_split_body(const Transform& split_transform, const PhysicsBody& source);

// true when the body is driven by a rotator joint
bool sprite_commit_has_rotator(const PhysicsBody& body);
