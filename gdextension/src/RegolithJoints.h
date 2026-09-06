#pragma once

#include "Physics/World.h"

#include <godot_cpp/core/object_id.hpp>

#include <optional>
#include <vector>

class RegolithSprite;
class DebugRendererLineList;

// pin joints between two sprites, sim units. every physics tick the live
// ones go to the solver, a joint whose sprite is gone drops out then
class RegolithJoints {
public:
    struct Joint {
        int id;
        godot::ObjectID a;
        godot::ObjectID b;
        vec2 local_a;
        vec2 local_b;
    };

    // -1 when the pair cannot be joined
    int add(RegolithSprite* a, RegolithSprite* b, vec2 world_point);
    void remove(int id);
    void clear();
    int count() const;

    // the anchor on the first sprite, none once the joint or sprite is gone
    std::optional<vec2> position(int id) const;

    void feed(PhysicsWorld& physics);
    void debug_lines(DebugRendererLineList& lines) const;

    const std::vector<Joint>& items() const;

private:
    std::vector<Joint> m_joints;
    int m_next_id = 1;
};
