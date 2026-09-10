#include <godot_cpp/templates/pair.hpp>
#include "RegolithSprite.h"
#include "RegolithRopeRender.h"
#include "RegolithWorld.h"
#include "SpriteImages.h"

#include "DestructibleSprite/Algorithm/SpriteBurn.h"
#include "DestructibleSprite/Algorithm/SpriteCommit.h"
#include "DestructibleSprite/Algorithm/SpriteRopeSpawn.h"
#include "DestructibleSprite/Algorithm/SpriteRopeHit.h"
#include "DestructibleSprite/Algorithm/SpriteRopeCut.h"
#include "Constants.h"
#include "Coordinate/Iterator/GridLineIterator.h"
#include "Math/MathUtil.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static Color to_color(Color4 color) {
    return Color(color.r / 255.f, color.g / 255.f, color.b / 255.f, color.a / 255.f);
}

static Color4 to_color4(Color color) {
    return Color4(
        static_cast<int>(color.r * 255.f + 0.5f),
        static_cast<int>(color.g * 255.f + 0.5f),
        static_cast<int>(color.b * 255.f + 0.5f),
        static_cast<int>(color.a * 255.f + 0.5f));
}

RegolithSprite::RegolithSprite() {}

RegolithSprite::~RegolithSprite() {
    detach();

    if (m_preview.is_valid()) {
        RenderingServer::get_singleton()->free_rid(m_preview);
    }
}

void RegolithSprite::_exit_tree() {
    detach();
}

void RegolithSprite::_notification(int what) {
    if (what == NOTIFICATION_READY) {
        ready();
    }

    else if (what == NOTIFICATION_EXTENSION_RELOADED && is_inside_tree() && !Engine::get_singleton()->is_editor_hint()) {
        call_deferred("_reload");
    }
}

void RegolithSprite::ready() {
    if (Engine::get_singleton()->is_editor_hint()) {
        queue_redraw();
        return;
    }

    if (is_loaded()) {
        return;
    }

    RegolithWorld* world = RegolithWorld::active();

    if (!world) {
        UtilityFunctions::push_warning("RegolithSprite needs a RegolithWorld in the tree before it: ", get_path());
        return;
    }

    load(world);
}

void RegolithSprite::_reload() {
    RegolithWorld* world = RegolithWorld::active();

    if (!is_loaded() && world) {
        load(world);
    }
}

void RegolithSprite::load(RegolithWorld* world) {
    if (m_texture.is_null()) {
        return;
    }

    Ref<Image> image = m_texture->get_image();

    if (image.is_null()) {
        return;
    }

    Ref<Image> mask = m_mask_texture.is_valid() ? m_mask_texture->get_image() : Ref<Image>();

    bool mask_mismatch = false;
    SpriteAsset asset = sprite_asset_from_images(image, mask, &mask_mismatch);

    if (mask_mismatch) {
        UtilityFunctions::push_warning("RegolithSprite mask texture size does not match texture: ", get_path());
    }

    load_asset(world, asset);
}

void RegolithSprite::load_asset(RegolithWorld* world, SpriteAsset& asset) {
    for (SpriteAssetCellGroup& group : asset.groups) {
        if (group.activeCount > 0) {
            group.root_grid_index_position /= group.activeCount;
        }
    }

    m_world = world;
    m_sprite = Sprite(world->pool(), asset, m_repairable);
    m_ropes = sprite_rope_set_from_asset(m_sprite.grid(), asset);

    m_transform.scale = k_chunk_local_size * godot::Vector2(m_sprite.grid().chunks);
    m_body = PhysicsBody();
    m_body.angle_fixed = m_angle_fixed;
    m_body.linear_damping = m_linear_damping;
    m_body.angular_damping = m_angular_damping;

    sync_body_from_node();
    apply_mass();
    m_sprite.build_distance_field();

    attach();
}

void RegolithSprite::init_piece(RegolithWorld* world, Sprite&& sprite, const Transform& transform, const PhysicsBody& body, bool dynamic) {
    m_world = world;
    m_dynamic = dynamic;
    m_sprite = std::move(sprite);
    m_transform = transform;
    m_body = body;
    m_linear_damping = body.linear_damping;
    m_angular_damping = body.angular_damping;

    attach();
}

void RegolithSprite::init_rope_piece(RegolithWorld* world, const Transform& transform, const Grid& grid, SpriteRopeSet&& ropes) {
    m_world = world;
    m_dynamic = false;
    m_sprite = Sprite();
    m_rope_grid = grid;
    m_ropes = std::move(ropes);
    m_transform = transform;

    m_body = PhysicsBody();
    m_body.position = transform.position;
    m_body.last_position = transform.position;
    m_body.angle = transform.angle;
    m_body.last_angle = transform.angle;

    attach();
}

void RegolithSprite::attach() {
    bind_material();
    m_world->register_sprite(this);
    ensure_rope_render();
    queue_redraw();
}

void RegolithSprite::detach() {
    if (m_world) {
        m_world->unregister_sprite(this);
    }

    release();
}

void RegolithSprite::release() {
    m_sprite = Sprite();
    m_ropes = SpriteRopeSet();
    m_world = nullptr;
}

void RegolithSprite::bind_material() {
    Ref<Material> material = get_material();
    Ref<ShaderMaterial> shader_material = material;

    if (shader_material.is_valid() && m_world) {
        shader_material->set_shader_parameter("color_atlas", m_world->get_color_atlas());
        shader_material->set_shader_parameter("mask_atlas", m_world->get_mask_atlas());
    }

    m_bound_material = material;
}

void RegolithSprite::ensure_rope_render() {
    if (!has_ropes()) {
        return;
    }

    RegolithRopeRender* render = Object::cast_to<RegolithRopeRender>(get_node_or_null(NodePath("RopeRender")));

    if (!render) {
        render = memnew(RegolithRopeRender);
        render->set_name("RopeRender");
        add_child(render);
    }

    render->set_material(m_rope_material);
}

RegolithWorld* RegolithSprite::world() const {
    return m_world;
}

bool RegolithSprite::is_loaded() const {
    return m_sprite.grid().cells.x > 0 && m_sprite.grid().cells.y > 0;
}

bool RegolithSprite::has_ropes() const {
    return !m_ropes.ropes.is_empty();
}

Sprite& RegolithSprite::sprite() {
    return m_sprite;
}

PhysicsBody& RegolithSprite::body() {
    return m_body;
}

Transform& RegolithSprite::transform() {
    return m_transform;
}

SpriteRopeSet& RegolithSprite::ropes() {
    return m_ropes;
}

const Grid& RegolithSprite::rope_grid() const {
    return is_loaded() ? m_sprite.grid() : m_rope_grid;
}

Transform RegolithSprite::render_pose(float fraction) const {
    Transform pose = m_transform;

    if (m_dynamic) {
        pose.position = ((m_body.last_position) * (1.f - (fraction)) + (m_body.position) * (fraction));
        pose.angle = lerp_angle(m_body.last_angle, m_body.angle, fraction);
    }

    else {
        pose.position = m_world->to_units(get_global_position());
        pose.angle = static_cast<float>(get_global_rotation());
    }

    return pose;
}

void RegolithSprite::sync_node_from_body() {
    m_transform.position = m_body.position;
    m_transform.angle = m_body.angle;

    set_global_position(m_world->to_pixels(m_body.position));
    set_global_rotation(m_body.angle);
}

void RegolithSprite::sync_body_from_node() {
    godot::Vector2 position = m_world->to_units(get_global_position());
    float angle = static_cast<float>(get_global_rotation());

    m_body.position = position;
    m_body.last_position = position;
    m_body.angle = angle;
    m_body.last_angle = angle;

    m_transform.position = position;
    m_transform.angle = angle;
}

void RegolithSprite::apply_mass() {
    if (!is_loaded()) {
        return;
    }

    sprite_commit_sync_mass(m_sprite, m_body);

    if (!m_dynamic) {
        m_body.inv_mass = 0.f;
        m_body.inv_inertia = 0.f;
        m_body.linear_velocity = godot::Vector2(0.f, 0.f);
        m_body.angular_velocity = 0.f;
    }
}

void RegolithSprite::_draw() {
    if (!is_loaded()) {
        draw_preview();
        return;
    }

    clear_preview();

    if (get_material() != m_bound_material) {
        bind_material();
    }

    const Grid& grid = m_sprite.grid();
    int chunk_size = grid.chunkSize;
    float page_size = static_cast<float>(m_world->pool().atlas_page_size());
    godot::Vector2 scale = m_transform.scale * m_world->pixels_per_unit();

    PackedVector2Array points;
    PackedVector2Array uvs;
    PackedColorArray colors;

    points.resize(4);
    uvs.resize(4);
    colors.resize(4);
    colors.fill(Color(1, 1, 1, 1));

    for (SpriteChunk* chunk : m_sprite.chunks().items()) {
        godot::Vector2 l0 = grid.to_local_point(chunk->gridPixelOffset) * scale;
        godot::Vector2 l1 = grid.to_local_point(chunk->gridPixelOffset + godot::Vector2i(chunk_size, chunk_size)) * scale;

        float layer = static_cast<float>(chunk->atlasPixelOffset.z) * 2.f;
        float u0 = layer + chunk->atlasPixelOffset.x / page_size;
        float u1 = layer + (chunk->atlasPixelOffset.x + chunk_size) / page_size;
        float v0 = chunk->atlasPixelOffset.y / page_size;
        float v1 = (chunk->atlasPixelOffset.y + chunk_size) / page_size;

        points[0] = Vector2(l0.x, l0.y);
        points[1] = Vector2(l1.x, l0.y);
        points[2] = Vector2(l1.x, l1.y);
        points[3] = Vector2(l0.x, l1.y);

        uvs[0] = Vector2(u0, v0);
        uvs[1] = Vector2(u1, v0);
        uvs[2] = Vector2(u1, v1);
        uvs[3] = Vector2(u0, v1);

        draw_primitive(points, colors, uvs);
    }
}

void RegolithSprite::draw_preview() {
    if (m_texture.is_null()) {
        clear_preview();
        return;
    }

    RenderingServer* rs = RenderingServer::get_singleton();

    if (!m_preview.is_valid()) {
        m_preview = rs->canvas_item_create();
        rs->canvas_item_set_parent(m_preview, get_canvas_item());
        rs->canvas_item_set_default_texture_filter(m_preview, RenderingServer::CANVAS_ITEM_TEXTURE_FILTER_NEAREST);
    }

    RegolithWorld* world = RegolithWorld::active();
    float pixels_per_cell = world ? static_cast<float>(world->get_pixels_per_cell()) : 1.f;
    Vector2 size = m_texture->get_size() * pixels_per_cell;

    rs->canvas_item_clear(m_preview);
    rs->canvas_item_add_texture_rect(m_preview, Rect2(-size * 0.5f, size), m_texture->get_rid(), false);
}

void RegolithSprite::clear_preview() {
    if (m_preview.is_valid()) {
        RenderingServer::get_singleton()->canvas_item_clear(m_preview);
    }
}

void RegolithSprite::set_texture(const Ref<Texture2D>& texture) {
    m_texture = texture;
    queue_redraw();
}

Ref<Texture2D> RegolithSprite::get_texture() const {
    return m_texture;
}

void RegolithSprite::set_mask_texture(const Ref<Texture2D>& texture) {
    m_mask_texture = texture;
}

Ref<Texture2D> RegolithSprite::get_mask_texture() const {
    return m_mask_texture;
}

void RegolithSprite::set_repairable(bool repairable) {
    m_repairable = repairable;
    m_sprite.set_repairable(repairable);
}

bool RegolithSprite::is_repairable() const {
    return m_repairable;
}

void RegolithSprite::set_angle_fixed(bool fixed) {
    m_angle_fixed = fixed;
    m_body.angle_fixed = fixed;

    if (fixed) {
        m_body.angular_velocity = 0.f;
    }
}

bool RegolithSprite::is_angle_fixed() const {
    return m_angle_fixed;
}

void RegolithSprite::set_linear_damping(float damping) {
    m_linear_damping = damping;
    m_body.linear_damping = damping;
}

float RegolithSprite::get_linear_damping() const {
    return m_linear_damping;
}

void RegolithSprite::set_angular_damping(float damping) {
    m_angular_damping = damping;
    m_body.angular_damping = damping;
}

float RegolithSprite::get_angular_damping() const {
    return m_angular_damping;
}

void RegolithSprite::set_dynamic(bool dynamic) {
    m_dynamic = dynamic;
    apply_mass();
}

bool RegolithSprite::is_dynamic() const {
    return m_dynamic;
}

void RegolithSprite::set_rope_material(const Ref<Material>& material) {
    m_rope_material = material;

    if (RegolithRopeRender* render = Object::cast_to<RegolithRopeRender>(get_node_or_null(NodePath("RopeRender")))) {
        render->set_material(material);
    }
}

Ref<Material> RegolithSprite::get_rope_material() const {
    return m_rope_material;
}

void RegolithSprite::create_blank(Vector2i size) {
    RegolithWorld* world = m_world ? m_world : RegolithWorld::active();

    if (!world || size.x <= 0 || size.y <= 0) {
        return;
    }

    SpriteAsset asset = sprite_asset_blank(size);
    load_asset(world, asset);
}

void RegolithSprite::load_from_images(const Ref<Image>& color, const Ref<Image>& mask) {
    RegolithWorld* world = m_world ? m_world : RegolithWorld::active();

    if (!world || color.is_null()) {
        return;
    }

    SpriteAsset asset = sprite_asset_from_images(color, mask);
    load_asset(world, asset);
}

Ref<Image> RegolithSprite::get_color_image() const {
    return is_loaded() ? sprite_color_image(m_sprite) : Ref<Image>();
}

Ref<Image> RegolithSprite::get_mask_image() const {
    return is_loaded() ? sprite_mask_image(m_sprite) : Ref<Image>();
}

void RegolithSprite::paint(Vector2i cell, Color color, SpriteCellMask mask) {
    m_sprite.paint_cell(godot::Vector2i(cell.x, cell.y), to_color4(color), mask);
}

static bool make_mask(RegolithSprite::CellType type, int cell_class, SpriteCellMask& out) {
    if (type <= RegolithSprite::CELL_EMPTY || static_cast<int>(type) >= SpriteCellMaskType_Count) {
        return false;
    }

    out = SpriteCellMask(static_cast<SpriteCellMaskType>(type));
    out.set_class(static_cast<uint8_t>(std::clamp(cell_class, 0, 7)));
    out.set_emissive(out.is_core_type());

    return true;
}

void RegolithSprite::set_cell(Vector2i cell, Color color, CellType type, int cell_class) {
    SpriteCellMask mask;

    if (!is_loaded() || !make_mask(type, cell_class, mask)) {
        return;
    }

    paint(cell, color, mask);
    queue_redraw();
}

void RegolithSprite::clear_cell(Vector2i cell) {
    if (!is_loaded()) {
        return;
    }

    paint(cell, Color(0, 0, 0, 0), SpriteCellMask(SpriteCellMaskType_Empty));
    queue_redraw();
}

void RegolithSprite::fill_rect(Rect2i rect, Color color, CellType type, int cell_class) {
    SpriteCellMask mask;

    if (!is_loaded() || !make_mask(type, cell_class, mask)) {
        return;
    }

    for (int y = rect.position.y; y < rect.position.y + rect.size.y; y++) {
        for (int x = rect.position.x; x < rect.position.x + rect.size.x; x++) {
            paint(Vector2i(x, y), color, mask);
        }
    }

    queue_redraw();
}

void RegolithSprite::clear_rect(Rect2i rect) {
    if (!is_loaded()) {
        return;
    }

    for (int y = rect.position.y; y < rect.position.y + rect.size.y; y++) {
        for (int x = rect.position.x; x < rect.position.x + rect.size.x; x++) {
            paint(Vector2i(x, y), Color(0, 0, 0, 0), SpriteCellMask(SpriteCellMaskType_Empty));
        }
    }

    queue_redraw();
}

Vector2i RegolithSprite::world_to_cell(Vector2 world_position) const {
    if (!is_loaded()) {
        return Vector2i(-1, -1);
    }

    godot::Vector2 local = m_transform.to_local_point(m_world->to_units(world_position));
    godot::Vector2 grid_point = m_sprite.grid().to_grid_point(local);
    godot::Vector2i cell = godot::Vector2i(floorf(grid_point.x), floorf(grid_point.y));

    if (!m_sprite.grid().is_grid_index_position_valid(cell)) {
        return Vector2i(-1, -1);
    }

    return Vector2i(cell.x, cell.y);
}

Vector2 RegolithSprite::cell_to_world(Vector2i cell) const {
    if (!is_loaded()) {
        return get_global_position();
    }

    godot::Vector2 local = m_sprite.grid().to_local_point_centered(godot::Vector2i(cell.x, cell.y));
    return m_world->to_pixels(m_transform.to_world_point(local));
}

bool RegolithSprite::has_cell(Vector2i cell) const {
    if (!is_loaded() || !m_sprite.grid().is_grid_index_position_valid(godot::Vector2i(cell.x, cell.y))) {
        return false;
    }

    auto [chunk_index, cell_index] = m_sprite.grid().to_chunk_cell_index(godot::Vector2i(cell.x, cell.y));

    return m_sprite.is_chunk_active(chunk_index) && m_sprite.is_cell_active(chunk_index, cell_index);
}

RegolithSprite::CellType RegolithSprite::get_cell_type(Vector2i cell) const {
    if (!has_cell(cell)) {
        return CELL_EMPTY;
    }

    auto [chunk_index, cell_index] = m_sprite.grid().to_chunk_cell_index(godot::Vector2i(cell.x, cell.y));
    return static_cast<CellType>(m_sprite.get_cell(chunk_index, cell_index).type.get_type());
}

int RegolithSprite::get_cell_class(Vector2i cell) const {
    if (!has_cell(cell)) {
        return 0;
    }

    auto [chunk_index, cell_index] = m_sprite.grid().to_chunk_cell_index(godot::Vector2i(cell.x, cell.y));
    return m_sprite.get_cell(chunk_index, cell_index).type.get_class();
}

Color RegolithSprite::get_cell_color(Vector2i cell) const {
    if (!has_cell(cell)) {
        return Color(0, 0, 0, 0);
    }

    auto [chunk_index, cell_index] = m_sprite.grid().to_chunk_cell_index(godot::Vector2i(cell.x, cell.y));
    return to_color(m_sprite.get_cell(chunk_index, cell_index).color);
}

Vector2i RegolithSprite::get_cell_count() const {
    godot::Vector2i cells = m_sprite.grid().cells;
    return is_loaded() ? Vector2i(cells.x, cells.y) : Vector2i();
}

int RegolithSprite::get_active_cell_count() const {
    return is_loaded() ? m_sprite.active_cell_count() : 0;
}

int RegolithSprite::count_cells_of_type(CellType type) const {
    if (!is_loaded() || type < 0 || static_cast<int>(type) >= SpriteCellMaskType_Count) {
        return 0;
    }

    return m_sprite.group(static_cast<SpriteCellMaskType>(type)).activeCount;
}

void RegolithSprite::repair_cells_of_type(CellType type) {
    if (!is_loaded() || type < 0 || static_cast<int>(type) >= SpriteCellMaskType_Count) {
        return;
    }

    m_sprite.repair_cell(static_cast<SpriteCellMaskType>(type));
}

void RegolithSprite::remove_cell(Vector2i cell) {
    if (!has_cell(cell)) {
        return;
    }

    auto [chunk_index, cell_index] = m_sprite.grid().to_chunk_cell_index(godot::Vector2i(cell.x, cell.y));
    m_sprite.remove_cell(chunk_index, cell_index);
}

void RegolithSprite::burn_cell(Vector2i cell, int strength, int damage) {
    if (!has_cell(cell)) {
        return;
    }

    auto [chunk_index, cell_index] = m_sprite.grid().to_chunk_cell_index(godot::Vector2i(cell.x, cell.y));
    sprite_burn_cell(m_sprite, chunk_index, cell_index, strength, damage);
}

void RegolithSprite::burn_fracture(Vector2i cell, int strength, int scorch_strength, float damage_ratio, int damage) {
    if (!has_cell(cell)) {
        return;
    }

    SpriteBurnProps props;
    props.strength = strength;
    props.scorch_strength = scorch_strength;
    props.damage_ratio = damage_ratio;
    props.damage = damage;

    sprite_burn_fracture(m_sprite, godot::Vector2i(cell.x, cell.y), props);
}

TypedArray<Vector2i> RegolithSprite::trace_cells(Vector2 from, Vector2 to, int max_cells) const {
    TypedArray<Vector2i> out;

    if (!is_loaded() || max_cells <= 0) {
        return out;
    }

    const Grid& grid = m_sprite.grid();

    godot::Vector2 start = grid.to_grid_point(m_transform.to_local_point(m_world->to_units(from)));
    godot::Vector2 end = grid.to_grid_point(m_transform.to_local_point(m_world->to_units(to)));

    auto [direction, distance] = safe_normalize_distance(end - start);

    for (GridLineIterator itr(start, direction, distance); itr.has_more(); itr.next()) {
        godot::Vector2i cell = itr.current();

        if (!grid.is_grid_index_position_valid(cell)) {
            continue;
        }

        auto [chunk_index, cell_index] = grid.to_chunk_cell_index(cell);

        if (m_sprite.is_chunk_active(chunk_index) && m_sprite.is_cell_active(chunk_index, cell_index)) {
            out.push_back(Vector2i(cell.x, cell.y));

            if (out.size() >= max_cells) {
                break;
            }
        }
    }

    return out;
}

float RegolithSprite::get_mass() const {
    return m_body.mass();
}

Vector2 RegolithSprite::get_velocity_at(Vector2 world_position) const {
    if (!m_world) {
        return Vector2();
    }

    godot::Vector2 local = m_transform.to_local_point(m_world->to_units(world_position));
    godot::Vector2 velocity = m_body.velocity_at_local_point(local);
    return Vector2(velocity.x, velocity.y);
}

Vector2 RegolithSprite::get_linear_velocity() const {
    return Vector2(m_body.linear_velocity.x, m_body.linear_velocity.y);
}

void RegolithSprite::set_linear_velocity(Vector2 velocity) {
    m_body.linear_velocity = godot::Vector2(velocity.x, velocity.y);
}

float RegolithSprite::get_angular_velocity() const {
    return m_body.angular_velocity;
}

void RegolithSprite::set_angular_velocity(float velocity) {
    m_body.angular_velocity = velocity;
}

void RegolithSprite::apply_impulse(Vector2 impulse, Vector2 world_position) {
    if (!m_world) {
        return;
    }

    godot::Vector2 center = m_transform.to_world_point(m_body.center_of_mass);
    godot::Vector2 r = m_world->to_units(world_position) - center;
    m_body.apply_impulse_r(godot::Vector2(impulse.x, impulse.y), r);
}

int RegolithSprite::get_rope_count() const {
    return static_cast<int>(m_ropes.ropes.size());
}

PackedVector2Array RegolithSprite::get_rope_points(int rope_index) const {
    PackedVector2Array out;

    if (!m_world || rope_index < 0 || rope_index >= static_cast<int>(m_ropes.ropes.size())) {
        return out;
    }

    for (const SpriteRopeNode& node : m_ropes.ropes[rope_index].nodes) {
        out.push_back(m_world->to_pixels(node.position));
    }

    return out;
}

Dictionary RegolithSprite::hit_rope(Vector2 from, Vector2 to) {
    Dictionary out;

    const Grid& grid = rope_grid();
    float radius = sprite_rope_radius(m_transform, grid);

    if (!m_world || !has_ropes() || radius <= 0.f) {
        return out;
    }

    SpriteRopeHitResult sweep;

    if (!find_rope_hit_segment(m_ropes, m_world->to_units(from), m_world->to_units(to), 2.f * radius, &sweep)) {
        return out;
    }

    SpriteRopeHitResult hit;

    if (!find_rope_hit_point(m_ropes, sweep.position, 2.f * radius, &hit)) {
        return out;
    }

    SpriteRope& rope = m_ropes.ropes[hit.rope_index];

    out["position"] = m_world->to_pixels(hit.position);
    out["rope"] = hit.rope_index;
    out["node"] = hit.node_index;
    out["cut"] = false;

    if (is_loaded() && !(m_sprite.damageable_classes() & (1u << rope.cell_class))) {
        return out;
    }

    if (hit.node_index >= 0 && hit.node_index < static_cast<int>(rope.node_health.size())) {
        uint8_t& health = rope.node_health[hit.node_index];

        if (health > 1) {
            health -= 1;
            return out;
        }
    }

    godot::Vector2 grid_pos = grid.to_grid_point(m_transform.to_local_point(hit.position));
    godot::Vector2 f = grid_pos.floor();
    godot::Vector2 pixel_world = m_transform.to_world_point(grid.to_local_point_centered(godot::Vector2i((int)f.x, (int)f.y)));

    godot::Vector2 a = rope.nodes[hit.segment_index].position;
    godot::Vector2 b = rope.nodes[hit.segment_index + 1].position;
    float t = closest_t_on_segment(a, b, pixel_world);

    SpriteRopeCutResult cut = cut_sprite_rope_at(m_ropes, hit.rope_index, hit.segment_index, t, 2.f * radius);

    if (!cut.did_cut) {
        return out;
    }

    out["cut"] = true;
    spawn_loose_pixels(cut.loose_pixels);
    after_rope_cut(cut.anchor_cells);

    return out;
}

bool RegolithSprite::cut_rope(int rope_index, int node_index) {
    if (rope_index < 0 || rope_index >= static_cast<int>(m_ropes.ropes.size())) {
        return false;
    }

    SpriteRopeCutResult cut = cut_sprite_rope(m_ropes, rope_index, node_index);

    if (!cut.did_cut) {
        return false;
    }

    spawn_loose_pixels(cut.loose_pixels);
    after_rope_cut(cut.anchor_cells);

    return true;
}

void RegolithSprite::spawn_loose_pixels(const godot::LocalVector<godot::Pair<godot::Vector2, Color4>>& pixels) {
    if (!m_world || pixels.is_empty()) {
        return;
    }

    for (const auto& [world, color] : pixels) {
        godot::Vector2 local = m_transform.to_local_point(world);
        m_world->spawn_cell_pixel(world, m_body.velocity_at_local_point(local), m_transform.angle, color);
    }

    m_world->emit_signal("cells_removed", this, static_cast<int>(pixels.size()));
}

void RegolithSprite::after_rope_cut(const godot::LocalVector<godot::Vector2i>& anchor_cells) {
    if (!is_loaded()) {
        if (m_world) {
            m_world->resplit_rope_piece(this);
        }

        return;
    }

    const Grid& grid = m_sprite.grid();
    godot::LocalVector<godot::Vector2i> cells;
    for (const godot::Vector2i& c : anchor_cells) cells.push_back(c);

    for (const SpriteRope& other : m_ropes.ropes) {
        for (const SpriteRopeAnchor* anchor : {&other.a, &other.b}) {
            if (anchor->type == SpriteRopeAnchorType_Cell) {
                cells.push_back(anchor->cell);
            }
        }
    }

    for (godot::Vector2i cell : cells) {
        if (grid.is_grid_index_position_valid(cell)) {
            auto [chunk_index, cell_index] = grid.to_chunk_cell_index(cell);
            m_sprite.mark_chunk_dirty(chunk_index);
        }
    }
}
