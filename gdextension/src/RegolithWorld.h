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
#include <godot_cpp/variant/typed_array.hpp>

#include <vector>

class RegolithSprite;

// the simulation: chunk pool with the atlas, physics world, sprite registry.
// each drawn frame commits cell changes and spawns pieces, each physics frame
// solves. drawing is done by the sprites, RegolithRopeRender, the cell
// particle child and RegolithDebugDraw
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
    vec2 to_units(godot::Vector2 pixels) const;
    godot::Vector2 to_pixels(vec2 units) const;

    void _enter_tree() override;
    void _exit_tree() override;
    void _process(double delta) override;
    void _physics_process(double delta) override;
    void _notification(int what);

    void commit_sprites();

    int get_sprite_count() const;
    godot::TypedArray<RegolithSprite> query_rect(godot::Rect2 rect) const;
    godot::TypedArray<RegolithSprite> query_segment(godot::Vector2 from, godot::Vector2 to) const;

    godot::Dictionary ray_cast(godot::Vector2 from, godot::Vector2 to, RegolithSprite* exclude) const;

    int hit_ropes(godot::Vector2 from, godot::Vector2 to, RegolithSprite* exclude);

    enum JointType {
        JOINT_PIN = RegolithJoints::Pin,
        JOINT_DISTANCE = RegolithJoints::Distance,
    };

    int add_joint(RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_point);

    int add_distance_joint(RegolithSprite* a, RegolithSprite* b, godot::Vector2 world_point_a, godot::Vector2 world_point_b, float rest_distance);

    void remove_joint(int joint_id);
    void clear_joints();
    int get_joint_count() const;
    godot::PackedVector2Array get_joint_anchors(int joint_id) const;
    godot::TypedArray<RegolithSprite> get_joint_sprites(int joint_id) const;
    int get_joint_type(int joint_id) const;

    godot::GPUParticles2D* get_cell_particles();
    void spawn_cell_particle(godot::Vector2 position, godot::Vector2 velocity, godot::Color color, float angle);
    void spawn_cell_pixel(vec2 position, vec2 velocity, float angle, Color4 color);
    void spawn_rope_pixels(RegolithSprite* source, const std::vector<SpriteRope>& ropes);

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

    const std::vector<RegolithSprite*>& sprites() const;
    const RegolithJoints& joints() const;
    const SpriteTree& tree() const;

protected:
    static void _bind_methods();

private:
    static float active_pixels_per_unit();
    static float active_pixels_per_cell();

    void start();
    void find_cell_particles();
    void step_physics(float delta_time);
    void decay_heat(float delta_time);
    void add_monitors();
    void remove_monitors();
    void free_sprite(RegolithSprite* node);

    RegolithSprite* spawn_piece(RegolithSprite* source, Sprite&& sprite, const Transform& transform, const PhysicsBody& body);
    RegolithSprite* spawn_rope_piece(RegolithSprite* source, std::vector<SpriteRope>&& group);
    void spawn_rope_group(RegolithSprite* source, std::vector<SpriteRope>&& group);

private:
    SpriteChunkPool m_pool;
    PhysicsWorld m_physics;
    std::vector<RegolithSprite*> m_sprites;
    SpriteTree m_tree;
    RegolithJoints m_joints;
    godot::GPUParticles2D* m_cell_particles = nullptr;

    int m_pixels_per_cell = 1;

    float m_time = 0.f;
    float m_heat_accumulator = 0.f;
    int m_heat_tick = 0;

    float m_commit_ms = 0.f;
    float m_physics_ms = 0.f;
    bool m_owns_monitors = false;
};

VARIANT_ENUM_CAST(RegolithWorld::JointType);
