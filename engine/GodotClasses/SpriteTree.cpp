#include "SpriteTree.h"
#include "RegolithSprite.h"

#include <godot_cpp/core/object.hpp>

#include <cmath>

using namespace godot;

void SpriteTree::build(const godot::LocalVector<RegolithSprite*>& sprites) {
    m_tree.clear();

    for (RegolithSprite* node : sprites) {
        if (!node->is_loaded()) {
            continue;
        }

        AxisAlignedBox box = node->body().transform(node->transform().scale).bounds();
        m_tree.insert(box, ObjectID(node->get_instance_id()));
    }
}

void SpriteTree::query(const AxisAlignedBox& box, godot::LocalVector<RegolithSprite*>& out) const {
    godot::LocalVector<ObjectID> ids;
    m_tree.query_items(box, ids);

    for (ObjectID id : ids) {
        RegolithSprite* sprite = Object::cast_to<RegolithSprite>(ObjectDB::get_instance(id));

        if (sprite && sprite->is_loaded()) {
            out.push_back(sprite);
        }
    }
}

Optional<SpriteTree::Hit> SpriteTree::ray_cast(godot::Vector2 origin, godot::Vector2 end, const RegolithSprite* exclude) const {
    godot::LocalVector<RegolithSprite*> hits;
    query(AxisAlignedBox(origin, end), hits);

    Optional<Hit> best;

    for (RegolithSprite* sprite : hits) {
        if (sprite == exclude) {
            continue;
        }

        const Transform& transform = sprite->transform();

        Optional<godot::Vector2i> cell = sprite->sprite().ray_cast(transform.to_local_point(origin), transform.to_local_point(end));

        if (!cell) {
            continue;
        }

        godot::Vector2 world = transform.to_world_point(sprite->sprite().grid().to_local_point_centered(*cell));
        float distance = (world - origin).length();

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
