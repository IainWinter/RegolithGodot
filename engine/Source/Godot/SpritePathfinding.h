#pragma once

#include "SpriteTree.h"
#include "DebugLineList.h"

#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

class RegolithSprite;

// any angle a star over an implicit grid of cell_size anchored at the query
// start, port of the engine's SpritePathfinding. cells are blocked by the
// filled cells of every sprite the blocker test accepts, the search ends as
// soon as an expanded cell can see the target. sim units throughout
struct PathfindWorld {
    const SpriteTree& tree;
    const RegolithSprite* source;
    float cell_size;
    // true when the sprite does not block, the source never blocks
    SpriteIgnoreFn ignore;
};

bool pathfind_blocked_point(const PathfindWorld& world, godot::Vector2 point);

bool pathfind_has_los(const PathfindWorld& world, godot::Vector2 from, godot::Vector2 to);

godot::LocalVector<godot::Vector2> pathfind(const PathfindWorld& world, godot::Vector2 start, godot::Vector2 target, int max_expansions = 400, DebugName debug_name = DebugName_Count);

bool pathfind_path_clear(const PathfindWorld& world, godot::Vector2 start, const godot::LocalVector<godot::Vector2>& path, godot::Vector2 goal);

// pops waypoints the position reached or already passed. any unit, the
// path is only compared against itself
void pathfind_advance_waypoints(godot::PackedVector2Array& path, godot::Vector2 pos, float capture_radius);

void pathfind_draw_path(const PathfindWorld& world, godot::Vector2 from, const godot::LocalVector<godot::Vector2>& path, godot::Vector2 goal, DebugName debug_name);
