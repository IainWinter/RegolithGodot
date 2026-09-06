#pragma once

#include "Coordinate/AxisAlignedAreaTree.h"

#include <godot_cpp/core/object_id.hpp>

#include <optional>
#include <vector>

class RegolithSprite;

// bounds of every loaded sprite, rebuilt after each physics step. queries
// are in sim units and only ever return sprites that are still loaded
class SpriteTree {
public:
    struct Hit {
        RegolithSprite* sprite;
        ivec2 cell;
        vec2 position;
        float distance;
    };

    void build(const std::vector<RegolithSprite*>& sprites);

    void query(const AxisAlignedBox& box, std::vector<RegolithSprite*>& out) const;

    // nearest filled cell along the segment across every sprite it touches
    std::optional<Hit> ray_cast(vec2 origin, vec2 end, const RegolithSprite* exclude) const;

    const AxisAlignedAreaTreeIndex& index() const;

private:
    AxisAlignedAreaTree<godot::ObjectID> m_tree;
};
