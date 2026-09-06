#pragma once

#include "RopeRender.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/core/binder_common.hpp>

// draws the ropes of the RegolithSprite it is a child of with the sprite's
// rope_material, see RopeRender. top level since rope nodes are world positions
class RegolithRopeRender : public godot::Node2D {
    GDCLASS(RegolithRopeRender, godot::Node2D)

public:
    RegolithRopeRender();

    void _ready() override;
    void _process(double delta) override;
    void _draw() override;
    void _exit_tree() override;

protected:
    static void _bind_methods();

private:
    RopeRender m_render;
    godot::Ref<godot::ArrayMesh> m_mesh;
};
