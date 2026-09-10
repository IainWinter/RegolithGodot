#include <godot_cpp/templates/pair.hpp>
#include "RegolithJoints.h"
#include "RegolithSprite.h"

#include "DebugLineList.h"

#include <godot_cpp/core/object.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

constexpr int k_anchor_search_cells = 3;

static RegolithSprite* sprite_of(ObjectID id) {
    return Object::cast_to<RegolithSprite>(ObjectDB::get_instance(id));
}

static bool can_join(RegolithSprite* a, RegolithSprite* b) {
    return a && b && a != b && a->is_loaded() && b->is_loaded();
}

int RegolithJoints::push(Type type, RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_a, godot::Vector2 world_b, float rest) {
    if (!can_join(a, b)) {
        return -1;
    }

    Joint joint;
    joint.id = m_next_id++;
    joint.type = type;
    joint.a = ObjectID(a->get_instance_id());
    joint.b = ObjectID(b->get_instance_id());
    joint.local_a = a->transform().to_local_point(world_a);
    joint.local_b = b->transform().to_local_point(world_b);
    joint.distance = rest < 0.f ? (world_b - world_a).length() : rest;

    m_joints.push_back(joint);

    return joint.id;
}

int RegolithJoints::add(RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_point) {
    return push(Pin, a, b, world_point, world_point, 0.f);
}

int RegolithJoints::add_distance(RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_a, godot::Vector2 world_b, float rest) {
    return push(Distance, a, b, world_a, world_b, rest);
}

void RegolithJoints::remove(int id) {
    for (uint32_t i = 0; i < m_joints.size(); ) {
        if (m_joints[i].id == id) {
            m_joints.remove_at(i);
        } else {
            i++;
        }
    }
}

void RegolithJoints::clear() {
    m_joints.clear();
}

int RegolithJoints::count() const {
    return static_cast<int>(m_joints.size());
}

const RegolithJoints::Joint* RegolithJoints::find(int id) const {
    for (const Joint& joint : m_joints) {
        if (joint.id == id) {
            return &joint;
        }
    }

    return nullptr;
}

Optional<godot::Pair<RegolithSprite*, RegolithSprite*>> RegolithJoints::resolve(const Joint* joint, bool loaded) const {
    if (!joint) {
        return Nothing{};
    }

    RegolithSprite* a = sprite_of(joint->a);
    RegolithSprite* b = sprite_of(joint->b);

    if (!a || !b || (loaded && (!a->is_loaded() || !b->is_loaded()))) {
        return Nothing{};
    }

    return godot::Pair<RegolithSprite*, RegolithSprite*>{a, b};
}

Optional<godot::Pair<godot::Vector2, godot::Vector2>> RegolithJoints::anchors(int id) const {
    const Joint* joint = find(id);

    if (auto sprites = resolve(joint, true)) {
        return godot::Pair<godot::Vector2, godot::Vector2>{sprites->first->transform().to_world_point(joint->local_a), sprites->second->transform().to_world_point(joint->local_b)};
    }

    return Nothing{};
}

Optional<godot::Pair<RegolithSprite*, RegolithSprite*>> RegolithJoints::sprites(int id) const {
    return resolve(find(id), false);
}

Optional<RegolithJoints::Type> RegolithJoints::type(int id) const {
    const Joint* joint = find(id);
    return joint ? Optional<Type>(joint->type) : Nothing{};
}

static bool holds_cell(RegolithSprite* sprite, godot::Vector2i cell) {
    return sprite->has_cell(Vector2i(cell.x, cell.y));
}

static RegolithSprite* find_holder(RegolithSprite* source, const godot::LocalVector<RegolithJoints::Piece>& pieces, godot::Vector2i cell) {
    auto holder_at = [&](godot::Vector2i at) -> RegolithSprite* {
        if (holds_cell(source, at)) {
            return source;
        }

        for (const RegolithJoints::Piece& piece : pieces) {
            if (holds_cell(piece.sprite, at - piece.grid_min)) {
                return piece.sprite;
            }
        }

        return nullptr;
    };

    if (RegolithSprite* holder = holder_at(cell)) {
        return holder;
    }

    for (int radius = 1; radius <= k_anchor_search_cells; radius++) {
        for (int dy = -radius; dy <= radius; dy++) {
            for (int dx = -radius; dx <= radius; dx++) {
                if (std::max(std::abs(dx), std::abs(dy)) != radius) {
                    continue;
                }

                if (RegolithSprite* holder = holder_at(cell + godot::Vector2i(dx, dy))) {
                    return holder;
                }
            }
        }
    }

    return nullptr;
}

static bool resolve_anchor(RegolithSprite* source, const godot::LocalVector<RegolithJoints::Piece>& pieces, ObjectID& id, godot::Vector2& local) {
    godot::Vector2 grid_point = source->sprite().grid().to_grid_point(local);
    godot::Vector2i cell(static_cast<int>(floorf(grid_point.x)), static_cast<int>(floorf(grid_point.y)));

    RegolithSprite* holder = find_holder(source, pieces, cell);

    if (!holder) {
        return false;
    }

    if (holder != source) {
        godot::Vector2 world = source->transform().to_world_point(local);

        id = ObjectID(holder->get_instance_id());
        local = holder->transform().to_local_point(world);
    }

    return true;
}

void RegolithJoints::resolve_split(RegolithSprite* source, const godot::LocalVector<Piece>& pieces) {
    ObjectID source_id(source->get_instance_id());

    for (uint32_t i = 0; i < m_joints.size(); ) {
        Joint& joint = m_joints[i];
        bool alive = true;

        if (joint.a == source_id) {
            alive = resolve_anchor(source, pieces, joint.a, joint.local_a);
        }

        if (alive && joint.b == source_id) {
            alive = resolve_anchor(source, pieces, joint.b, joint.local_b);
        }

        if (!alive || joint.a == joint.b) {
            m_joints.remove_at(i);
        } else {
            i++;
        }
    }
}

void RegolithJoints::feed(PhysicsWorld& physics) {
    physics.clear_joints();

    for (uint32_t i = 0; i < m_joints.size(); ) {
        const Joint& j = m_joints[i];
        if (!sprite_of(j.a) || !sprite_of(j.b)) {
            m_joints.remove_at(i);
        } else {
            i++;
        }
    }

    for (const Joint& joint : m_joints) {
        RegolithSprite* a = sprite_of(joint.a);
        RegolithSprite* b = sprite_of(joint.b);

        if (!a->is_loaded() || !b->is_loaded()) {
            continue;
        }

        int type = joint.type == Distance ? PhysicsWorldJointType_Distance : PhysicsWorldJointType_Pin;

        physics.add_joint({&a->body(), &b->body(), joint.local_a, joint.local_b, type, joint.distance});
    }
}

void RegolithJoints::debug_lines(DebugRendererLineList& lines) const {
    for (const Joint& joint : m_joints) {
        auto sprites = resolve(&joint, true);

        if (!sprites) {
            continue;
        }

        godot::Vector2 pa = sprites->first->transform().to_world_point(joint.local_a);
        godot::Vector2 pb = sprites->second->transform().to_world_point(joint.local_b);

        lines.line(pa, pb, DebugName_Physics_Joint);
        lines.circle(pa, 0.1f, DebugName_Physics_Joint_Anchor);
        lines.circle(pb, 0.1f, DebugName_Physics_Joint_Anchor);
    }
}

const godot::LocalVector<RegolithJoints::Joint>& RegolithJoints::items() const {
    return m_joints;
}
