#include "RegolithDebugDraw.h"
#include "RegolithJoints.h"
#include "RegolithSprite.h"
#include "RegolithWorld.h"
#include "SpriteTree.h"

#include "DestructibleSprite/Algorithm/SpriteRopeHit.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/engine_debugger.hpp>

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
    {DebugName_Ai_Thrower, "AI_THROWER"},
    {DebugName_Ai_Shield, "AI_SHIELD"},
    {DebugName_Ai_Trap, "AI_TRAP"},
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
    // textures on lines tile along the length (u > 1); need repeat enabled
    set_texture_repeat(CanvasItem::TEXTURE_REPEAT_ENABLED);
}

// the node that holds the "regolith" debugger capture, one per process
static RegolithDebugDraw* s_capture_owner = nullptr;

void RegolithDebugDraw::_enter_tree() {
    add_to_group("regolith_debug_draw");
    apply();

    EngineDebugger* debugger = EngineDebugger::get_singleton();

    if (!Engine::get_singleton()->is_editor_hint() && debugger->is_active() && s_capture_owner == nullptr) {
        debugger->register_message_capture("regolith", Callable(this, "debugger_message"));
        debugger->send_message("regolith:ready", Array());
        s_capture_owner = this;
    }
}

void RegolithDebugDraw::apply() {
    debug_color_map() = m_map;
    debug_render_invalidate_cache();
}

// editor debugger link

static const char* k_layer_labels[DebugLayer_Count] = {"DEFAULT", "A", "B"};

int RegolithDebugDraw::name_index(const String& label) {
    for (int i = 0; i < DebugName_Count; i++) {
        if (label == k_names[i].label) {
            return i;
        }
    }
    return -1;
}

int RegolithDebugDraw::layer_index(const String& label) {
    for (int i = 0; i < DebugLayer_Count; i++) {
        if (label == k_layer_labels[i]) {
            return i;
        }
    }
    return -1;
}

void RegolithDebugDraw::_exit_tree() {
    if (s_capture_owner == this) {
        EngineDebugger::get_singleton()->unregister_message_capture("regolith");
        s_capture_owner = nullptr;
    }
}

void RegolithDebugDraw::apply_settings(const Dictionary& settings) {
    if (settings.has("visible")) {
        set_visible(settings["visible"]);
    }

    Dictionary names = settings.get("names", Dictionary());
    Dictionary colors = settings.get("colors", Dictionary());
    Dictionary layers = settings.get("layers", Dictionary());
    Dictionary tints = settings.get("tints", Dictionary());

    Array keys = names.keys();
    for (int i = 0; i < keys.size(); i++) {
        int name = name_index(keys[i]);
        if (name >= 0) m_map.set_name_enabled(static_cast<DebugName>(name), names[keys[i]]);
    }

    keys = colors.keys();
    for (int i = 0; i < keys.size(); i++) {
        int name = name_index(keys[i]);
        if (name >= 0) m_map.set_name_color(static_cast<DebugName>(name), to_color4(colors[keys[i]]));
    }

    keys = layers.keys();
    for (int i = 0; i < keys.size(); i++) {
        int layer = layer_index(keys[i]);
        if (layer >= 0) m_map.set_layer_enabled(static_cast<DebugLayer>(layer), layers[keys[i]]);
    }

    keys = tints.keys();
    for (int i = 0; i < keys.size(); i++) {
        int layer = layer_index(keys[i]);
        if (layer >= 0) m_map.set_layer_tint(static_cast<DebugLayer>(layer), to_color4(tints[keys[i]]));
    }

    apply();
}

Dictionary RegolithDebugDraw::get_settings() const {
    Dictionary names, colors, layers, tints;

    for (int i = 0; i < DebugName_Count; i++) {
        names[k_names[i].label] = m_map.colors()[i].enabled;
        colors[k_names[i].label] = to_color(m_map.colors()[i].color);
    }

    for (int i = 0; i < DebugLayer_Count; i++) {
        layers[k_layer_labels[i]] = m_map.tints()[i].enabled;
        tints[k_layer_labels[i]] = to_color(m_map.tints()[i].color);
    }

    Dictionary out;
    out["visible"] = is_visible();
    out["names"] = names;
    out["colors"] = colors;
    out["layers"] = layers;
    out["tints"] = tints;
    return out;
}

bool RegolithDebugDraw::debugger_message(const String& message, const Array& data) {
    if (message == "settings" && data.size() > 0) {
        apply_settings(data[0]);
        return true;
    }

    return false;
}

void RegolithDebugDraw::_process(double delta) {
    if (Engine::get_singleton()->is_editor_hint()) {
        return;
    }

    if (is_visible_in_tree()) {
        collect();
    } else {
        m_points.resize(0);
        m_colors.resize(0);
        m_names.resize(0);
        debug_render().clear_lines();
        debug_render_render().clear_lines();
    }

    queue_redraw();
}

int RegolithDebugDraw::collect() {
    m_points.resize(0);
    m_colors.resize(0);
    m_names.resize(0);

    if (RegolithWorld* world = RegolithWorld::active()) {
        emit_world_lines(*world);
    }

    float ppu = RegolithWorld::active_pixels_per_unit();
    gather(ppu, debug_render());
    gather(ppu, debug_render_fixed());
    gather(ppu, debug_render_render());

    debug_render().clear_lines();
    debug_render_render().clear_lines();

    return static_cast<int>(m_colors.size());
}

PackedVector2Array RegolithDebugDraw::get_points() const {
    return m_points;
}

PackedColorArray RegolithDebugDraw::get_colors() const {
    return m_colors;
}

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
                    godot::Vector2 l0 = grid.to_local_point(chunk->gridPixelOffset);
                    godot::Vector2 l1 = grid.to_local_point(chunk->gridPixelOffset + godot::Vector2i(grid.chunkSize, grid.chunkSize));

                    godot::Vector2 corners[4] = {
                        transform.to_world_point(l0),
                        transform.to_world_point(godot::Vector2(l1.x, l0.y)),
                        transform.to_world_point(l1),
                        transform.to_world_point(godot::Vector2(l0.x, l1.y)),
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

void RegolithDebugDraw::gather(float pixels_per_unit, DebugRendererLineList& list) {
    for (const DebugRendererLine& line : list.get_lines()) {
        m_points.push_back(Vector2(line.a.x, line.a.y) * pixels_per_unit);
        m_points.push_back(Vector2(line.b.x, line.b.y) * pixels_per_unit);

        m_colors.push_back(to_color(line.color));
        m_names.push_back(static_cast<int>(line.name));
    }
}

void RegolithDebugDraw::_draw() {
    // in the editor the plugin draws the lines over the viewport itself
    if (m_points.size() < 2 || Engine::get_singleton()->is_editor_hint()) {
        return;
    }

    // fast path — no per-name texture assigned, one batched call
    bool any_textured = false;
    for (int i = 0; i < DebugName_Count; i++) {
        if (m_textures[i].is_valid()) {
            any_textured = true;
            break;
        }
    }

    if (!any_textured) {
        draw_multiline_colors(m_points, m_colors, m_line_width);
        return;
    }

    // textured segments need real geometry width — a hairline (-1) has no
    // quad to stretch a texture across, so pick a sensible default there
    const float quad_width = m_line_width > 0.f ? m_line_width : 4.f;
    const int line_count = m_colors.size();

    PackedVector2Array plain_points;
    PackedColorArray plain_colors;

    PackedVector2Array quad;
    PackedVector2Array uvs;
    PackedColorArray quad_colors;
    quad.resize(4);
    uvs.resize(4);
    quad_colors.resize(4);

    for (int i = 0; i < line_count; i++) {
        int name = m_names[i];
        Ref<Texture2D> tex = (name >= 0 && name < DebugName_Count) ? m_textures[name] : Ref<Texture2D>();

        Vector2 a = m_points[i * 2];
        Vector2 b = m_points[i * 2 + 1];

        if (!tex.is_valid()) {
            plain_points.push_back(a);
            plain_points.push_back(b);
            plain_colors.push_back(m_colors[i]);
            continue;
        }

        Vector2 dir = b - a;
        float len = dir.length();
        if (len < 1e-6f) {
            continue;
        }

        Vector2 x = dir / len;
        Vector2 y = Vector2(-x.y, x.x);
        float w = quad_width * 0.5f;

        quad.set(0, a + y * w);
        quad.set(1, a - y * w);
        quad.set(2, b - y * w);
        quad.set(3, b + y * w);

        // aspect-preserving tiling: texture repeats every `quad_width` pixels
        // along the length so square patterns stay square, gradients stretch
        // reasonably. relies on TEXTURE_REPEAT_ENABLED set in the constructor
        float u_end = len / quad_width;
        uvs.set(0, Vector2(0.f, 0.f));
        uvs.set(1, Vector2(0.f, 1.f));
        uvs.set(2, Vector2(u_end, 1.f));
        uvs.set(3, Vector2(u_end, 0.f));

        const Color& c = m_colors[i];
        quad_colors.set(0, c);
        quad_colors.set(1, c);
        quad_colors.set(2, c);
        quad_colors.set(3, c);

        draw_polygon(quad, quad_colors, uvs, tex);
    }

    if (plain_points.size() >= 2) {
        draw_multiline_colors(plain_points, plain_colors, m_line_width);
    }
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

    m_map.set_name_enabled(static_cast<DebugName>(name), enabled);
    apply();
}

bool RegolithDebugDraw::is_name_enabled(int name) const {
    return name_valid(name) && m_map.colors()[name].enabled;
}

void RegolithDebugDraw::set_all_names_enabled(bool enabled) {
    for (int name = 0; name < DebugName_Count; name++) {
        m_map.set_name_enabled(static_cast<DebugName>(name), enabled);
    }

    apply();
}

void RegolithDebugDraw::set_name_color(int name, Color color) {
    if (!name_valid(name)) {
        return;
    }

    m_map.set_name_color(static_cast<DebugName>(name), to_color4(color));
    apply();
}

Color RegolithDebugDraw::get_name_color(int name) const {
    return name_valid(name) ? to_color(m_map.colors()[name].color) : Color();
}

void RegolithDebugDraw::set_name_texture(int name, Ref<Texture2D> texture) {
    if (!name_valid(name)) {
        return;
    }

    m_textures[name] = texture;
    queue_redraw();
}

Ref<Texture2D> RegolithDebugDraw::get_name_texture(int name) const {
    return name_valid(name) ? m_textures[name] : Ref<Texture2D>();
}

void RegolithDebugDraw::set_all_names_texture(Ref<Texture2D> texture) {
    for (int name = 0; name < DebugName_Count; name++) {
        m_textures[name] = texture;
    }
    queue_redraw();
}

int RegolithDebugDraw::get_layer_count() const {
    return DebugLayer_Count;
}

void RegolithDebugDraw::set_layer_enabled(int layer, bool enabled) {
    if (!layer_valid(layer)) {
        return;
    }

    m_map.set_layer_enabled(static_cast<DebugLayer>(layer), enabled);
    apply();
}

bool RegolithDebugDraw::is_layer_enabled(int layer) const {
    return layer_valid(layer) && m_map.tints()[layer].enabled;
}

void RegolithDebugDraw::set_layer_tint(int layer, Color tint) {
    if (!layer_valid(layer)) {
        return;
    }

    m_map.set_layer_tint(static_cast<DebugLayer>(layer), to_color4(tint));
    apply();
}

Color RegolithDebugDraw::get_layer_tint(int layer) const {
    return layer_valid(layer) ? to_color(m_map.tints()[layer].color) : Color();
}

// pixels to units for script lines. no world in the tree (an enemy scene
// open in the editor) falls back to the default scale
static bool emit_ok(int name, int layer, float* ppu) {
    *ppu = RegolithWorld::active_pixels_per_unit();
    return RegolithDebugDraw::name_valid(name) && RegolithDebugDraw::layer_valid(layer);
}

static Vector2 units(Vector2 pixels, float ppu) {
    return pixels / ppu;
}

void RegolithDebugDraw::add_line(Vector2 a, Vector2 b, int name, int layer) {
    float ppu;
    if (emit_ok(name, layer, &ppu)) {
        debug_render().line(units(a, ppu), units(b, ppu), static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
    }
}

void RegolithDebugDraw::add_ray(Vector2 origin, Vector2 ray, int name, int layer) {
    float ppu;
    if (emit_ok(name, layer, &ppu)) {
        debug_render().ray(units(origin, ppu), units(ray, ppu), static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
    }
}

void RegolithDebugDraw::add_circle(Vector2 origin, float radius, int name, int layer) {
    float ppu;
    if (emit_ok(name, layer, &ppu)) {
        debug_render().circle(units(origin, ppu), radius / ppu, static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
    }
}

void RegolithDebugDraw::add_capsule(Vector2 a, Vector2 b, float radius, int name, int layer) {
    float ppu;
    if (emit_ok(name, layer, &ppu)) {
        debug_render().capsule(units(a, ppu), units(b, ppu), radius / ppu, static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
    }
}

void RegolithDebugDraw::add_rect(Rect2 rect, int name, int layer) {
    float ppu;
    if (emit_ok(name, layer, &ppu)) {
        Vector2 lo = units(rect.position, ppu);
        Vector2 hi = units(rect.position + rect.size, ppu);
        debug_render().axis_aligned_box(AxisAlignedBox(lo, hi), static_cast<DebugName>(name), static_cast<DebugLayer>(layer));
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
