#include "RegolithSprite.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void RegolithSprite::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_texture", "texture"), &RegolithSprite::set_texture);
    ClassDB::bind_method(D_METHOD("get_texture"), &RegolithSprite::get_texture);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "texture", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_texture", "get_texture");

    ClassDB::bind_method(D_METHOD("set_mask_texture", "texture"), &RegolithSprite::set_mask_texture);
    ClassDB::bind_method(D_METHOD("get_mask_texture"), &RegolithSprite::get_mask_texture);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "mask_texture", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_mask_texture", "get_mask_texture");

    ClassDB::bind_method(D_METHOD("set_repairable", "repairable"), &RegolithSprite::set_repairable);
    ClassDB::bind_method(D_METHOD("is_repairable"), &RegolithSprite::is_repairable);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "repairable"), "set_repairable", "is_repairable");

    ClassDB::bind_method(D_METHOD("create_blank", "size"), &RegolithSprite::create_blank);
    ClassDB::bind_method(D_METHOD("load_from_images", "color", "mask"), &RegolithSprite::load_from_images, DEFVAL(Ref<Image>()));
    ClassDB::bind_method(D_METHOD("get_color_image"), &RegolithSprite::get_color_image);
    ClassDB::bind_method(D_METHOD("get_mask_image"), &RegolithSprite::get_mask_image);
    ClassDB::bind_method(D_METHOD("set_cell", "cell", "color", "type", "cell_class"), &RegolithSprite::set_cell, DEFVAL(CELL_FILLED), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("clear_cell", "cell"), &RegolithSprite::clear_cell);
    ClassDB::bind_method(D_METHOD("fill_rect", "rect", "color", "type", "cell_class"), &RegolithSprite::fill_rect, DEFVAL(CELL_FILLED), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("clear_rect", "rect"), &RegolithSprite::clear_rect);
    ClassDB::bind_method(D_METHOD("is_loaded"), &RegolithSprite::is_loaded);

    ClassDB::bind_method(D_METHOD("set_dynamic", "dynamic"), &RegolithSprite::set_dynamic);
    ClassDB::bind_method(D_METHOD("is_dynamic"), &RegolithSprite::is_dynamic);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "dynamic"), "set_dynamic", "is_dynamic");

    ClassDB::bind_method(D_METHOD("set_rope_material", "material"), &RegolithSprite::set_rope_material);
    ClassDB::bind_method(D_METHOD("get_rope_material"), &RegolithSprite::get_rope_material);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "rope_material", PROPERTY_HINT_RESOURCE_TYPE, "ShaderMaterial"), "set_rope_material", "get_rope_material");

    ClassDB::bind_method(D_METHOD("set_angle_fixed", "fixed"), &RegolithSprite::set_angle_fixed);
    ClassDB::bind_method(D_METHOD("is_angle_fixed"), &RegolithSprite::is_angle_fixed);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "angle_fixed"), "set_angle_fixed", "is_angle_fixed");

    ClassDB::bind_method(D_METHOD("set_rope_angle_stiffness", "stiffness"), &RegolithSprite::set_rope_angle_stiffness);
    ClassDB::bind_method(D_METHOD("get_rope_angle_stiffness"), &RegolithSprite::get_rope_angle_stiffness);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rope_angle_stiffness"), "set_rope_angle_stiffness", "get_rope_angle_stiffness");

    ClassDB::bind_method(D_METHOD("set_linear_damping", "damping"), &RegolithSprite::set_linear_damping);
    ClassDB::bind_method(D_METHOD("get_linear_damping"), &RegolithSprite::get_linear_damping);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "linear_damping", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater"), "set_linear_damping", "get_linear_damping");

    ClassDB::bind_method(D_METHOD("set_angular_damping", "damping"), &RegolithSprite::set_angular_damping);
    ClassDB::bind_method(D_METHOD("get_angular_damping"), &RegolithSprite::get_angular_damping);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "angular_damping", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater"), "set_angular_damping", "get_angular_damping");

    ClassDB::bind_method(D_METHOD("world_to_cell", "world_position"), &RegolithSprite::world_to_cell);
    ClassDB::bind_method(D_METHOD("cell_to_world", "cell"), &RegolithSprite::cell_to_world);
    ClassDB::bind_method(D_METHOD("world_to_local", "world_position"), &RegolithSprite::world_to_local);
    ClassDB::bind_method(D_METHOD("local_to_world", "local_point"), &RegolithSprite::local_to_world);
    ClassDB::bind_method(D_METHOD("world_to_grid_point", "world_position"), &RegolithSprite::world_to_grid_point);
    ClassDB::bind_method(D_METHOD("grid_point_to_world", "grid_point"), &RegolithSprite::grid_point_to_world);
    ClassDB::bind_method(D_METHOD("local_to_grid_point", "local_point"), &RegolithSprite::local_to_grid_point);
    ClassDB::bind_method(D_METHOD("grid_point_to_local", "grid_point"), &RegolithSprite::grid_point_to_local);
    ClassDB::bind_method(D_METHOD("cell_to_local", "cell"), &RegolithSprite::cell_to_local);
    ClassDB::bind_method(D_METHOD("cell_to_grid_point", "cell"), &RegolithSprite::cell_to_grid_point);
    ClassDB::bind_method(D_METHOD("has_cell", "cell"), &RegolithSprite::has_cell);
    ClassDB::bind_method(D_METHOD("get_cell_type", "cell"), &RegolithSprite::get_cell_type);
    ClassDB::bind_method(D_METHOD("get_cell_class", "cell"), &RegolithSprite::get_cell_class);
    ClassDB::bind_method(D_METHOD("get_cell_color", "cell"), &RegolithSprite::get_cell_color);
    ClassDB::bind_method(D_METHOD("count_cells_of_type", "type"), &RegolithSprite::count_cells_of_type);
    ClassDB::bind_method(D_METHOD("repair_cells_of_type", "type"), &RegolithSprite::repair_cells_of_type);
    ClassDB::bind_method(D_METHOD("repair_all_cells"), &RegolithSprite::repair_all_cells);
    ClassDB::bind_method(D_METHOD("remove_all_cells"), &RegolithSprite::remove_all_cells);
    ClassDB::bind_method(D_METHOD("remove_cell", "cell"), &RegolithSprite::remove_cell);
    ClassDB::bind_method(D_METHOD("burn_cell", "cell", "strength", "damage"), &RegolithSprite::burn_cell, DEFVAL(255), DEFVAL(1));
    ClassDB::bind_method(D_METHOD("burn_fracture", "cell", "strength", "scorch_strength", "damage_ratio", "damage"), &RegolithSprite::burn_fracture, DEFVAL(255), DEFVAL(110), DEFVAL(0.65f), DEFVAL(1));
    ClassDB::bind_method(D_METHOD("trace_cells", "from", "to", "max_cells"), &RegolithSprite::trace_cells, DEFVAL(64));
    ClassDB::bind_method(D_METHOD("get_velocity_at", "world_position"), &RegolithSprite::get_velocity_at);

    ClassDB::bind_method(D_METHOD("get_cell_count"), &RegolithSprite::get_cell_count);
    ClassDB::bind_method(D_METHOD("get_active_cell_count"), &RegolithSprite::get_active_cell_count);
    ClassDB::bind_method(D_METHOD("get_mass"), &RegolithSprite::get_mass);
    ClassDB::bind_method(D_METHOD("get_center_of_mass"), &RegolithSprite::get_center_of_mass);
    ClassDB::bind_method(D_METHOD("get_rope_count"), &RegolithSprite::get_rope_count);
    ClassDB::bind_method(D_METHOD("get_rope_points", "rope_index"), &RegolithSprite::get_rope_points);
    ClassDB::bind_method(D_METHOD("hit_rope", "from", "to"), &RegolithSprite::hit_rope);
    ClassDB::bind_method(D_METHOD("cut_rope", "rope_index", "node_index"), &RegolithSprite::cut_rope);

    ClassDB::bind_method(D_METHOD("set_linear_velocity", "velocity"), &RegolithSprite::set_linear_velocity);
    ClassDB::bind_method(D_METHOD("get_linear_velocity"), &RegolithSprite::get_linear_velocity);
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "linear_velocity", PROPERTY_HINT_NONE, "suffix:m/s", PROPERTY_USAGE_EDITOR), "set_linear_velocity", "get_linear_velocity");

    ClassDB::bind_method(D_METHOD("set_angular_velocity", "velocity"), &RegolithSprite::set_angular_velocity);
    ClassDB::bind_method(D_METHOD("get_angular_velocity"), &RegolithSprite::get_angular_velocity);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "angular_velocity", PROPERTY_HINT_NONE, "radians_as_degrees", PROPERTY_USAGE_EDITOR), "set_angular_velocity", "get_angular_velocity");

    ClassDB::bind_method(D_METHOD("apply_impulse", "impulse", "world_position", "max_delta_speed", "max_delta_spin"), &RegolithSprite::apply_impulse, DEFVAL(0.0f), DEFVAL(0.0f));
    ClassDB::bind_method(D_METHOD("_reload"), &RegolithSprite::_reload);

    ClassDB::bind_method(D_METHOD("get_core_count"), &RegolithSprite::get_core_count);
    ClassDB::bind_method(D_METHOD("get_core_type", "index"), &RegolithSprite::get_core_type);
    ClassDB::bind_method(D_METHOD("get_core_position", "index"), &RegolithSprite::get_core_position);
    ClassDB::bind_method(D_METHOD("get_core_initial_cells", "index"), &RegolithSprite::get_core_initial_cells);
    ClassDB::bind_method(D_METHOD("get_core_remaining_cells", "index"), &RegolithSprite::get_core_remaining_cells);
    ClassDB::bind_method(D_METHOD("get_core_damage", "index"), &RegolithSprite::get_core_damage);
    ClassDB::bind_method(D_METHOD("set_cores_unstable"), &RegolithSprite::set_cores_unstable);
    ClassDB::bind_method(D_METHOD("repair_cores"), &RegolithSprite::repair_cores);
    ClassDB::bind_method(D_METHOD("update_cores"), &RegolithSprite::update_cores);
    ClassDB::bind_static_method("RegolithSprite", D_METHOD("is_core_type", "type"), &RegolithSprite::is_core_type);

    ClassDB::bind_method(D_METHOD("set_core_explode_damage", "damage"), &RegolithSprite::set_core_explode_damage);
    ClassDB::bind_method(D_METHOD("get_core_explode_damage"), &RegolithSprite::get_core_explode_damage);
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "core_explode_damage", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_core_explode_damage", "get_core_explode_damage");

    ADD_SIGNAL(MethodInfo("core_exploded", PropertyInfo(Variant::VECTOR2, "position"), PropertyInfo(Variant::INT, "power"), PropertyInfo(Variant::INT, "type")));

    BIND_ENUM_CONSTANT(CELL_EMPTY);
    BIND_ENUM_CONSTANT(CELL_FILLED);
    BIND_ENUM_CONSTANT(CELL_CORE);
    BIND_ENUM_CONSTANT(CELL_WEAKPOINT1);
    BIND_ENUM_CONSTANT(CELL_WEAKPOINT2);
    BIND_ENUM_CONSTANT(CELL_WEAKPOINT3);
    BIND_ENUM_CONSTANT(CELL_WEAKPOINT4);
    BIND_ENUM_CONSTANT(CELL_JOINT1);
    BIND_ENUM_CONSTANT(CELL_JOINT2);
    BIND_ENUM_CONSTANT(CELL_JOINT3);
    BIND_ENUM_CONSTANT(CELL_JOINT4);
    BIND_ENUM_CONSTANT(CELL_ROPE);
}
