#include "RegolithRopeRender.h"
#include "RegolithSprite.h"
#include "RegolithWorld.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/scene_tree.hpp>

using namespace godot;

// xy pads around the segment, uv.x picks endpoint a or b
static Ref<ArrayMesh> make_segment_quad() {
    PackedVector2Array quad;
    quad.push_back(Vector2(-1, -1));
    quad.push_back(Vector2(1, -1));
    quad.push_back(Vector2(1, 1));
    quad.push_back(Vector2(-1, -1));
    quad.push_back(Vector2(1, 1));
    quad.push_back(Vector2(-1, 1));

    PackedVector2Array ends;
    ends.push_back(Vector2(0, 0));
    ends.push_back(Vector2(1, 0));
    ends.push_back(Vector2(1, 0));
    ends.push_back(Vector2(0, 0));
    ends.push_back(Vector2(1, 0));
    ends.push_back(Vector2(0, 0));

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = quad;
    arrays[Mesh::ARRAY_TEX_UV] = ends;

    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);

    return mesh;
}

RegolithRopeRender::RegolithRopeRender() {
    set_as_top_level(true);
    set_physics_interpolation_mode(Node::PHYSICS_INTERPOLATION_MODE_OFF);
}

void RegolithRopeRender::_ready() {
    m_mesh = make_segment_quad();
}

void RegolithRopeRender::_exit_tree() {
    m_render.free();
}

void RegolithRopeRender::_process(double delta) {
    if (Engine::get_singleton()->is_editor_hint() || !is_visible_in_tree()) {
        return;
    }

    RegolithSprite* sprite = Object::cast_to<RegolithSprite>(get_parent());

    if (!sprite || !sprite->world()) {
        return;
    }

    SceneTree* tree = get_tree();
    bool interpolated = tree && tree->is_physics_interpolation_enabled();
    float fraction = interpolated ? static_cast<float>(Engine::get_singleton()->get_physics_interpolation_fraction()) : 1.f;

    Transform pose = sprite->render_pose(fraction);

    if (m_render.update(get_canvas_item(), m_mesh->get_rid(), pose, sprite->rope_grid(), sprite->ropes().ropes, fraction, sprite->world()->pixels_per_unit())) {
        queue_redraw();
    }
}

void RegolithRopeRender::_draw() {
    if (m_render.multimesh().is_valid()) {
        RenderingServer::get_singleton()->canvas_item_add_multimesh(get_canvas_item(), m_render.multimesh());
    }
}
