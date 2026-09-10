#pragma once

#include "Coordinate/Grid.h"

class GridLineIterator {
public:
    GridLineIterator(godot::Vector2 startGridPoint, godot::Vector2 dir, float length);

    godot::Vector2i current() const;
    godot::Vector2 current_position() const;
    godot::Vector2 current_direction() const;
    float current_distance() const;
    float length() const;
    bool has_more() const;
    void next();
    void set_direction(godot::Vector2 dir);

private:
    void init(godot::Vector2 dir);

private:
    // Things which are stored not as vectors have no relation between their x and y

    float m_ray_step_x;
    float m_ray_step_y;

    float m_ray_length_x;
    float m_ray_length_y;

    godot::Vector2i m_cell;

    godot::Vector2 m_start;
    godot::Vector2 m_ray_direction;

    int m_cell_step_x;
    int m_cell_step_y;

    float m_ray_current_length;
    float m_ray_final_length;
};