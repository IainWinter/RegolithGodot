#pragma once

#include "Coordinate/AxisAlignedAreaTree.h"
#include "Result.h"

#include <godot_cpp/core/object_id.hpp>

#include <godot_cpp/templates/local_vector.hpp>

#include <functional>

class RegolithSprite;

// true when the ray or path should pass through the sprite
using SpriteIgnoreFn = std::function<bool(RegolithSprite*)>;

// bounds of every loaded sprite, rebuilt after each physics step. a sprite's
// box grows to cover its rope nodes so bullets still find it out there.
// queries are in sim units and only ever return sprites that are still loaded
class SpriteTree {
public:
    struct Hit {
        RegolithSprite* sprite;
        godot::Vector2i cell;
        godot::Vector2 position;
        godot::Vector2 local_position;
        float distance;
    };

    void build(const godot::LocalVector<RegolithSprite*>& sprites);

    void query(const AxisAlignedBox& box, godot::LocalVector<RegolithSprite*>& out) const;

    // walks the tree along the segment and returns the nearest cell hit,
    // skipping exclude and anything ignore says to
    Optional<Hit> ray_cast(godot::Vector2 origin, godot::Vector2 end, const RegolithSprite* exclude, const SpriteIgnoreFn& ignore = {}) const;

    const AxisAlignedAreaTreeIndex& index() const;

private:
    // the sprite behind a tree item, null once it was freed or unloaded
    RegolithSprite* resolve(godot::ObjectID id) const;

    AxisAlignedAreaTree<godot::ObjectID> m_tree;
};
