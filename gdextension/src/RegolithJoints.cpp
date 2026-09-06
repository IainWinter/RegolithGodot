#include "RegolithJoints.h"
#include "RegolithSprite.h"

#include "DebugLineList.h"

#include <godot_cpp/core/object.hpp>

#include <algorithm>

using namespace godot;

static RegolithSprite* sprite_of(ObjectID id) {
    return Object::cast_to<RegolithSprite>(ObjectDB::get_instance(id));
}

int RegolithJoints::add(RegolithSprite* a, RegolithSprite* b, vec2 world_point) {
    if (!a || !b || a == b || !a->is_loaded() || !b->is_loaded()) {
        return -1;
    }

    Joint joint;
    joint.id = m_next_id++;
    joint.a = ObjectID(a->get_instance_id());
    joint.b = ObjectID(b->get_instance_id());
    joint.local_a = a->transform().to_local_point(world_point);
    joint.local_b = b->transform().to_local_point(world_point);

    m_joints.push_back(joint);

    return joint.id;
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

std::optional<vec2> RegolithJoints::position(int id) const {
    for (const Joint& joint : m_joints) {
        if (joint.id != id) {
            continue;
        }

        RegolithSprite* a = sprite_of(joint.a);

        if (a && a->is_loaded()) {
            return a->transform().to_world_point(joint.local_a);
        }
    }

    return std::nullopt;
}

void RegolithJoints::feed(PhysicsWorld& physics) {
    physics.clear_joints();

    std::erase_if(m_joints, [](const Joint& joint) {
        return !sprite_of(joint.a) || !sprite_of(joint.b);
    });

    for (const Joint& joint : m_joints) {
        RegolithSprite* a = sprite_of(joint.a);
        RegolithSprite* b = sprite_of(joint.b);

        if (!a->is_loaded() || !b->is_loaded() || a->is_editing() || b->is_editing()) {
            continue;
        }

        physics.add_joint({&a->body(), &b->body(), joint.local_a, joint.local_b, PhysicsWorldJointType_Pin});
    }
}

void RegolithJoints::debug_lines(DebugRendererLineList& lines) const {
    for (const Joint& joint : m_joints) {
        RegolithSprite* a = sprite_of(joint.a);
        RegolithSprite* b = sprite_of(joint.b);

        if (!a || !b || !a->is_loaded() || !b->is_loaded()) {
            continue;
        }

        vec2 pa = a->transform().to_world_point(joint.local_a);
        vec2 pb = b->transform().to_world_point(joint.local_b);

        lines.line(pa, pb, DebugName_Physics_Joint);
        lines.circle(pa, 0.1f, DebugName_Physics_Joint_Anchor);
        lines.circle(pb, 0.1f, DebugName_Physics_Joint_Anchor);
    }
}

const std::vector<RegolithJoints::Joint>& RegolithJoints::items() const {
    return m_joints;
}
