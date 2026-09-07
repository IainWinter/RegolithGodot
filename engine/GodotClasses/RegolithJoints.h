#pragma once

#include "Physics/World.h"

#include <godot_cpp/core/object_id.hpp>

#include <optional>
#include <utility>
#include <vector>

class RegolithSprite;
class DebugRendererLineList;

// joints between two sprites, sim units. every physics tick the live ones go
// to the solver, a joint whose sprite is gone drops out then. when a sprite
// splits, a joint anchored on cells that moved to a piece follows the piece
class RegolithJoints {
public:
    enum Type {
        Pin,
        Distance,
    };

    struct Joint {
        int id;
        Type type;
        godot::ObjectID a;
        godot::ObjectID b;
        vec2 local_a;
        vec2 local_b;
        float distance;
    };

    struct Piece {
        RegolithSprite* sprite;
        ivec2 grid_min;
    };

    int add(RegolithSprite* a, RegolithSprite* b, vec2 world_point);

    int add_distance(RegolithSprite* a, RegolithSprite* b, vec2 world_a, vec2 world_b, float rest);

    void remove(int id);
    void clear();
    int count() const;

    std::optional<std::pair<vec2, vec2>> anchors(int id) const;
    std::optional<std::pair<RegolithSprite*, RegolithSprite*>> sprites(int id) const;
    std::optional<Type> type(int id) const;

    void resolve_split(RegolithSprite* source, const std::vector<Piece>& pieces);

    void feed(PhysicsWorld& physics);
    void debug_lines(DebugRendererLineList& lines) const;

    const std::vector<Joint>& items() const;

private:
    int push(Type type, RegolithSprite* a, RegolithSprite* b, vec2 world_a, vec2 world_b, float rest);
    const Joint* find(int id) const;
    std::optional<std::pair<RegolithSprite*, RegolithSprite*>> resolve(const Joint* joint, bool loaded) const;

private:
    std::vector<Joint> m_joints;
    int m_next_id = 1;
};
