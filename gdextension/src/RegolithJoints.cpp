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

int RegolithJoints::push(Type type, RegolithSprite* a, RegolithSprite* b, vec2 world_a, vec2 world_b, float rest) {
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
    joint.distance = rest < 0.f ? length(world_b - world_a) : rest;

    m_joints.push_back(joint);

    return joint.id;
}

int RegolithJoints::add(RegolithSprite* a, RegolithSprite* b, vec2 world_point) {
    return push(Pin, a, b, world_point, world_point, 0.f);
}

int RegolithJoints::add_distance(RegolithSprite* a, RegolithSprite* b, vec2 world_a, vec2 world_b, float rest) {
    return push(Distance, a, b, world_a, world_b, rest);
}

void RegolithJoints::remove(int id) {
    std::erase_if(m_joints, [id](const Joint& joint) { return joint.id == id; });
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

std::optional<std::pair<RegolithSprite*, RegolithSprite*>> RegolithJoints::resolve(const Joint* joint, bool loaded) const {
    if (!joint) {
        return std::nullopt;
    }

    RegolithSprite* a = sprite_of(joint->a);
    RegolithSprite* b = sprite_of(joint->b);

    if (!a || !b || (loaded && (!a->is_loaded() || !b->is_loaded()))) {
        return std::nullopt;
    }

    return std::make_pair(a, b);
}

std::optional<std::pair<vec2, vec2>> RegolithJoints::anchors(int id) const {
    const Joint* joint = find(id);

    if (auto sprites = resolve(joint, true)) {
        return std::make_pair(sprites->first->transform().to_world_point(joint->local_a), sprites->second->transform().to_world_point(joint->local_b));
    }

    return std::nullopt;
}

std::optional<std::pair<RegolithSprite*, RegolithSprite*>> RegolithJoints::sprites(int id) const {
    return resolve(find(id), false);
}

std::optional<RegolithJoints::Type> RegolithJoints::type(int id) const {
    const Joint* joint = find(id);
    return joint ? std::optional<Type>(joint->type) : std::nullopt;
}

static bool holds_cell(RegolithSprite* sprite, ivec2 cell) {
    return sprite->has_cell(Vector2i(cell.x, cell.y));
}

static RegolithSprite* find_holder(RegolithSprite* source, const std::vector<RegolithJoints::Piece>& pieces, ivec2 cell) {
    auto holder_at = [&](ivec2 at) -> RegolithSprite* {
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

                if (RegolithSprite* holder = holder_at(cell + ivec2(dx, dy))) {
                    return holder;
                }
            }
        }
    }

    return nullptr;
}

static bool resolve_anchor(RegolithSprite* source, const std::vector<RegolithJoints::Piece>& pieces, ObjectID& id, vec2& local) {
    vec2 grid_point = source->sprite().grid().to_grid_point(local);
    ivec2 cell(static_cast<int>(floorf(grid_point.x)), static_cast<int>(floorf(grid_point.y)));

    RegolithSprite* holder = find_holder(source, pieces, cell);

    if (!holder) {
        return false;
    }

    if (holder != source) {
        vec2 world = source->transform().to_world_point(local);

        id = ObjectID(holder->get_instance_id());
        local = holder->transform().to_local_point(world);
    }

    return true;
}

void RegolithJoints::resolve_split(RegolithSprite* source, const std::vector<Piece>& pieces) {
    ObjectID source_id(source->get_instance_id());

    std::erase_if(m_joints, [&](Joint& joint) {
        bool alive = true;

        if (joint.a == source_id) {
            alive = resolve_anchor(source, pieces, joint.a, joint.local_a);
        }

        if (alive && joint.b == source_id) {
            alive = resolve_anchor(source, pieces, joint.b, joint.local_b);
        }

        return !alive || joint.a == joint.b;
    });
}

void RegolithJoints::feed(PhysicsWorld& physics) {
    physics.clear_joints();

    std::erase_if(m_joints, [](const Joint& joint) {
        return !sprite_of(joint.a) || !sprite_of(joint.b);
    });

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

        vec2 pa = sprites->first->transform().to_world_point(joint.local_a);
        vec2 pb = sprites->second->transform().to_world_point(joint.local_b);

        lines.line(pa, pb, DebugName_Physics_Joint);
        lines.circle(pa, 0.1f, DebugName_Physics_Joint_Anchor);
        lines.circle(pb, 0.1f, DebugName_Physics_Joint_Anchor);
    }
}

const std::vector<RegolithJoints::Joint>& RegolithJoints::items() const {
    return m_joints;
}
