#include "RegolithDebugDraw.h"
#include "RegolithJoints.h"
#include "RegolithSprite.h"
#include "RegolithWorld.h"
#include "SpriteTree.h"

#include "DestructibleSprite/Algorithm/SpriteRopeHit.h"

#include <godot_cpp/classes/engine.hpp>

using namespace godot;

static const RegolithDebugDraw::NameEntry k_names[] = {
    {DebugName_Default, "DEFAULT"},
    {DebugName_Physics_Broadphase_Tree, "PHYSICS_BROADPHASE_TREE"},
    {DebugName_Physics_Broadphase_Overlap_World_Bounds, "PHYSICS_BROADPHASE_OVERLAP_WORLD_BOUNDS"},
    {DebugName_Physics_Broadphase_Overlap_World_Pair_Line, "PHYSICS_BROADPHASE_OVERLAP_WORLD_PAIR_LINE"},
    {DebugName_Physics_Contact_Point, "PHYSICS_CONTACT_POINT"},
    {DebugName_Physics_Contact_Point_Normal, "PHYSICS_CONTACT_POINT_NORMAL"},
    {DebugName_Physics_Surface_Point, "PHYSICS_SURFACE_POINT"},
    {DebugName_Physics_Rope_Node, "PHYSICS_ROPE_NODE"},
    {DebugName_Physics_Force_Bias, "PHYSICS_FORCE_BIAS"},
    {DebugName_Physics_Force_Correction, "PHYSICS_FORCE_CORRECTION"},
    {DebugName_Physics_Force_Velocity, "PHYSICS_FORCE_VELOCITY"},
    {DebugName_Physics_Force_World, "PHYSICS_FORCE_WORLD"},
    {DebugName_Physics_Joint, "PHYSICS_JOINT"},
    {DebugName_Physics_Joint_Rotator, "PHYSICS_JOINT_ROTATOR"},
    {DebugName_Physics_Joint_Rope, "PHYSICS_JOINT_ROPE"},
    {DebugName_Physics_Joint_Anchor, "PHYSICS_JOINT_ANCHOR"},
    {DebugName_Physics_Drag, "PHYSICS_DRAG"},
    {DebugName_Ai, "AI"},
    {DebugName_Ai_Pathfinding, "AI_PATHFINDING"},
    {DebugName_Ai_Path, "AI_PATH"},
    {DebugName_Ai_Flocker, "AI_FLOCKER"},
    {DebugName_Ai_Los_Clear, "AI_LOS_CLEAR"},
    {DebugName_Ai_Los_Blocked, "AI_LOS_BLOCKED"},
    {DebugName_Sprite, "SPRITE"},
    {DebugName_Sprite_Chunk, "SPRITE_CHUNK"},
    {DebugName_World_Tree, "WORLD_TREE"},
    {DebugName_Aim_Assist, "AIM_ASSIST"},
    {DebugName_Region, "REGION"},
    {DebugName_Region_Spawn_Zone, "REGION_SPAWN_ZONE"},
    {DebugName_Region_Asteroid_Belt, "REGION_ASTEROID_BELT"},
    {DebugName_Region_Generated, "REGION_GENERATED"},
    {DebugName_Region_StableSpawnAttemptAABB, "REGION_STABLE_SPAWN_ATTEMPT_AABB"},
    {DebugName_Explosion, "EXPLOSION"},
    {DebugName_Explosion_Force, "EXPLOSION_FORCE"},
};

static_assert(sizeof(k_names) / sizeof(k_names[0]) == DebugName_Count, "every DebugName needs a label");

static Color to_color(Color4 c) {
    return Color(c.r / 255.f, c.g / 255.f, c.b / 255.f, c.a / 255.f);
}

static Color4 to_color4(Color c) {
    return Color4(
        static_cast<int>(c.r * 255.f + 0.5f),
        static_cast<int>(c.g * 255.f + 0.5f),
        static_cast<int>(c.b * 255.f + 0.5f),
        static_cast<int>(c.a * 255.f + 0.5f));
}

const RegolithDebugDraw::NameEntry* RegolithDebugDraw::names(int* count) {
    *count = DebugName_Count;
    return k_names;
}

bool RegolithDebugDraw::name_valid(int name) {
    return name >= 0 && name < DebugName_Count;
}

bool RegolithDebugDraw::layer_valid(int layer) {
    return layer >= 0 && layer < DebugLayer_Count;
}

RegolithDebugDraw::RegolithDebugDraw() {
    set_z_index(4096);
}

void RegolithDebugDraw::_enter_tree() {
    add_to_group("regolith_debug_draw");
}

// the fixed list belongs to the solver and holds until the next step, the
// rest drains every frame even when hidden so script lines never pile up
void RegolithDebugDraw::_process(double delta) {
    if (Engine::get_singleton()->is_editor_hint()) {
        return;
    }

    m_points.resize(0);
    m_colors.resize(0);

    RegolithWorld* world = RegolithWorld::active();

    if (world && is_visible_in_tree()) {
        emit_world_lines(*world);

        gather(*world, debug_render());
        gather(*world, debug_render_fixed());
        gather(*world, debug_render_render());
    }

    debug_render().clear_lines();
    debug_render_render().clear_lines();

    queue_redraw();
}

// sprite quads, chunk bounds, rope nodes, joints and the query tree
void RegolithDebugDraw::emit_world_lines(const RegolithWorld& world) {
    DebugRendererLineList& lines = debug_render();
    const DebugRendererColorMap& map = debug_color_map();

    bool chunks = map.is_enabled(DebugLayer_Default, DebugName_Sprite_Chunk);
    bool rope_nodes = map.is_enabled(DebugLayer_Default, DebugName_Physics_Rope_Node);

    for (RegolithSprite* node : world.sprites()) {
        if (node->is_loaded()) {
            const Transform& transform = node->transform();
            lines.transform(transform, DebugName_Sprite);

            if (chunks) {
                const Grid& grid = node->sprite().grid();

                for (const SpriteChunk* chunk : node->sprite().chunks().items()) {
                    vec2 l0 = grid.to_local_point(chunk->gridPixelOffset);
                    vec2 l1 = grid.to_local_point(chunk->gridPixelOffset + ivec2(grid.chunkSize));

                    vec2 corners[4] = {
                        transform.to_world_point(l0),
                        transform.to_world_point(vec2(l1.x, l0.y)),
                        transform.to_world_point(l1),
                        transform.to_world_point(vec2(l0.x, l1.y)),
                    };

                    lines.polygon(corners, 4, DebugName_Sprite_Chunk);
                }
            }
        }

        if (rope_nodes && node->has_ropes()) {
            float radius = sprite_rope_radius(node->transform(), node->rope_grid());

            for (const SpriteRope& rope : node->ropes().ropes) {
                for (const SpriteRopeNode& rope_node : rope.nodes) {
                    lines.circle(rope_node.position, radius, DebugName_Physics_Rope_Node);
                }
            }
        }
    }

    world.joints().debug_lines(lines);
    lines.axis_aligned_area_tree(world.tree().index(), DebugName_World_Tree);
}

void RegolithDebugDraw::gather(const RegolithWorld& world, DebugRendererLineList& list) {
    for (const DebugRendererLine& line : list.get_lines()) {
        m_points.push_back(world.to_pixels(line.a));
        m_points.push_back(world.to_pixels(line.b));

        m_colors.push_back(to_color(line.color));
    }
}

void RegolithDebugDraw::_draw() {
    if (m_points.size() < 2) {
        return;
    }

    draw_multiline_colors(m_points, m_colors, m_line_width);
}

int RegolithDebugDraw::get_name_count() const {
    return DebugName_Count;
}

String RegolithDebugDraw::get_name_label(int name) const {
    return name_valid(name) ? String(k_names[name].label) : String();
}

void RegolithDebugDraw::set_name_enabled(int name, bool enabled) {
    if (!name_valid(name)) {
        return;
    }

    debug_color_map().set_name_enabled(static_cast<DebugName>(name), enabled);
    debug_render_invalidate_cache();
}

bool RegolithDebugDraw::is_name_enabled(int name) const {
    return name_valid(name) && debug_color_map().colors()[name].second;
}

void RegolithDebugDraw::set_all_names_enabled(bool enabled) {
    for (int name = 0; name < DebugName_Count; name++) {
        debug_color_map().set_name_enabled(static_cast<DebugName>(name), enabled);
    }

    debug_render_invalidate_cache();
}

void RegolithDebugDraw::set_name_color(int name, Color color) {
    if (!name_valid(name)) {
        return;
    }

    debug_color_map().set_name_color(static_cast<DebugName>(name), to_color4(color));
    debug_render_invalidate_cache();
}

Color RegolithDebugDraw::get_name_color(int name) const {
    return name_valid(name) ? to_color(debug_color_map().colors()[name].first) : Color();
}

int RegolithDebugDraw::get_layer_count() const {
    return DebugLayer_Count;
}

void RegolithDebugDraw::set_layer_enabled(int layer, bool enabled) {
    if (!layer_valid(layer)) {
        return;
    }

    debug_color_map().set_layer_enabled(static_cast<DebugLayer>(layer), enabled);
    debug_render_invalidate_cache();
}

bool RegolithDebugDraw::is_layer_enabled(int layer) const {
    return layer_valid(layer) && debug_color_map().tints()[layer].second;
}

void RegolithDebugDraw::set_layer_tint(int layer, Color tint) {
    if (!layer_valid(layer)) {
        return;
    }

    debug_color_map().set_layer_tint(static_cast<DebugLayer>(layer), to_color4(tint));
    debug_render_invalidate_cache();
}

Color RegolithDebugDraw::get_layer_tint(int layer) const {
    return layer_valid(layer) ? to_color(debug_color_map().tints()[layer].first) : Color();
}

// script emitters, pixels in

static RegolithWorld* emit_world(int name, int layer) {
    return RegolithDebugDraw::name_valid(name) && RegolithDebugDraw::layer_valid(layer) ? RegolithWorld::active() : nullptr;
}

void RegolithDebugDraw::add_line(Vector2 a, Vector2 b, int name, int layer) {
    if (RegolithWorld* world = emit_world(name, layer)) {
        debug_render().line(world->to_units(a), world->to_units(b), static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
    }
}

void RegolithDebugDraw::add_ray(Vector2 origin, Vector2 ray, int name, int layer) {
    if (RegolithWorld* world = emit_world(name, layer)) {
        debug_render().ray(world->to_units(origin), world->to_units(ray), static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
    }
}

void RegolithDebugDraw::add_circle(Vector2 origin, float radius, int name, int layer) {
    if (RegolithWorld* world = emit_world(name, layer)) {
        debug_render().circle(world->to_units(origin), radius / world->pixels_per_unit(), static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
    }
}

void RegolithDebugDraw::add_capsule(Vector2 a, Vector2 b, float radius, int name, int layer) {
    if (RegolithWorld* world = emit_world(name, layer)) {
        debug_render().capsule(world->to_units(a), world->to_units(b), radius / world->pixels_per_unit(), static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
    }
}

void RegolithDebugDraw::add_rect(Rect2 rect, int name, int layer) {
    if (RegolithWorld* world = emit_world(name, layer)) {
        AxisAlignedBox box(world->to_units(rect.position), world->to_units(rect.get_end()));
        debug_render().axis_aligned_box(box, static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
    }
}

void RegolithDebugDraw::set_line_width(float width) {
    m_line_width = width;
}

float RegolithDebugDraw::get_line_width() const {
    return m_line_width;
}

int RegolithDebugDraw::get_line_count() const {
    return static_cast<int>(m_colors.size());
}
