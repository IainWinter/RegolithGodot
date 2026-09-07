#pragma once

#include "Coordinate/Grid.h"
#include "Coordinate/Transform.h"
#include "DestructibleSprite/SpriteRope.h"

#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/rid.hpp>

#include <vector>

// mirror of the engine's PixelLinePass. ropes rasterize one cell thick onto
// their sprite's grid: one multimesh instance per segment carrying the
// endpoints in grid space, the instance transform places grid cells in the
// world so the shader can snap to whole cells. the caller owns the canvas
// item the multimesh draws from, see RegolithRopeRender
class RopeRender {
public:
    ~RopeRender();

    bool update(godot::RID item, godot::RID mesh, const Transform& pose, const Grid& grid, const std::vector<SpriteRope>& ropes, float fraction, float pixels_per_unit);

    godot::RID multimesh() const;

    int instance_count() const;

    void hide();

    void free();

private:
    godot::RID m_multimesh;
    godot::PackedFloat32Array m_buffer;
    int m_capacity = 0;
    int m_written = 0;
};
