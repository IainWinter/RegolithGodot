#pragma once

#include "Physics/World.h"
#include "DestructibleSprite/SpriteRope.h"

// sprite to solver mapping, the system feeds these into the world

PhysicsProxy sprite_physics_create_proxy(godot::ObjectID entity, Transform& transform, PhysicsBody& body, Sprite& sprite,
                                         float delta_time);

// chain state in, anchors are resolved by the caller
PhysicsRope sprite_physics_create_rope(const SpriteRope& rope, SpriteRopeSet& set, int owner_proxy, float delta_time);

// drive a traveling sine wave along the chain. period is the wave period in
// seconds, phase offsets ropes from each other
void sprite_physics_wiggle_rope(PhysicsRope& rope, float period, float amount, float phase, float time, float delta_time);

// solved state out
void sprite_physics_apply_rope(const PhysicsRope& solved, SpriteRope& rope, float delta_time);
