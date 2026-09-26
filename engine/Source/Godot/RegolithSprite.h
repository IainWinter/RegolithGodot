#include <godot_cpp/templates/pair.hpp>
#pragma once

#include "DestructibleSprite/Sprite.h"
#include "Physics/Body.h"
#include "DestructibleSprite/SpriteRope.h"
#include "Coordinate/Transform.h"

#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rid.hpp>

class RegolithWorld;

// a destructible pixel sprite with a rigid body. cells are the pixels of the
// texture, the world commits removed cells and splits off pieces that no
// longer connect. draws its chunks from the world's atlas through its material,
// ropes draw from a RegolithRopeRender child
class RegolithSprite : public godot::Node2D {
    GDCLASS(RegolithSprite, godot::Node2D)

public:
    enum CellType {
        CELL_EMPTY,
        CELL_FILLED,
        CELL_CORE,
        CELL_WEAKPOINT1,
        CELL_WEAKPOINT2,
        CELL_WEAKPOINT3,
        CELL_WEAKPOINT4,
        CELL_JOINT1,
        CELL_JOINT2,
        CELL_JOINT3,
        CELL_JOINT4,
        CELL_ROPE,
    };

    RegolithSprite();
    ~RegolithSprite();

    void _exit_tree() override;
    void _draw() override;
    void _notification(int what);

    void set_texture(const godot::Ref<godot::Texture2D>& texture);
    godot::Ref<godot::Texture2D> get_texture() const;

    void set_mask_texture(const godot::Ref<godot::Texture2D>& texture);
    godot::Ref<godot::Texture2D> get_mask_texture() const;

    void set_repairable(bool repairable);
    bool is_repairable() const;

    void set_angle_fixed(bool fixed);
    bool is_angle_fixed() const;

    // how hard the ropes pull back to their rest shape, 0.02 hangs limp
    // and 0.3 holds shape (the original SpriteRopeSet::angle_stiffness).
    // negative means the asset's value stays
    void set_rope_angle_stiffness(float stiffness);
    float get_rope_angle_stiffness() const;

    void set_linear_damping(float damping);
    float get_linear_damping() const;

    void set_angular_damping(float damping);
    float get_angular_damping() const;

    void set_dynamic(bool dynamic);
    bool is_dynamic() const;

    void set_rope_material(const godot::Ref<godot::Material>& material);
    godot::Ref<godot::Material> get_rope_material() const;

    void create_blank(godot::Vector2i size);
    void load_from_images(const godot::Ref<godot::Image>& color, const godot::Ref<godot::Image>& mask);
    godot::Ref<godot::Image> get_color_image() const;
    godot::Ref<godot::Image> get_mask_image() const;
    void set_cell(godot::Vector2i cell, godot::Color color, CellType type, int cell_class);
    void clear_cell(godot::Vector2i cell);
    void fill_rect(godot::Rect2i rect, godot::Color color, CellType type, int cell_class);
    void clear_rect(godot::Rect2i rect);

    godot::Vector2i world_to_cell(godot::Vector2 world_position) const;
    godot::Vector2 cell_to_world(godot::Vector2i cell) const;

    // the coordinate frames of the original (Frames.h, Transform, Grid):
    // world pixels <-> local point (-1..1 spanning the whole grid, y down)
    // <-> grid point (0..cells, floating) <-> cell (integer grid index)
    godot::Vector2 world_to_local(godot::Vector2 world_position) const;
    godot::Vector2 local_to_world(godot::Vector2 local_point) const;
    godot::Vector2 world_to_grid_point(godot::Vector2 world_position) const;
    godot::Vector2 grid_point_to_world(godot::Vector2 grid_point) const;
    godot::Vector2 local_to_grid_point(godot::Vector2 local_point) const;
    godot::Vector2 grid_point_to_local(godot::Vector2 grid_point) const;
    godot::Vector2 cell_to_local(godot::Vector2i cell) const;
    godot::Vector2 cell_to_grid_point(godot::Vector2i cell) const;
    bool has_cell(godot::Vector2i cell) const;
    CellType get_cell_type(godot::Vector2i cell) const;
    int get_cell_class(godot::Vector2i cell) const;
    godot::Color get_cell_color(godot::Vector2i cell) const;
    godot::Vector2i get_cell_count() const;
    int get_active_cell_count() const;
    int count_cells_of_type(CellType type) const;

    void repair_cells_of_type(CellType type);
    void repair_all_cells();
    void remove_all_cells();

    void remove_cell(godot::Vector2i cell);
    void burn_cell(godot::Vector2i cell, int strength, int damage);
    void burn_fracture(godot::Vector2i cell, int strength, int scorch_strength, float damage_ratio, int damage);

    godot::TypedArray<godot::Vector2i> trace_cells(godot::Vector2 from, godot::Vector2 to, int max_cells) const;

    float get_mass() const;
    godot::Vector2 get_center_of_mass() const;
    godot::Vector2 get_velocity_at(godot::Vector2 world_position) const;
    godot::Vector2 get_linear_velocity() const;
    void set_linear_velocity(godot::Vector2 velocity);
    float get_angular_velocity() const;
    void set_angular_velocity(float velocity);
    void apply_impulse(godot::Vector2 impulse, godot::Vector2 world_position, float max_delta_speed = 0.f, float max_delta_spin = 0.f);

    int get_rope_count() const;
    godot::PackedVector2Array get_rope_points(int rope_index) const;

    godot::Dictionary hit_rope(godot::Vector2 from, godot::Vector2 to);
    bool cut_rope(int rope_index, int node_index);

    // cores: the Core, Weakpoint and Joint cell groups found in the mask.
    // the world checks them after every commit that touched the sprite, once
    // after load and when set_cores_unstable is called, and the sprite emits
    // core_exploded(position, power, type) for any that went unstable, right
    // before the world's core_exploded(sprite, position, power, type).
    // positions in world pixels
    int get_core_count() const;
    CellType get_core_type(int index) const;
    godot::Vector2 get_core_position(int index) const;
    int get_core_initial_cells(int index) const;
    int get_core_remaining_cells(int index) const;
    float get_core_damage(int index) const;
    void set_core_explode_damage(float damage);
    float get_core_explode_damage() const;
    void set_cores_unstable();
    void repair_cores();
    void update_cores();

    // true for the Core and Weakpoint1-4 cell types, the ones that make a core
    static bool is_core_type(int type);

    RegolithWorld* world() const;
    bool is_loaded() const;
    bool has_ropes() const;
    Sprite& sprite();
    PhysicsBody& body();
    Transform& transform();
    SpriteRopeSet& ropes();

    const Grid& rope_grid() const;

    void init_piece(RegolithWorld* world, Sprite&& sprite, const Transform& transform, const PhysicsBody& body, bool dynamic);

    void init_rope_piece(RegolithWorld* world, const Transform& transform, const Grid& grid, SpriteRopeSet&& ropes);

    Transform render_pose(float fraction) const;

    void sync_node_from_body();
    void sync_body_from_node();
    void apply_mass();
    void release();

protected:
    static void _bind_methods();

private:
    void ready();
    void load(RegolithWorld* world);
    void load_asset(RegolithWorld* world, SpriteAsset& asset);
    void attach();
    void detach();
    void bind_material();
    void ensure_rope_render();
    void draw_preview();
    void clear_preview();
    void paint(godot::Vector2i cell, godot::Color color, SpriteCellMask mask);
    void _reload();
    void after_rope_cut(const godot::LocalVector<godot::Vector2i>& anchor_cells);
    void spawn_loose_pixels(const godot::LocalVector<godot::Pair<godot::Vector2, Color4>>& pixels);

    // null when not loaded or index is out of range
    const SpriteCore* core_at(int index) const;

    // a grid point of this node's grid (the rope grid for a rope only piece)
    // in sim units and in world pixels
    godot::Vector2 grid_point_to_units(godot::Vector2 grid_point) const;

private:
    godot::Ref<godot::Texture2D> m_texture;
    godot::Ref<godot::Texture2D> m_mask_texture;
    godot::Ref<godot::Material> m_rope_material;
    godot::Ref<godot::Material> m_bound_material;
    godot::RID m_preview;
    bool m_dynamic = true;
    bool m_repairable = false;
    bool m_angle_fixed = false;
    float m_rope_angle_stiffness = -1.f;
    float m_linear_damping = 0.01f;
    float m_angular_damping = 0.01f;
    float m_core_explode_damage = k_core_explode_damage;

    RegolithWorld* m_world = nullptr;
    Sprite m_sprite;
    PhysicsBody m_body;
    Transform m_transform;
    SpriteRopeSet m_ropes;
    Grid m_rope_grid;
};

VARIANT_ENUM_CAST(RegolithSprite::CellType);
