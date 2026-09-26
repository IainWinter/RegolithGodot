#include "SpritePathfinding.h"
#include "RegolithSprite.h"

#include "DestructibleSprite/Sprite.h"
#include "Containers/PriorityQueue.h"
#include "Coordinate/Transform.h"
#include "Math/Hash.h"

#include <algorithm>
#include <cmath>
#include <unordered_map>
#include <unordered_set>

using godot::Vector2;
using godot::Vector2i;

static Vector2i point_to_cell(Vector2 p, Vector2 origin, float cell_size) {
    Vector2 c = (p - origin) / cell_size;
    return Vector2i(static_cast<int>(std::round(c.x)), static_cast<int>(std::round(c.y)));
}

static Vector2 cell_to_center(Vector2i c, Vector2 origin, float cell_size) {
    return Vector2(static_cast<float>(c.x), static_cast<float>(c.y)) * cell_size + origin;
}

static bool pathfind_ignores(const PathfindWorld& world, RegolithSprite* sprite) {
    return sprite == world.source || (world.ignore && world.ignore(sprite));
}

bool pathfind_blocked_point(const PathfindWorld& world, Vector2 point) {
    AxisAlignedBox box(point, world.cell_size * 0.01f);

    godot::LocalVector<RegolithSprite*> hits;
    world.tree.query(box, hits);

    for (RegolithSprite* hit : hits) {
        if (pathfind_ignores(world, hit)) {
            continue;
        }

        const Sprite& sprite = hit->sprite();
        const Transform& transform = hit->transform();

        Vector2 local = transform.to_local_point(point);
        Vector2 grid_point = sprite.grid().to_grid_point(local);
        Vector2i dim = sprite.grid().cells;

        if (grid_point.x < 0.f || grid_point.y < 0.f || grid_point.x >= dim.x || grid_point.y >= dim.y) {
            continue;
        }

        auto [chunk_index, cell_index] = sprite.grid().to_chunk_cell_index(grid_point);

        if (sprite.is_cell_active(chunk_index, cell_index)) {
            return true;
        }
    }

    return false;
}

static Optional<SpriteTree::Hit> pathfind_los_cast(const PathfindWorld& world, Vector2 from, Vector2 to) {
    if ((to - from).length() < 0.0001f) {
        return Nothing{};
    }

    return world.tree.ray_cast(from, to, world.source, world.ignore);
}

bool pathfind_has_los(const PathfindWorld& world, Vector2 from, Vector2 to) {
    return !pathfind_los_cast(world, from, to);
}

static bool pathfind_has_los_to_goal(const PathfindWorld& world, Vector2 from, Vector2 goal) {
    Optional<SpriteTree::Hit> hit = pathfind_los_cast(world, from, goal);

    if (hit) {
        debug_render().line(from, hit->position, DebugName_Ai_Los_Blocked);
        debug_render().circle(hit->position, world.cell_size * 0.15f, DebugName_Ai_Los_Blocked);
    }

    else {
        debug_render().line(from, goal, DebugName_Ai_Los_Clear);
        debug_render().circle(goal, world.cell_size * 0.15f, DebugName_Ai_Los_Clear);
    }

    return !hit;
}

struct OpenNode {
    float f;
    Vector2i cell;
};

struct OpenNodeGreater {
    bool operator()(const OpenNode& a, const OpenNode& b) const {
        return a.f > b.f;
    }
};

// the containers of one search, kept between calls so a find_path does not
// allocate them fresh each time. blocked memoizes the cell test, neighbours
// and corner cuts ask about the same cells over and over
struct PathfindScratch {
    PriorityQueue<OpenNode, OpenNodeGreater> open;
    std::unordered_map<Vector2i, float> g_score;
    std::unordered_map<Vector2i, Vector2i> came_from;
    std::unordered_set<Vector2i> closed;
    std::unordered_map<Vector2i, bool> blocked;

    void clear() {
        open.clear();
        g_score.clear();
        came_from.clear();
        closed.clear();
        blocked.clear();
    }

    bool is_blocked(const PathfindWorld& world, Vector2i c, Vector2 origin) {
        auto it = blocked.find(c);

        if (it != blocked.end()) {
            return it->second;
        }

        bool result = pathfind_blocked_point(world, cell_to_center(c, origin, world.cell_size));
        blocked.emplace(c, result);

        return result;
    }
};

godot::LocalVector<Vector2> pathfind(const PathfindWorld& world, Vector2 start, Vector2 target, int max_expansions, DebugName debug_name) {
    bool draw = debug_name != DebugName_Count;
    float cs = world.cell_size;

    godot::LocalVector<Vector2> path;

    if (pathfind_has_los_to_goal(world, start, target)) {
        if (draw) {
            debug_render().line(start, target, debug_name);
            debug_render().circle(target, cs * 0.25f, debug_name);
        }

        path.push_back(target);
        return path;
    }

    Vector2 origin = start;
    Vector2i start_cell = point_to_cell(start, origin, cs);

    static thread_local PathfindScratch g_scratch;
    PathfindScratch& scratch = g_scratch;
    scratch.clear();

    scratch.g_score[start_cell] = 0.f;
    scratch.open.push({(target - cell_to_center(start_cell, origin, cs)).length(), start_cell});

    static const Vector2i dirs[8] = {
        Vector2i( 1, 0), Vector2i(-1, 0), Vector2i(0,  1), Vector2i(0, -1),
        Vector2i( 1, 1), Vector2i( 1,-1), Vector2i(-1, 1), Vector2i(-1,-1),
    };

    Vector2i goal_cell;
    bool found = false;
    int expansions = 0;

    while (!scratch.open.is_empty() && expansions < max_expansions) {
        Vector2i cur = scratch.open.top().cell;
        scratch.open.pop();

        if (!scratch.closed.insert(cur).second) {
            continue;
        }

        Vector2 cur_center = cell_to_center(cur, origin, cs);

        if (pathfind_has_los_to_goal(world, cur_center, target)) {
            goal_cell = cur;
            found = true;
            break;
        }

        ++expansions;

        float cur_g = scratch.g_score[cur];

        for (const Vector2i& d : dirs) {
            Vector2i n = cur + d;

            if (scratch.is_blocked(world, n, origin)) {
                continue;
            }

            if (d.x != 0 && d.y != 0) {
                if (scratch.is_blocked(world, Vector2i(cur.x + d.x, cur.y), origin) || scratch.is_blocked(world, Vector2i(cur.x, cur.y + d.y), origin)) {
                    continue;
                }
            }

            float tentative = cur_g + Vector2(static_cast<float>(d.x), static_cast<float>(d.y)).length() * cs;

            auto it = scratch.g_score.find(n);

            if (it != scratch.g_score.end() && tentative >= it->second) {
                continue;
            }

            Vector2 n_center = cell_to_center(n, origin, cs);

            if (!pathfind_has_los(world, cur_center, n_center)) {
                continue;
            }

            scratch.g_score[n] = tentative;
            scratch.came_from[n] = cur;

            scratch.open.push({tentative + (target - n_center).length(), n});

            if (draw) {
                debug_render().line(cur_center, n_center, debug_name);
                debug_render().circle(n_center, cs * 0.15f, debug_name);
            }
        }
    }

    if (!found) {
        return path;
    }

    Vector2i walk = goal_cell;

    while (walk != start_cell) {
        path.push_back(cell_to_center(walk, origin, cs));

        auto it = scratch.came_from.find(walk);

        if (it == scratch.came_from.end()) {
            break;
        }

        walk = it->second;
    }

    path.invert();
    path.push_back(target);

    return path;
}

bool pathfind_path_clear(const PathfindWorld& world, Vector2 start, const godot::LocalVector<Vector2>& path, Vector2 goal) {
    if (path.is_empty()) {
        return false;
    }

    Vector2 prev = start;

    for (const Vector2& pt : path) {
        if (!pathfind_has_los(world, prev, pt)) {
            return false;
        }

        prev = pt;
    }

    return pathfind_has_los(world, path[path.size() - 1], goal);
}

void pathfind_draw_path(const PathfindWorld& world, Vector2 from, const godot::LocalVector<Vector2>& path, Vector2 goal, DebugName debug_name) {
    Vector2 prev = from;

    for (const Vector2& pt : path) {
        debug_render().line(prev, pt, debug_name);
        debug_render().circle(pt, world.cell_size * 0.2f, debug_name);
        prev = pt;
    }

    debug_render().line(prev, goal, debug_name);
}

void pathfind_advance_waypoints(godot::PackedVector2Array& path, Vector2 pos, float capture_radius) {
    while (!path.is_empty()) {
        if ((path[0] - pos).length() < capture_radius) {
            path.remove_at(0);
            continue;
        }

        if (path.size() >= 2 && pos.distance_to(path[1]) < pos.distance_to(path[0])) {
            path.remove_at(0);
            continue;
        }

        break;
    }
}
