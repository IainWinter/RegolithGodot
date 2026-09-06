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

class RegolithWorld;

// a destructible pixel sprite with a rigid body. cells are the pixels of the
// texture, the world commits removed cells and splits off pieces that no
// longer connect. draws its chunks from the world's atlas through its material,
// ropes draw from a RegolithRopeRender child
class RegolithSprite : public godot::Node2D {
    GDCLASS(RegolithSprite, godot::Node2D)

public:
    // matches SpriteCellMaskType
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

    void _ready() override;
    void _exit_tree() override;
    void _draw() override;
    void _notification(int what);

    // properties

    void set_texture(const godot::Ref<godot::Texture2D>& texture);
    godot::Ref<godot::Texture2D> get_texture() const;

    // same size as the texture, colors pick each cell's type and class
    void set_mask_texture(const godot::Ref<godot::Texture2D>& texture);
    godot::Ref<godot::Texture2D> get_mask_texture() const;

    void set_repairable(bool repairable);
    bool is_repairable() const;

    void set_angle_fixed(bool fixed);
    bool is_angle_fixed() const;

    void set_linear_damping(float damping);
    float get_linear_damping() const;

    void set_angular_damping(float damping);
    float get_angular_damping() const;

    void set_dynamic(bool dynamic);
    bool is_dynamic() const;

    void set_rope_material(const godot::Ref<godot::Material>& material);
    godot::Ref<godot::Material> get_rope_material() const;

    // no physics and no commit while editing, paint freely
    void set_editing(bool editing);
    bool is_editing() const;

    // editor api, cells are grid positions

    void create_blank(godot::Vector2i size);
    void load_from_images(const godot::Ref<godot::Image>& color, const godot::Ref<godot::Image>& mask);
    godot::Ref<godot::Image> get_color_image() const;
    godot::Ref<godot::Image> get_mask_image() const;
    void set_cell(godot::Vector2i cell, godot::Color color, CellType type, int cell_class);
    void clear_cell(godot::Vector2i cell);
    void fill_rect(godot::Rect2i rect, godot::Color color, CellType type, int cell_class);
    void clear_rect(godot::Rect2i rect);

    // cells

    // (-1, -1) when outside the grid
    godot::Vector2i world_to_cell(godot::Vector2 world_position) const;
    godot::Vector2 cell_to_world(godot::Vector2i cell) const;
    bool has_cell(godot::Vector2i cell) const;
    CellType get_cell_type(godot::Vector2i cell) const;
    int get_cell_class(godot::Vector2i cell) const;
    godot::Color get_cell_color(godot::Vector2i cell) const;
    godot::Vector2i get_cell_count() const;
    int get_active_cell_count() const;
    int count_cells_of_type(CellType type) const;

    // only for repairable sprites
    void repair_cells_of_type(CellType type);

    void remove_cell(godot::Vector2i cell);
    void burn_cell(godot::Vector2i cell, int strength, int damage);
    void burn_fracture(godot::Vector2i cell, int strength, int scorch_strength, float damage_ratio, int damage);

    // filled cells along a world segment in hit order
    godot::TypedArray<godot::Vector2i> trace_cells(godot::Vector2 from, godot::Vector2 to, int max_cells) const;

    // body

    float get_mass() const;
    godot::Vector2 get_velocity_at(godot::Vector2 world_position) const;
    godot::Vector2 get_linear_velocity() const;
    void set_linear_velocity(godot::Vector2 velocity);
    float get_angular_velocity() const;
    void set_angular_velocity(float velocity);
    void apply_impulse(godot::Vector2 impulse, godot::Vector2 world_position);

    // ropes, chains scanned from rope cells in the mask

    int get_rope_count() const;
    godot::PackedVector2Array get_rope_points(int rope_index) const;

    // a bullet sweep against this node's ropes. the first rope hit loses node
    // health, at zero it is cut there. empty when nothing was hit, else
    // position, rope, node and cut
    godot::Dictionary hit_rope(godot::Vector2 from, godot::Vector2 to);
    bool cut_rope(int rope_index, int node_index);

    // world side

    RegolithWorld* world() const;
    bool is_loaded() const;
    bool has_ropes() const;
    Sprite& sprite();
    PhysicsBody& body();
    Transform& transform();
    SpriteRopeSet& ropes();

    // the sprite's grid, or the kept grid of a rope piece
    const Grid& rope_grid() const;

    void init_piece(RegolithWorld* world, Sprite&& sprite, const Transform& transform, const PhysicsBody& body, bool dynamic);

    // a rope group cut loose: no cells and no body, keeps the source grid for its cell units
    void init_rope_piece(RegolithWorld* world, const Transform& transform, const Grid& grid, SpriteRopeSet&& ropes);

    // where the node is drawn this frame, dynamic bodies interpolate by fraction
    Transform render_pose(float fraction) const;

    void sync_node_from_body();
    void sync_body_from_node();
    void apply_mass();
    void release();

protected:
    static void _bind_methods();

private:
    void load(RegolithWorld* world);
    void load_asset(RegolithWorld* world, SpriteAsset& asset);
    void attach();
    void detach();
    void bind_material();
    void ensure_rope_render();
    void paint(godot::Vector2i cell, godot::Color color, SpriteCellMask mask);
    void _reload();
    void after_rope_cut(const std::vector<ivec2>& anchor_cells);
    void spawn_loose_pixels(const std::vector<std::pair<vec2, Color4>>& pixels);

private:
    godot::Ref<godot::Texture2D> m_texture;
    godot::Ref<godot::Texture2D> m_mask_texture;
    godot::Ref<godot::Material> m_rope_material;
    godot::Ref<godot::Material> m_bound_material;
    bool m_dynamic = true;
    bool m_editing = false;
    bool m_repairable = false;
    bool m_angle_fixed = false;
    float m_linear_damping = 0.01f;
    float m_angular_damping = 0.01f;

    RegolithWorld* m_world = nullptr;
    Sprite m_sprite;
    PhysicsBody m_body;
    Transform m_transform;
    SpriteRopeSet m_ropes;
    Grid m_rope_grid;
};

VARIANT_ENUM_CAST(RegolithSprite::CellType);
