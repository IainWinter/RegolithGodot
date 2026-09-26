#pragma once

#include "RegolithJoints.h"
#include "SpriteTree.h"

#include "DestructibleSprite/SpriteChunkPool.h"
#include "DestructibleSprite/SpriteRope.h"
#include "Physics/World.h"
#include "Constants.h"

#include <godot_cpp/classes/gpu_particles2d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/templates/local_vector.hpp>

class RegolithSprite;
struct PathfindWorld;

// the simulation: chunk pool with the atlas, physics world, sprite registry.
// each drawn frame commits cell changes and spawns pieces, each physics frame
// solves. drawing is done by the sprites, RegolithRopeRender, the cell
// particle child and RegolithDebugDraw.
//
// signals: sprite_split(source, piece), sprite_destroyed(sprite),
// sprite_emptied(sprite), cells_removed(sprite, count) and
// core_exploded(sprite, position, power, type), the world level copy of a
// sprite's core_exploded emitted right after it so one connection covers
// every sprite. cores are checked at commit for the sprites it touched
class RegolithWorld : public godot::Node {
    GDCLASS(RegolithWorld, godot::Node)

public:
    enum {
        CELLS_PER_CHUNK = k_cells_per_chunk,
        SDF_BAND_CELLS = static_cast<int>(k_sdf_band_cells),
        CAMERA_HEIGHT = static_cast<int>(k_camera_height),
        ATLAS_PAGE_SIZE = k_atlas_page_size,
        ATLAS_PAGE_COUNT = k_atlas_page_count,
    };

    RegolithWorld();
    ~RegolithWorld();

    static RegolithWorld* active();

    float pixels_per_unit() const;
    godot::Vector2 to_units(godot::Vector2 pixels) const;
    godot::Vector2 to_pixels(godot::Vector2 units) const;

    void _enter_tree() override;
    void _exit_tree() override;
    void _process(double delta) override;
    void _physics_process(double delta) override;
    void _notification(int what);

    void commit_sprites();

    int get_sprite_count() const;
    godot::TypedArray<RegolithSprite> query_rect(godot::Rect2 rect) const;
    godot::TypedArray<RegolithSprite> query_segment(godot::Vector2 from, godot::Vector2 to) const;

    godot::Dictionary ray_cast(godot::Vector2 from, godot::Vector2 to, RegolithSprite* exclude, const godot::PackedStringArray& ignore_groups) const;

    // pathfinding over the sprite tree, pixels in and out. sprites in
    // ignore_groups and the exclude sprite never block
    godot::PackedVector2Array find_path(godot::Vector2 from, godot::Vector2 to, float cell_size, RegolithSprite* exclude, const godot::PackedStringArray& ignore_groups, int max_expansions) const;
    bool has_line_of_sight(godot::Vector2 from, godot::Vector2 to, RegolithSprite* exclude, const godot::PackedStringArray& ignore_groups) const;
    bool is_point_blocked(godot::Vector2 point, RegolithSprite* exclude, const godot::PackedStringArray& ignore_groups) const;
    bool is_path_clear(godot::Vector2 from, const godot::PackedVector2Array& path, godot::Vector2 goal, RegolithSprite* exclude, const godot::PackedStringArray& ignore_groups) const;
    static godot::PackedVector2Array advance_waypoints(const godot::PackedVector2Array& path, godot::Vector2 position, float capture_radius);
    void draw_path(godot::Vector2 from, const godot::PackedVector2Array& path, godot::Vector2 goal) const;

    int hit_ropes(godot::Vector2 from, godot::Vector2 to, RegolithSprite* exclude);

    enum JointType {
        JOINT_PIN = RegolithJoints::Pin,
        JOINT_DISTANCE = RegolithJoints::Distance,
    };

    // collide_connected false: the two sprites pass through each other, for
    // parts built overlapping (a barrel on its mount). true keeps contacts
    int add_joint(RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_point, bool collide_connected = true);

    int add_distance_joint(RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_point_a, godot::Vector2 world_point_b, float rest_distance, bool collide_connected = true);

    void remove_joint(int joint_id);
    void clear_joints();
    int get_joint_count() const;
    godot::PackedInt32Array get_joint_ids() const;
    godot::PackedVector2Array get_joint_anchors(int joint_id) const;
    godot::TypedArray<RegolithSprite> get_joint_sprites(int joint_id) const;
    int get_joint_type(int joint_id) const;
    bool get_joint_collide_connected(int joint_id) const;

    // cells glowing at min_heat or more (0-15, read from 8 up, see
    // Sprite::k_hot_cell_heat) across every sprite, as x, y world pixels and
    // z heat. only sprites holding a hot cell list are read and the lists
    // are kept by heat writes and the decay pass, so this never scans a
    // sprite. more than max_count are sampled down evenly
    godot::PackedVector3Array get_hot_cells(int min_heat, int max_count) const;

    godot::GPUParticles2D* get_cell_particles();
    void spawn_cell_particle(godot::Vector2 position, godot::Vector2 velocity, godot::Color color, float angle);
    void spawn_cell_pixel(godot::Vector2 position, godot::Vector2 velocity, float angle, Color4 color);
    void spawn_rope_pixels(RegolithSprite* source, const godot::LocalVector<SpriteRope>& ropes);

    void set_pixels_per_cell(int pixels);
    int get_pixels_per_cell() const;

    void set_gravity(godot::Vector2 gravity);
    godot::Vector2 get_gravity() const;

    void set_substeps(int substeps);
    int get_substeps() const;

    godot::Ref<godot::Texture2DArray> get_color_atlas() const;
    godot::Ref<godot::Texture2DArray> get_mask_atlas() const;

    float get_commit_time_ms() const;
    float get_physics_time_ms() const;
    int get_contact_count() const;
    int get_rope_count() const;

    SpriteChunkPool& pool();
    PhysicsWorld& physics();

    void register_sprite(RegolithSprite* sprite);
    void unregister_sprite(RegolithSprite* sprite);

    void resplit_rope_piece(RegolithSprite* node);

    const godot::LocalVector<RegolithSprite*>& sprites() const;
    const RegolithJoints& joints() const;
    const SpriteTree& tree() const;

    static float active_pixels_per_unit();
    static float active_pixels_per_cell();

protected:
    static void _bind_methods();

private:
    void start();
    void find_cell_particles();
    void step_physics(float delta_time);
    void reset_collision_priority();
    void decay_heat(float delta_time);
    void add_monitors();
    void remove_monitors();
    void free_sprite(RegolithSprite* node);

    // cell_size in sim units
    PathfindWorld make_pathfind_world(RegolithSprite* exclude, const godot::PackedStringArray& ignore_groups, float cell_size = 1.f) const;

    RegolithSprite* spawn_piece(RegolithSprite* source, Sprite&& sprite, const Transform& transform, const PhysicsBody& body);
    RegolithSprite* spawn_rope_piece(RegolithSprite* source, godot::LocalVector<SpriteRope>&& group);
    void spawn_rope_group(RegolithSprite* source, godot::LocalVector<SpriteRope>&& group);

private:
    SpriteChunkPool m_pool;
    PhysicsWorld m_physics;
    godot::LocalVector<RegolithSprite*> m_sprites;
    SpriteTree m_tree;
    RegolithJoints m_joints;
    godot::GPUParticles2D* m_cell_particles = nullptr;
    // scratch of reset_collision_priority, kept so it is not rebuilt each step
    godot::HashSet<uint64_t> m_touching;

    int m_pixels_per_cell = 1;

    float m_time = 0.f;
    float m_heat_accumulator = 0.f;
    int m_heat_tick = 0;

    float m_commit_ms = 0.f;
    float m_physics_ms = 0.f;
    bool m_owns_monitors = false;
};

VARIANT_ENUM_CAST(RegolithWorld::JointType);
