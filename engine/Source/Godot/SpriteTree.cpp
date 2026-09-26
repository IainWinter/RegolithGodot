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

        if (node->has_ropes()) {
            for (const SpriteRope& rope : node->ropes().ropes) {
                for (const SpriteRopeNode& rope_node : rope.nodes) {
                    box.add_point(rope_node.position);
                }
            }
        }

        m_tree.insert(box, ObjectID(node->get_instance_id()));
    }
}

RegolithSprite* SpriteTree::resolve(ObjectID id) const {
    RegolithSprite* sprite = Object::cast_to<RegolithSprite>(ObjectDB::get_instance(id));
    return sprite && sprite->is_loaded() ? sprite : nullptr;
}

void SpriteTree::query(const AxisAlignedBox& box, godot::LocalVector<RegolithSprite*>& out) const {
    godot::LocalVector<ObjectID> ids;
    m_tree.query_items(box, ids);

    for (ObjectID id : ids) {
        if (RegolithSprite* sprite = resolve(id)) {
            out.push_back(sprite);
        }
    }
}

Optional<SpriteTree::Hit> SpriteTree::ray_cast(godot::Vector2 origin, godot::Vector2 end, const RegolithSprite* exclude, const SpriteIgnoreFn& ignore) const {
    godot::Vector2 delta = end - origin;
    float length = delta.length();

    if (length < 1e-6f) {
        return Nothing{};
    }

    godot::Vector2 direction = delta / length;

    godot::LocalVector<int> keys;
    m_tree.query_ray(origin, direction, length, keys);

    Optional<Hit> best;

    for (int key : keys) {
        RegolithSprite* sprite = resolve(m_tree.get(key));

        if (!sprite || sprite == exclude) {
            continue;
        }

        if (ignore && ignore(sprite)) {
            continue;
        }

        const AxisAlignedBox& box = m_tree.index().get_box(key);
        auto [clip_min, clip_max] = box.clip_ray(origin, direction, length);

        if (!std::isfinite(clip_min) || !std::isfinite(clip_max)) {
            clip_min = 0.f;
            clip_max = length;
        }

        if (clip_max < clip_min) {
            continue;
        }

        const Transform& transform = sprite->transform();

        godot::Vector2 local_origin = transform.to_local_point(origin + direction * clip_min);
        godot::Vector2 local_end = transform.to_local_point(origin + direction * clip_max);

        Optional<godot::Vector2i> cell = sprite->sprite().ray_cast(local_origin, local_end);

        if (!cell) {
            continue;
        }

        godot::Vector2 local = sprite->sprite().grid().to_local_point_centered(*cell);
        godot::Vector2 world = transform.to_world_point(local);
        float distance = (world - origin).length();

        if (best && distance >= best->distance) {
            continue;
        }

        best = Hit{sprite, *cell, world, local, distance};
    }

    return best;
}

const AxisAlignedAreaTreeIndex& SpriteTree::index() const {
    return m_tree.index();
}
