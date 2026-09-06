#include "SpriteTree.h"
#include "RegolithSprite.h"

#include <godot_cpp/core/object.hpp>

#include <cmath>

using namespace godot;

void SpriteTree::build(const std::vector<RegolithSprite*>& sprites) {
    m_tree.clear();

    for (RegolithSprite* node : sprites) {
        if (!node->is_loaded()) {
            continue;
        }

        AxisAlignedBox box = node->body().transform(node->transform().scale).bounds();
        m_tree.insert(box, ObjectID(node->get_instance_id()));
    }
}

void SpriteTree::query(const AxisAlignedBox& box, std::vector<RegolithSprite*>& out) const {
    std::vector<ObjectID> ids;
    m_tree.query_items(box, ids);

    for (ObjectID id : ids) {
        RegolithSprite* sprite = Object::cast_to<RegolithSprite>(ObjectDB::get_instance(id));

        if (sprite && sprite->is_loaded()) {
            out.push_back(sprite);
        }
    }
}

std::optional<SpriteTree::Hit> SpriteTree::ray_cast(vec2 origin, vec2 end, const RegolithSprite* exclude) const {
    std::vector<RegolithSprite*> hits;
    query(AxisAlignedBox(origin, end), hits);

    std::optional<Hit> best;

    for (RegolithSprite* sprite : hits) {
        if (sprite == exclude) {
            continue;
        }

        const Transform& transform = sprite->transform();

        std::optional<ivec2> cell = sprite->sprite().ray_cast(transform.to_local_point(origin), transform.to_local_point(end));

        if (!cell) {
            continue;
        }

        vec2 world = transform.to_world_point(sprite->sprite().grid().to_local_point_centered(*cell));
        float distance = length(world - origin);

        if (best && distance >= best->distance) {
            continue;
        }

        best = Hit{sprite, *cell, world, distance};
    }

    return best;
}

const AxisAlignedAreaTreeIndex& SpriteTree::index() const {
    return m_tree.index();
}
