#pragma once

#include "DestructibleSprite/SpriteRope.h"
#include "Physics/World.h"

#include <vector>

class RegolithSprite;

// mirror of the engine's SpritePhysicsSystem rope mapping. every node's
// chains go into the solver with their anchors resolved to proxy indices,
// sources line up with the solver ropes so the solved state can go back.
// call after the physics proxies are built, rope pieces have no body and
// their chains hang free
void feed_ropes(PhysicsWorld& physics, const std::vector<RegolithSprite*>& sprites, float time, float delta_time, std::vector<SpriteRope*>& sources);
