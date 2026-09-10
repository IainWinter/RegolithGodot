#pragma once

#include "Coordinate/AxisAlignedAreaTree.h"
#include "Result.h"

#include <godot_cpp/core/object_id.hpp>

#include <godot_cpp/templates/local_vector.hpp>

class RegolithSprite;

// bounds of every loaded sprite, rebuilt after each physics step. queries
// are in sim units and only ever return sprites that are still loaded
class SpriteTree {
public:
    struct Hit {
        RegolithSprite* sprite;
        godot::Vector2i cell;
        godot::Vector2 position;
        float distance;
    };

    void build(const godot::LocalVector<RegolithSprite*>& sprites);

    void query(const AxisAlignedBox& box, godot::LocalVector<RegolithSprite*>& out) const;

    Optional<Hit> ray_cast(godot::Vector2 origin, godot::Vector2 end, const RegolithSprite* exclude) const;

    const AxisAlignedAreaTreeIndex& index() const;

private:
    AxisAlignedAreaTree<godot::ObjectID> m_tree;
};
