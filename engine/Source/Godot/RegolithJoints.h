#pragma once

#include "Physics/World.h"

#include <godot_cpp/core/object_id.hpp>


#include <godot_cpp/templates/pair.hpp>
#include <godot_cpp/templates/local_vector.hpp>

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
        godot::Vector2 local_a;
        godot::Vector2 local_b;
        float distance;
    };

    struct Piece {
        RegolithSprite* sprite;
        godot::Vector2i grid_min;
    };

    int add(RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_point);

    int add_distance(RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_a, godot::Vector2 world_b, float rest);

    void remove(int id);
    void clear();
    int count() const;

    Optional<godot::Pair<godot::Vector2, godot::Vector2>> anchors(int id) const;
    Optional<godot::Pair<RegolithSprite*, RegolithSprite*>> sprites(int id) const;
    Optional<Type> type(int id) const;

    void resolve_split(RegolithSprite* source, const godot::LocalVector<Piece>& pieces);

    void feed(PhysicsWorld& physics);
    void debug_lines(DebugRendererLineList& lines) const;

    const godot::LocalVector<Joint>& items() const;

private:
    int push(Type type, RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_a, godot::Vector2 world_b, float rest);
    const Joint* find(int id) const;
    Optional<godot::Pair<RegolithSprite*, RegolithSprite*>> resolve(const Joint* joint, bool loaded) const;

private:
    godot::LocalVector<Joint> m_joints;
    int m_next_id = 1;
};
