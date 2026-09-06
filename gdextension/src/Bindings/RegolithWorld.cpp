#include "RegolithWorld.h"
#include "RegolithSprite.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void RegolithWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("commit_sprites"), &RegolithWorld::commit_sprites);
    ClassDB::bind_method(D_METHOD("get_sprite_count"), &RegolithWorld::get_sprite_count);
    ClassDB::bind_method(D_METHOD("query_rect", "rect"), &RegolithWorld::query_rect);
    ClassDB::bind_method(D_METHOD("query_segment", "from", "to"), &RegolithWorld::query_segment);
    ClassDB::bind_method(D_METHOD("ray_cast", "from", "to", "exclude"), &RegolithWorld::ray_cast, DEFVAL(nullptr));
    ClassDB::bind_method(D_METHOD("hit_ropes", "from", "to", "exclude"), &RegolithWorld::hit_ropes, DEFVAL(nullptr));
    ClassDB::bind_method(D_METHOD("add_joint", "a", "b", "world_point"), &RegolithWorld::add_joint);
    ClassDB::bind_method(D_METHOD("remove_joint", "joint_id"), &RegolithWorld::remove_joint);
    ClassDB::bind_method(D_METHOD("clear_joints"), &RegolithWorld::clear_joints);
    ClassDB::bind_method(D_METHOD("get_joint_count"), &RegolithWorld::get_joint_count);
    ClassDB::bind_method(D_METHOD("get_joint_position", "joint_id"), &RegolithWorld::get_joint_position);
    ClassDB::bind_method(D_METHOD("get_color_atlas"), &RegolithWorld::get_color_atlas);
    ClassDB::bind_method(D_METHOD("get_mask_atlas"), &RegolithWorld::get_mask_atlas);
    ClassDB::bind_method(D_METHOD("get_commit_time_ms"), &RegolithWorld::get_commit_time_ms);
    ClassDB::bind_method(D_METHOD("get_physics_time_ms"), &RegolithWorld::get_physics_time_ms);
    ClassDB::bind_method(D_METHOD("get_contact_count"), &RegolithWorld::get_contact_count);
    ClassDB::bind_method(D_METHOD("get_rope_count"), &RegolithWorld::get_rope_count);
    ClassDB::bind_method(D_METHOD("spawn_cell_particle", "position", "velocity", "color", "angle"), &RegolithWorld::spawn_cell_particle, DEFVAL(0.f));
    ClassDB::bind_method(D_METHOD("get_cell_particles"), &RegolithWorld::get_cell_particles);

    ClassDB::bind_static_method("RegolithWorld", D_METHOD("active"), &RegolithWorld::active);
    ClassDB::bind_static_method("RegolithWorld", D_METHOD("pixels_per_unit"), &RegolithWorld::active_pixels_per_unit);

    ClassDB::bind_method(D_METHOD("set_pixels_per_cell", "pixels"), &RegolithWorld::set_pixels_per_cell);
    ClassDB::bind_method(D_METHOD("get_pixels_per_cell"), &RegolithWorld::get_pixels_per_cell);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "pixels_per_cell", PROPERTY_HINT_RANGE, "1,16,1"), "set_pixels_per_cell", "get_pixels_per_cell");

    ClassDB::bind_method(D_METHOD("set_gravity", "gravity"), &RegolithWorld::set_gravity);
    ClassDB::bind_method(D_METHOD("get_gravity"), &RegolithWorld::get_gravity);
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "gravity", PROPERTY_HINT_NONE, "suffix:m/s/s"), "set_gravity", "get_gravity");

    ClassDB::bind_method(D_METHOD("set_substeps", "substeps"), &RegolithWorld::set_substeps);
    ClassDB::bind_method(D_METHOD("get_substeps"), &RegolithWorld::get_substeps);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "substeps", PROPERTY_HINT_RANGE, "1,32,1"), "set_substeps", "get_substeps");

    BIND_CONSTANT(CELLS_PER_CHUNK);
    BIND_CONSTANT(SDF_BAND_CELLS);
    BIND_CONSTANT(CAMERA_HEIGHT);
    BIND_CONSTANT(ATLAS_PAGE_SIZE);
    BIND_CONSTANT(ATLAS_PAGE_COUNT);

    ADD_SIGNAL(MethodInfo("sprite_split", PropertyInfo(Variant::OBJECT, "source", PROPERTY_HINT_NODE_TYPE, "RegolithSprite"), PropertyInfo(Variant::OBJECT, "piece", PROPERTY_HINT_NODE_TYPE, "RegolithSprite")));
    ADD_SIGNAL(MethodInfo("sprite_destroyed", PropertyInfo(Variant::OBJECT, "sprite", PROPERTY_HINT_NODE_TYPE, "RegolithSprite")));
    ADD_SIGNAL(MethodInfo("cells_removed", PropertyInfo(Variant::OBJECT, "sprite", PROPERTY_HINT_NODE_TYPE, "RegolithSprite"), PropertyInfo(Variant::INT, "count")));
}
