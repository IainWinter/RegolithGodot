#include "RopeRender.h"

#include <godot_cpp/classes/rendering_server.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

RopeRender::~RopeRender() {
    free();
}

void RopeRender::free() {
    RenderingServer* rs = RenderingServer::get_singleton();

    if (rs && m_multimesh.is_valid()) {
        rs->free_rid(m_multimesh);
    }

    m_multimesh = RID();
    m_capacity = 0;
    m_written = 0;
    m_buffer.resize(0);
}

RID RopeRender::multimesh() const {
    return m_multimesh;
}

int RopeRender::instance_count() const {
    return m_written;
}

void RopeRender::hide() {
    if (m_multimesh.is_valid()) {
        RenderingServer::get_singleton()->multimesh_set_visible_instances(m_multimesh, 0);
    }

    m_written = 0;
}

bool RopeRender::update(RID item, RID mesh, const Transform& pose, const Grid& grid, const std::vector<SpriteRope>& ropes, float fraction, float pixels_per_unit) {
    RenderingServer* rs = RenderingServer::get_singleton();

    int segments = 0;

    if (grid.cells.x > 0) {
        for (const SpriteRope& rope : ropes) {
            size_t count = rope.nodes.size() >= 2 ? rope.nodes.size() : rope.rest_local.size();
            segments += count >= 2 ? static_cast<int>(count) - 1 : 0;
        }
    }

    if (segments == 0) {
        hide();
        return false;
    }

    bool grown = false;

    if (segments > m_capacity) {
        if (!m_multimesh.is_valid()) {
            m_multimesh = rs->multimesh_create();
        }

        m_capacity = std::max(segments, m_capacity * 2);

        rs->multimesh_allocate_data(m_multimesh, m_capacity, RenderingServer::MULTIMESH_TRANSFORM_2D, true, true);
        rs->multimesh_set_mesh(m_multimesh, mesh);

        m_buffer.resize(m_capacity * 16);
        grown = true;
    }

    vec2 origin = pose.to_world_point(grid.to_local_point(vec2(0.f))) * pixels_per_unit;
    vec2 axis_x = pose.to_world_point(grid.to_local_point(vec2(1.f, 0.f))) * pixels_per_unit - origin;
    vec2 axis_y = pose.to_world_point(grid.to_local_point(vec2(0.f, 1.f))) * pixels_per_unit - origin;

    float neg_sin = sinf(-pose.angle);
    float neg_cos = cosf(-pose.angle);

    float* out = m_buffer.ptrw();
    int written = 0;

    vec2 bounds_min = vec2(INFINITY);
    vec2 bounds_max = vec2(-INFINITY);

    std::vector<vec2> grid_points;

    for (const SpriteRope& rope : ropes) {
        grid_points.clear();

        if (rope.nodes.size() >= 2) {
            for (const SpriteRopeNode& node : rope.nodes) {
                vec2 world = mix(node.last_position, node.position, fraction);
                grid_points.push_back(grid.to_grid_point(pose.to_local_point(world, neg_sin, neg_cos)));
            }
        }

        else if (rope.rest_local.size() >= 2) {
            for (const vec2& rest : rope.rest_local) {
                grid_points.push_back(grid.to_grid_point(rest));
            }
        }

        else {
            continue;
        }

        float r = rope.color.r / 255.f;
        float g = rope.color.g / 255.f;
        float b = rope.color.b / 255.f;
        float a = rope.color.a / 255.f;

        for (const vec2& point : grid_points) {
            vec2 world = origin + axis_x * point.x + axis_y * point.y;
            bounds_min = min(bounds_min, world);
            bounds_max = max(bounds_max, world);
        }

        for (size_t i = 0; i + 1 < grid_points.size() && written < m_capacity; i++) {
            float* instance = out + written * 16;

            instance[0] = axis_x.x;
            instance[1] = axis_y.x;
            instance[2] = 0.f;
            instance[3] = origin.x;
            instance[4] = axis_x.y;
            instance[5] = axis_y.y;
            instance[6] = 0.f;
            instance[7] = origin.y;

            instance[8] = r;
            instance[9] = g;
            instance[10] = b;
            instance[11] = a;

            instance[12] = grid_points[i].x;
            instance[13] = grid_points[i].y;
            instance[14] = grid_points[i + 1].x;
            instance[15] = grid_points[i + 1].y;

            written++;
        }
    }

    float pad = 2.f * (length(axis_x) + length(axis_y));
    bounds_min -= vec2(pad);
    bounds_max += vec2(pad);

    rs->multimesh_set_buffer(m_multimesh, m_buffer);
    rs->multimesh_set_visible_instances(m_multimesh, written);
    m_written = written;
    rs->canvas_item_set_custom_rect(item, true, Rect2(bounds_min.x, bounds_min.y, bounds_max.x - bounds_min.x, bounds_max.y - bounds_min.y));

    return grown;
}
