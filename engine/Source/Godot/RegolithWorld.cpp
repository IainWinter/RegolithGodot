#include <algorithm>
#include <godot_cpp/templates/pair.hpp>
#include "RegolithWorld.h"
#include "RegolithSprite.h"
#include "RopeFeed.h"
#include "ScopeMs.h"
#include "SpritePathfinding.h"

#include "DestructibleSprite/Algorithm/SpriteBurn.h"
#include "DestructibleSprite/Algorithm/SpriteCommit.h"
#include "DestructibleSprite/Algorithm/SpriteDistanceField.h"
#include "DestructibleSprite/Algorithm/SpritePhysics.h"
#include "DestructibleSprite/Algorithm/SpriteRopeCut.h"
#include "DestructibleSprite/Algorithm/SpriteRopeHit.h"
#include "DestructibleSprite/Algorithm/SpriteRopeSpawn.h"
#include "Math/Random.h"
#include "DebugLineList.h"
#include "Parallel.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/performance.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>

using namespace godot;

constexpr float k_cell_particle_max_speed = 6.f;
constexpr int k_cell_particle_amount = 1024;
constexpr float k_cell_particle_lifetime = 10.f;

RegolithWorld::RegolithWorld() {}

RegolithWorld::~RegolithWorld() {
    for (RegolithSprite* sprite : m_sprites) {
        sprite->release();
    }
}

RegolithWorld* RegolithWorld::active() {
    SceneTree* tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
    return tree ? Object::cast_to<RegolithWorld>(tree->get_first_node_in_group("regolith_world")) : nullptr;
}

float RegolithWorld::active_pixels_per_unit() {
    RegolithWorld* world = active();
    return world ? world->pixels_per_unit() : static_cast<float>(k_cells_per_chunk);
}

float RegolithWorld::active_pixels_per_cell() {
    RegolithWorld* world = active();
    return world ? static_cast<float>(world->get_pixels_per_cell()) : 1.f;
}

float RegolithWorld::pixels_per_unit() const {
    return static_cast<float>(m_pixels_per_cell * k_cells_per_chunk);
}

godot::Vector2 RegolithWorld::to_units(Vector2 pixels) const {
    return godot::Vector2(pixels.x, pixels.y) / pixels_per_unit();
}

Vector2 RegolithWorld::to_pixels(godot::Vector2 units) const {
    return Vector2(units.x, units.y) * pixels_per_unit();
}

void RegolithWorld::_enter_tree() {
    add_to_group("regolith_world");

    if (Engine::get_singleton()->is_editor_hint()) {
        set_process(false);
        set_physics_process(false);
        return;
    }

    start();
}

void RegolithWorld::_exit_tree() {
    remove_monitors();
}

void RegolithWorld::_notification(int what) {
    if (what == NOTIFICATION_EXTENSION_RELOADED && is_inside_tree() && !Engine::get_singleton()->is_editor_hint()) {
        start();
    }
}

void RegolithWorld::start() {
    if (!m_pool.is_created()) {
        m_pool.create(k_cells_per_chunk, k_atlas_page_size, k_atlas_page_count);
    }

    find_cell_particles();
    set_process(true);
    set_physics_process(true);
    add_monitors();
}

void RegolithWorld::find_cell_particles() {
    m_cell_particles = nullptr;

    for (int i = 0; i < get_child_count(); i++) {
        if (GPUParticles2D* particles = Object::cast_to<GPUParticles2D>(get_child(i))) {
            m_cell_particles = particles;
            break;
        }
    }

    if (!m_cell_particles) {
        UtilityFunctions::print("RegolithWorld: no GPUParticles2D child, cell particles are off: ", get_path());
        return;
    }

    if (m_cell_particles->get_process_material().is_null()) {
        UtilityFunctions::push_warning("RegolithWorld cell particles have no process_material, cells will vanish instead of flying off: ", m_cell_particles->get_path());
    }

    if (m_cell_particles->get_texture().is_null()) {
        Ref<Image> image = Image::create(1, 1, false, Image::FORMAT_RGBA8);
        image->fill(Color(1, 1, 1, 1));
        m_cell_particles->set_texture(ImageTexture::create_from_image(image));
    }

    m_cell_particles->set_amount(k_cell_particle_amount);
    m_cell_particles->set_lifetime(k_cell_particle_lifetime);
    m_cell_particles->set_one_shot(false);
    m_cell_particles->set_explosiveness_ratio(0.f);
    m_cell_particles->set_emitting(false);
    m_cell_particles->set_fixed_fps(0);
    m_cell_particles->set_interpolate(false);
    m_cell_particles->set_visibility_rect(Rect2(-1e7f, -1e7f, 2e7f, 2e7f));
    m_cell_particles->set_physics_interpolation_mode(Node::PHYSICS_INTERPOLATION_MODE_OFF);
}

void RegolithWorld::_process(double delta) {
    decay_heat(static_cast<float>(delta));
    commit_sprites();
}

void RegolithWorld::_physics_process(double delta) {
    step_physics(static_cast<float>(delta));
}

void RegolithWorld::step_physics(float delta_time) {
    ScopeMs timer{m_physics_ms};

    debug_render_fixed().clear_lines();

    godot::LocalVector<PhysicsProxy>& proxies = m_physics.proxies();
    proxies.clear();

    for (RegolithSprite* node : m_sprites) {
        if (!node->is_loaded()) {
            continue;
        }

        if (!node->is_dynamic()) {
            node->sync_body_from_node();
        }

        proxies.push_back(sprite_physics_create_proxy(ObjectID(node->get_instance_id()), node->transform(), node->body(), node->sprite(), delta_time));
    }

    m_physics.shapes().clear();

    godot::LocalVector<SpriteRope*> rope_sources;
    feed_ropes(m_physics, m_sprites, m_time, delta_time, rope_sources);
    m_joints.feed(m_physics);

    m_physics.solve(delta_time);

    godot::LocalVector<PhysicsRope>& solved = m_physics.ropes();

    for (size_t i = 0; i < solved.size(); i++) {
        sprite_physics_apply_rope(solved[i], *rope_sources[i], delta_time);
    }

    for (RegolithSprite* node : m_sprites) {
        if (node->is_loaded() && node->is_dynamic()) {
            node->sync_node_from_body();
        }
    }

    reset_collision_priority();

    m_time += delta_time;
    m_tree.build(m_sprites);
}

// port of PhysicsResetPrioritySystem: a body lowering its priority skips
// contacts, so its overlaps are tracked apart. once it touches nothing it
// drops back to priority zero
void RegolithWorld::reset_collision_priority() {
    bool any_lowered = false;

    for (RegolithSprite* node : m_sprites) {
        any_lowered |= node->body().attempt_lower_priority;
    }

    if (!any_lowered) {
        return;
    }

    m_touching.clear();

    for (const PhysicsContact& contact : m_physics.contacts()) {
        m_touching.insert(contact.entity_0);
        m_touching.insert(contact.entity_1);
    }

    for (const godot::Pair<ObjectID, ObjectID>& pair : m_physics.overlaps()) {
        m_touching.insert(pair.first);
        m_touching.insert(pair.second);
    }

    for (RegolithSprite* node : m_sprites) {
        PhysicsBody& body = node->body();

        if (body.attempt_lower_priority && !m_touching.has(node->get_instance_id())) {
            body.attempt_lower_priority = false;
            body.collision_priority = 0;
        }
    }
}

void RegolithWorld::decay_heat(float delta_time) {
    m_heat_accumulator += delta_time;

    if (m_heat_accumulator < sprite_heat_decay_interval()) {
        return;
    }

    m_heat_accumulator -= sprite_heat_decay_interval();
    m_heat_tick++;

    uint16_t levels = sprite_heat_decay_levels(m_heat_tick);

    if (levels == 0) {
        return;
    }

    for (RegolithSprite* node : m_sprites) {
        if (node->is_loaded() && node->sprite().has_hot_chunks()) {
            node->sprite().decay_heat(levels);
        }
    }
}

godot::PackedVector3Array RegolithWorld::get_hot_cells(int min_heat, int max_count) const {
    godot::PackedVector3Array result;

    if (max_count <= 0) {
        return result;
    }

    uint8_t heat_floor = static_cast<uint8_t>(std::clamp(min_heat, 0, 15));
    godot::LocalVector<godot::Pair<godot::Vector2i, uint8_t>> cells;
    int seen = 0;

    for (RegolithSprite* node : m_sprites) {
        if (!node->is_loaded() || !node->sprite().has_hot_cells()) {
            continue;
        }

        cells.clear();
        node->sprite().hot_cells(heat_floor, cells);

        // reservoir sample so a big burn still gives an even spread
        for (const godot::Pair<godot::Vector2i, uint8_t>& cell : cells) {
            int slot = seen < max_count ? seen : random_int_max(seen + 1);
            seen++;

            if (slot >= max_count) {
                continue;
            }

            godot::Vector2 position = node->cell_to_world(cell.first);
            godot::Vector3 entry(position.x, position.y, float(cell.second));

            if (slot == result.size()) {
                result.push_back(entry);
            } else {
                result.set(slot, entry);
            }
        }
    }

    return result;
}

void RegolithWorld::commit_sprites() {
    ScopeMs timer{m_commit_ms};

    SpriteCommitConfig config {.debug = false, .smallestIslandsToSplit = 20};

    godot::LocalVector<RegolithSprite*> dirty;
    godot::LocalVector<SpriteCommitProxy> proxies;

    for (RegolithSprite* node : m_sprites) {
        if (!node->is_loaded()) {
            continue;
        }

        if (!node->sprite().dirty_chunks().is_empty()) {
            dirty.push_back(node);
            proxies.push_back({&node->sprite(), &node->transform()});
        }
    }

    if (dirty.is_empty()) {
        m_pool.commit_chunks();
        return;
    }

    godot::LocalVector<SpriteCommitResult> results = sprite_commit_all(proxies, config);

    struct DistanceWork {
        Sprite* sprite;
        bool full_build;
        const godot::LocalVector<SpriteChunk*>* chunks;
    };

    struct PieceWork {
        RegolithSprite* source;
        RegolithSprite* piece;
        godot::Vector2i grid_min;
    };

    godot::LocalVector<DistanceWork> distance;
    godot::LocalVector<RegolithSprite*> dead;
    godot::LocalVector<PieceWork> pieces;

    for (size_t i = 0; i < dirty.size(); i++) {
        RegolithSprite* node = dirty[i];
        SpriteCommitResult& result = results[i];

        if (node->sprite().active_cell_count() > 0) {
            node->apply_mass();
        }

        godot::LocalVector<godot::Pair<godot::Vector2i, Color4>> loose;
        node->sprite().take_loose_pixels(loose);

        if (result.selfIsEmpty) {
            for (const godot::Pair<godot::Vector2i, Color4>& p : result.removedPixelColors) {
                loose.push_back(p);
            }
        }

        if (!loose.is_empty()) {
            const Grid& grid = node->sprite().grid();
            const Transform& transform = node->transform();
            const PhysicsBody& body = node->body();

            for (const auto& [grid_position, color] : loose) {
                godot::Vector2 local = grid.to_local_point_centered(grid_position);
                spawn_cell_pixel(transform.to_world_point(local), body.velocity_at_local_point(local), transform.angle, color);
            }

            emit_signal("cells_removed", node, static_cast<int>(loose.size()));
        }

        godot::LocalVector<SpriteRopeSplitTarget> rope_targets;

        // a rotator driven body that lost cells stops colliding with its
        // joint partners until it has moved clear of everything
        bool lower_priority = sprite_commit_has_rotator(node->body()) && (!result.removedPixelColors.is_empty() || !result.splits.is_empty());

        if (lower_priority) {
            node->body().attempt_lower_priority = true;
        }

        for (SpriteCut& cut : result.splits) {
            auto& [split_transform, split_sprite, grid_min] = cut;

            PhysicsBody body = sprite_commit_split_body(split_transform, node->body());
            body.attempt_lower_priority = lower_priority;
            RegolithSprite* piece = spawn_piece(node, std::move(split_sprite), split_transform, body);

            pieces.push_back({node, piece, godot::Vector2i((int)grid_min.x, (int)grid_min.y)});
            distance.push_back({&piece->sprite(), true, nullptr});
            rope_targets.push_back({&piece->transform(), &piece->sprite(), godot::Vector2i((int)grid_min.x, (int)grid_min.y), &piece->ropes()});
        }

        if (node->has_ropes()) {
            ObjectID owner(node->get_instance_id());

            for (godot::LocalVector<SpriteRope>& group : sprite_rope_resolve_after_commit(owner, node->transform(), node->sprite(), node->ropes(), rope_targets)) {
                spawn_rope_group(node, std::move(group));
            }
        }

        if (result.selfIsEmpty && node->is_repairable()) {
            // a repairable sprite keeps its node with every cell on the
            // removed list, ready for repair_cells_of_type. the cells already
            // flew off as particles above. the body keeps its last mass so
            // the solver never sees an empty sprite
            if (node->sprite().active_cell_count() > 0) {
                node->sprite().remove_all_cells();

                godot::LocalVector<godot::Pair<godot::Vector2i, Color4>> discard;
                node->sprite().take_loose_pixels(discard);
                emit_signal("sprite_emptied", node);
            }
        }

        else if (result.selfIsEmpty) {
            dead.push_back(node);
        }

        else {
            distance.push_back({&node->sprite(), false, &result.dirty_chunks});
        }
    }

    parallel_for(0, distance.size(), [&](size_t i) {
        DistanceWork& work = distance[i];

        if (work.full_build) {
            work.sprite->build_distance_field();
        }

        else {
            sprite_distance_field_update_chunks(*work.sprite, *work.chunks);
        }
    });

    for (size_t i = 0; i < pieces.size();) {
        RegolithSprite* source = pieces[i].source;
        godot::LocalVector<RegolithJoints::Piece> own;

        for (; i < pieces.size() && pieces[i].source == source; i++) {
            own.push_back({pieces[i].piece, pieces[i].grid_min});
        }

        m_joints.resolve_split(source, own);
    }

    for (RegolithSprite* node : dead) {
        emit_signal("sprite_destroyed", node);
        free_sprite(node);
    }

    for (PieceWork& work : pieces) {
        register_sprite(work.piece);
        work.piece->apply_mass();
        work.piece->sync_node_from_body();
        work.piece->reset_physics_interpolation();
        emit_signal("sprite_split", work.source, work.piece);
    }

    // core state only moves with the cells, so the check runs here for the
    // sprites this commit touched and the pieces it made. freed sources are
    // unloaded by now and skip themselves
    for (RegolithSprite* node : dirty) {
        node->update_cores();
    }

    for (PieceWork& work : pieces) {
        work.piece->update_cores();
    }

    m_pool.commit_chunks();

    for (RegolithSprite* node : dirty) {
        node->queue_redraw();
    }
}

static RegolithSprite* make_piece(RegolithSprite* source, Node* fallback_parent) {
    RegolithSprite* piece = memnew(RegolithSprite);
    piece->set_material(source->get_material());
    piece->set_rope_material(source->get_rope_material());

    TypedArray<StringName> groups = source->get_groups();

    for (int i = 0; i < groups.size(); i++) {
        piece->add_to_group(groups[i]);
    }

    Node* parent = source->get_parent();
    (parent ? parent : fallback_parent)->add_child(piece);

    return piece;
}

RegolithSprite* RegolithWorld::spawn_piece(RegolithSprite* source, Sprite&& sprite, const Transform& transform, const PhysicsBody& body) {
    RegolithSprite* piece = make_piece(source, this);
    piece->init_piece(this, std::move(sprite), transform, body, source->is_dynamic());

    return piece;
}

RegolithSprite* RegolithWorld::spawn_rope_piece(RegolithSprite* source, godot::LocalVector<SpriteRope>&& group) {
    const SpriteRopeSet& source_set = source->ropes();

    SpriteRopeSet set;
    set.ropes = std::move(group);
    set.angle_stiffness = source_set.angle_stiffness;
    set.damping = source_set.damping;
    set.node_mass = source_set.node_mass;
    set.wiggle = source_set.wiggle;

    RegolithSprite* piece = make_piece(source, this);
    piece->init_rope_piece(this, source->transform(), source->rope_grid(), std::move(set));
    piece->sync_node_from_body();
    piece->reset_physics_interpolation();

    return piece;
}

void RegolithWorld::spawn_rope_group(RegolithSprite* source, godot::LocalVector<SpriteRope>&& group) {
    if (sprite_rope_group_pixels(group) >= k_rope_entity_min_pixels) {
        spawn_rope_piece(source, std::move(group));
    }

    else {
        spawn_rope_pixels(source, group);
    }
}

void RegolithWorld::spawn_rope_pixels(RegolithSprite* source, const godot::LocalVector<SpriteRope>& ropes) {
    godot::LocalVector<SpriteRopePixel> pixels;
    sprite_rope_group_to_pixels(ropes, source->rope_grid(), source->transform(), &source->body(), pixels);

    for (const SpriteRopePixel& pixel : pixels) {
        spawn_cell_pixel(pixel.position, pixel.velocity, pixel.angle, pixel.color);
    }

    if (!pixels.is_empty()) {
        emit_signal("cells_removed", source, static_cast<int>(pixels.size()));
    }
}

void RegolithWorld::resplit_rope_piece(RegolithSprite* node) {
    if (node->has_ropes()) {
        for (godot::LocalVector<SpriteRope>& group : extract_detached_rope_groups(node->ropes())) {
            spawn_rope_group(node, std::move(group));
        }

        godot::LocalVector<SpriteRope>& ropes = node->ropes().ropes;

        if (!ropes.is_empty() && sprite_rope_group_pixels(ropes) < k_rope_entity_min_pixels) {
            spawn_rope_pixels(node, ropes);
            ropes.clear();
        }
    }

    if (!node->has_ropes()) {
        free_sprite(node);
    }
}

void RegolithWorld::free_sprite(RegolithSprite* node) {
    unregister_sprite(node);
    node->release();
    node->queue_free();
}

int RegolithWorld::add_joint(RegolithSprite* a, RegolithSprite* b, Vector2 world_point, bool collide_connected) {
    return m_joints.add(a, b, to_units(world_point), collide_connected);
}

int RegolithWorld::add_distance_joint(RegolithSprite* a, RegolithSprite* b, Vector2 world_point_a, Vector2 world_point_b, float rest_distance, bool collide_connected) {
    float rest = rest_distance < 0.f ? -1.f : rest_distance / pixels_per_unit();
    return m_joints.add_distance(a, b, to_units(world_point_a), to_units(world_point_b), rest, collide_connected);
}

PackedVector2Array RegolithWorld::get_joint_anchors(int joint_id) const {
    PackedVector2Array out;

    if (Optional<godot::Pair<godot::Vector2, godot::Vector2>> anchors = m_joints.anchors(joint_id)) {
        out.push_back(to_pixels(anchors->first));
        out.push_back(to_pixels(anchors->second));
    }

    return out;
}

TypedArray<RegolithSprite> RegolithWorld::get_joint_sprites(int joint_id) const {
    TypedArray<RegolithSprite> out;

    if (Optional<godot::Pair<RegolithSprite*, RegolithSprite*>> sprites = m_joints.sprites(joint_id)) {
        out.push_back(sprites->first);
        out.push_back(sprites->second);
    }

    return out;
}

int RegolithWorld::get_joint_type(int joint_id) const {
    Optional<RegolithJoints::Type> type = m_joints.type(joint_id);
    return type ? static_cast<int>(*type) : -1;
}

bool RegolithWorld::get_joint_collide_connected(int joint_id) const {
    return m_joints.collide_connected(joint_id);
}

void RegolithWorld::remove_joint(int joint_id) {
    m_joints.remove(joint_id);
}

void RegolithWorld::clear_joints() {
    m_joints.clear();
}

int RegolithWorld::get_joint_count() const {
    return m_joints.count();
}

PackedInt32Array RegolithWorld::get_joint_ids() const {
    PackedInt32Array out;

    for (const RegolithJoints::Joint& joint : m_joints.items()) {
        out.push_back(joint.id);
    }

    return out;
}

static TypedArray<RegolithSprite> to_array(const godot::LocalVector<RegolithSprite*>& sprites) {
    TypedArray<RegolithSprite> out;

    for (RegolithSprite* sprite : sprites) {
        out.push_back(sprite);
    }

    return out;
}

static godot::LocalVector<Vector2> to_units_vector(const RegolithWorld& world, const PackedVector2Array& pixels) {
    godot::LocalVector<Vector2> out;
    out.reserve(pixels.size());

    for (int i = 0; i < pixels.size(); i++) {
        out.push_back(world.to_units(pixels[i]));
    }

    return out;
}

static PackedVector2Array to_pixels_array(const RegolithWorld& world, const godot::LocalVector<Vector2>& units) {
    PackedVector2Array out;
    out.resize(units.size());

    for (size_t i = 0; i < units.size(); i++) {
        out[i] = world.to_pixels(units[i]);
    }

    return out;
}

TypedArray<RegolithSprite> RegolithWorld::query_rect(Rect2 rect) const {
    godot::LocalVector<RegolithSprite*> hits;
    m_tree.query(AxisAlignedBox(to_units(rect.position), to_units(rect.get_end())), hits);

    return to_array(hits);
}

TypedArray<RegolithSprite> RegolithWorld::query_segment(Vector2 from, Vector2 to) const {
    godot::LocalVector<RegolithSprite*> hits;
    m_tree.query(AxisAlignedBox(to_units(from), to_units(to)), hits);

    return to_array(hits);
}

// sprites in any of the groups pass rays and never block paths
static SpriteIgnoreFn group_ignore(const PackedStringArray& groups) {
    if (groups.is_empty()) {
        return {};
    }

    godot::LocalVector<StringName> names;

    for (int i = 0; i < groups.size(); i++) {
        names.push_back(StringName(groups[i]));
    }

    return [names](RegolithSprite* sprite) {
        for (const StringName& name : names) {
            if (sprite->is_in_group(name)) {
                return true;
            }
        }

        return false;
    };
}

PathfindWorld RegolithWorld::make_pathfind_world(RegolithSprite* exclude, const PackedStringArray& ignore_groups, float cell_size) const {
    return PathfindWorld{m_tree, exclude, cell_size, group_ignore(ignore_groups)};
}

Dictionary RegolithWorld::ray_cast(Vector2 from, Vector2 to, RegolithSprite* exclude, const PackedStringArray& ignore_groups) const {
    Dictionary result;

    if (Optional<SpriteTree::Hit> hit = m_tree.ray_cast(to_units(from), to_units(to), exclude, group_ignore(ignore_groups))) {
        result["sprite"] = hit->sprite;
        result["cell"] = Vector2i(hit->cell.x, hit->cell.y);
        result["position"] = to_pixels(hit->position);
        result["local_position"] = hit->local_position * pixels_per_unit();
        result["distance"] = hit->distance * pixels_per_unit();
    }

    return result;
}

PackedVector2Array RegolithWorld::find_path(Vector2 from, Vector2 to, float cell_size, RegolithSprite* exclude, const PackedStringArray& ignore_groups, int max_expansions) const {
    PathfindWorld world = make_pathfind_world(exclude, ignore_groups, std::max(cell_size, 1.f) / pixels_per_unit());
    return to_pixels_array(*this, pathfind(world, to_units(from), to_units(to), max_expansions, DebugName_Ai_Pathfinding));
}

bool RegolithWorld::has_line_of_sight(Vector2 from, Vector2 to, RegolithSprite* exclude, const PackedStringArray& ignore_groups) const {
    return pathfind_has_los(make_pathfind_world(exclude, ignore_groups), to_units(from), to_units(to));
}

bool RegolithWorld::is_point_blocked(Vector2 point, RegolithSprite* exclude, const PackedStringArray& ignore_groups) const {
    return pathfind_blocked_point(make_pathfind_world(exclude, ignore_groups), to_units(point));
}

bool RegolithWorld::is_path_clear(Vector2 from, const PackedVector2Array& path, Vector2 goal, RegolithSprite* exclude, const PackedStringArray& ignore_groups) const {
    return pathfind_path_clear(make_pathfind_world(exclude, ignore_groups), to_units(from), to_units_vector(*this, path), to_units(goal));
}

void RegolithWorld::draw_path(Vector2 from, const PackedVector2Array& path, Vector2 goal) const {
    pathfind_draw_path(make_pathfind_world(nullptr, PackedStringArray()), to_units(from), to_units_vector(*this, path), to_units(goal), DebugName_Ai_Path);
}

PackedVector2Array RegolithWorld::advance_waypoints(const PackedVector2Array& path, Vector2 position, float capture_radius) {
    PackedVector2Array out = path;
    pathfind_advance_waypoints(out, position, capture_radius);
    return out;
}

static AxisAlignedBox rope_bounds(const godot::LocalVector<SpriteRope>& ropes, float padding) {
    AxisAlignedBox bounds;
    bool any = false;

    for (const SpriteRope& rope : ropes) {
        for (const SpriteRopeNode& node : rope.nodes) {
            if (!any) {
                bounds = AxisAlignedBox(node.position, node.position);
                any = true;
            }

            else {
                bounds.min = bounds.min.min(node.position);
                bounds.max = bounds.max.max(node.position);
            }
        }
    }

    bounds.min -= godot::Vector2(padding, padding);
    bounds.max += godot::Vector2(padding, padding);

    return bounds;
}

int RegolithWorld::hit_ropes(Vector2 from, Vector2 to, RegolithSprite* exclude) {
    AxisAlignedBox sweep(to_units(from), to_units(to));
    int hits = 0;

    // the tree covers loaded sprites out to their rope nodes, rope only
    // pieces have no cells so they are swept by hand
    godot::LocalVector<RegolithSprite*> nodes;
    m_tree.query(sweep, nodes);

    for (RegolithSprite* n : m_sprites) {
        if (!n->is_loaded() && n->has_ropes()) {
            nodes.push_back(n);
        }
    }

    for (RegolithSprite* node : nodes) {
        if (node == exclude || !node->has_ropes()) {
            continue;
        }

        float radius = sprite_rope_radius(node->transform(), node->rope_grid());

        if (!rope_bounds(node->ropes().ropes, 2.f * radius).intersects_box(sweep)) {
            continue;
        }

        if (!node->hit_rope(from, to).is_empty()) {
            hits++;
        }
    }

    return hits;
}

GPUParticles2D* RegolithWorld::get_cell_particles() {
    if (!m_cell_particles || !m_cell_particles->is_inside_tree()) {
        find_cell_particles();
    }

    return m_cell_particles;
}

void RegolithWorld::spawn_cell_particle(Vector2 position, Vector2 velocity, Color color, float angle) {
    if (!get_cell_particles() || !m_cell_particles->is_visible_in_tree()) {
        return;
    }

    float cell = static_cast<float>(m_pixels_per_cell);
    float max_speed = k_cell_particle_max_speed * pixels_per_unit();

    if (velocity.length_squared() > max_speed * max_speed) {
        velocity = velocity.normalized() * max_speed;
    }

    Transform2D xform(angle, Vector2(cell, cell), 0.f, position);
    Color custom(0.f, angle, cell, 0.f);

    uint32_t flags = GPUParticles2D::EMIT_FLAG_POSITION | GPUParticles2D::EMIT_FLAG_ROTATION_SCALE
                   | GPUParticles2D::EMIT_FLAG_VELOCITY | GPUParticles2D::EMIT_FLAG_COLOR | GPUParticles2D::EMIT_FLAG_CUSTOM;

    m_cell_particles->emit_particle(xform, velocity, color, custom, flags);
}

void RegolithWorld::spawn_cell_pixel(godot::Vector2 position, godot::Vector2 velocity, float angle, Color4 color) {
    velocity += random_float2_centered() * (velocity).length() * 0.2f;

    Color tint(color.r / 255.f, color.g / 255.f, color.b / 255.f, color.a / 255.f);
    spawn_cell_particle(to_pixels(position), to_pixels(velocity), tint, angle);
}

struct MonitorEntry {
    const char* id;
    const char* method;
};

static const MonitorEntry k_monitors[] = {
    {"regolith/sprites", "get_sprite_count"},
    {"regolith/joints", "get_joint_count"},
    {"regolith/contacts", "get_contact_count"},
    {"regolith/ropes", "get_rope_count"},
    {"regolith/commit_ms", "get_commit_time_ms"},
    {"regolith/physics_ms", "get_physics_time_ms"},
};

void RegolithWorld::add_monitors() {
    Performance* performance = Performance::get_singleton();

    if (!performance || m_owns_monitors || performance->has_custom_monitor(StringName(k_monitors[0].id))) {
        return;
    }

    for (const MonitorEntry& entry : k_monitors) {
        performance->add_custom_monitor(StringName(entry.id), Callable(this, entry.method));
    }

    m_owns_monitors = true;
}

void RegolithWorld::remove_monitors() {
    Performance* performance = Performance::get_singleton();

    if (!performance || !m_owns_monitors) {
        return;
    }

    for (const MonitorEntry& entry : k_monitors) {
        if (performance->has_custom_monitor(StringName(entry.id))) {
            performance->remove_custom_monitor(StringName(entry.id));
        }
    }

    m_owns_monitors = false;
}

float RegolithWorld::get_commit_time_ms() const {
    return m_commit_ms;
}

float RegolithWorld::get_physics_time_ms() const {
    return m_physics_ms;
}

int RegolithWorld::get_contact_count() const {
    return static_cast<int>(m_physics.contacts().size());
}

int RegolithWorld::get_rope_count() const {
    int count = 0;

    for (RegolithSprite* node : m_sprites) {
        count += node->get_rope_count();
    }

    return count;
}

int RegolithWorld::get_sprite_count() const {
    return static_cast<int>(m_sprites.size());
}

void RegolithWorld::set_pixels_per_cell(int pixels) {
    m_pixels_per_cell = std::max(1, pixels);

    for (RegolithSprite* sprite : m_sprites) {
        sprite->queue_redraw();
    }
}

int RegolithWorld::get_pixels_per_cell() const {
    return m_pixels_per_cell;
}

void RegolithWorld::set_gravity(Vector2 gravity) {
    m_physics.settings().gravity = godot::Vector2(gravity.x, gravity.y);
}

Vector2 RegolithWorld::get_gravity() const {
    godot::Vector2 gravity = const_cast<PhysicsWorld&>(m_physics).settings().gravity;
    return Vector2(gravity.x, gravity.y);
}

void RegolithWorld::set_substeps(int substeps) {
    m_physics.settings().substeps = std::max(1, substeps);
}

int RegolithWorld::get_substeps() const {
    return const_cast<PhysicsWorld&>(m_physics).settings().substeps;
}

Ref<Texture2DArray> RegolithWorld::get_color_atlas() const {
    return m_pool.color_texture();
}

Ref<Texture2DArray> RegolithWorld::get_mask_atlas() const {
    return m_pool.mask_texture();
}

SpriteChunkPool& RegolithWorld::pool() {
    return m_pool;
}

PhysicsWorld& RegolithWorld::physics() {
    return m_physics;
}

void RegolithWorld::register_sprite(RegolithSprite* sprite) {
    if (m_sprites.find(sprite) == -1) {
        m_sprites.push_back(sprite);
    }
}

void RegolithWorld::unregister_sprite(RegolithSprite* sprite) {
    m_sprites.erase(sprite);
    m_tree.build(m_sprites);
}

const godot::LocalVector<RegolithSprite*>& RegolithWorld::sprites() const {
    return m_sprites;
}

const RegolithJoints& RegolithWorld::joints() const {
    return m_joints;
}

const SpriteTree& RegolithWorld::tree() const {
    return m_tree;
}
