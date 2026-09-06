#pragma once

#include "Coordinate/Grid.h"

class GridLineIterator {
public:
    GridLineIterator(vec2 startGridPoint, vec2 dir, float length);

    ivec2 current() const;
    vec2 current_position() const;
    vec2 current_direction() const;
    float current_distance() const;
    float length() const;
    bool has_more() const;
    void next();
    void set_direction(vec2 dir);

private:
    void init(vec2 dir);

private:
    // Things which are stored not as vectors have no relation between their x and y

    float m_ray_step_x;
    float m_ray_step_y;

    float m_ray_length_x;
    float m_ray_length_y;

    ivec2 m_cell;

    vec2 m_start;
    vec2 m_ray_direction;

    int m_cell_step_x;
    int m_cell_step_y;

    float m_ray_current_length;
    float m_ray_final_length;
};