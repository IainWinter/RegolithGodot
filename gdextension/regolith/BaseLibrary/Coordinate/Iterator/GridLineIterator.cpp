#include "GridLineIterator.h"

#include <cmath>

GridLineIterator::GridLineIterator(vec2 startGridPoint, vec2 dir, float length) {
    m_start = startGridPoint;
    m_cell = ivec2(startGridPoint);
    m_ray_current_length = 0.f;
    m_ray_final_length = length;
    init(dir);
}

ivec2 GridLineIterator::current() const {
    return m_cell;
}

vec2 GridLineIterator::current_position() const {
    return m_start + m_ray_direction * m_ray_current_length; 
}

vec2 GridLineIterator::current_direction() const {
    return m_ray_direction;
}

float GridLineIterator::current_distance() const {
    return m_ray_current_length;
}

float GridLineIterator::length() const {
    return m_ray_final_length;
}

bool GridLineIterator::has_more() const {
    return m_ray_final_length >= m_ray_current_length; // allow runs of 0 length, add config for this.
}

void GridLineIterator::next() {
    if (m_ray_length_y > m_ray_length_x) { // walk along axis which has smallest length
        m_cell.x += m_cell_step_x;
        m_ray_current_length = m_ray_length_x;
        m_ray_length_x += m_ray_step_x;
    }

    else {
        m_cell.y += m_cell_step_y;
        m_ray_current_length = m_ray_length_y;
        m_ray_length_y += m_ray_step_y;
    }
}

void GridLineIterator::set_direction(vec2 dir) {
    m_start = current_position();
    m_ray_final_length -= m_ray_current_length;
    m_ray_current_length = 0.f;

    init(dir);
}

void GridLineIterator::init(vec2 dir) {
    m_ray_direction = dir;

    // X axis
    if (dir.x == 0.f) {
        m_ray_step_x = std::numeric_limits<float>::infinity();
        m_cell_step_x = 0;
        m_ray_length_x = std::numeric_limits<float>::infinity();
    } else {
        m_ray_step_x = std::sqrt(1.f + (dir.y / dir.x) * (dir.y / dir.x));
        m_cell_step_x = (dir.x > 0.f) ? 1 : -1;
        m_ray_length_x = (dir.x > 0.f ? float(m_cell.x + 1) - m_start.x : m_start.x - float(m_cell.x)) * m_ray_step_x;
    }

    // Y axis
    if (dir.y == 0.f) {
        m_ray_step_y = std::numeric_limits<float>::infinity();
        m_cell_step_y = 0;
        m_ray_length_y = std::numeric_limits<float>::infinity();
    } else {
        m_ray_step_y = std::sqrt(1.f + (dir.x / dir.y) * (dir.x / dir.y));
        m_cell_step_y = (dir.y > 0.f) ? 1 : -1;
        m_ray_length_y = (dir.y > 0.f ? float(m_cell.y + 1) - m_start.y : m_start.y - float(m_cell.y)) * m_ray_step_y;
    }

    // m_ray_step_x = sqrtf(1 + (m_ray_direction.y / m_ray_direction.x) * (m_ray_direction.y / m_ray_direction.x));
    // m_ray_step_y = sqrtf(1 + (m_ray_direction.x / m_ray_direction.y) * (m_ray_direction.x / m_ray_direction.y));

    // if (m_ray_direction.x > 0) {
    //     m_cell_step_x = 1;
    //     m_ray_length_x = float(m_cell.x + 1) - m_start.x;
    // }

    // else {
    //     m_cell_step_x = -1;
    //     m_ray_length_x = m_start.x - float(m_cell.x);
    // }

    // if (m_ray_direction.y > 0) {
    //     m_cell_step_y = 1;
    //     m_ray_length_y = float(m_cell.y + 1) - m_start.y;
    // }

    // else {
    //     m_cell_step_y = -1;
    //     m_ray_length_y = m_start.y - float(m_cell.y);
    // }

    // // 0 * inf is nan so rays breaks if they are in cardinal direction
    
    // if (!std::isinf(m_ray_step_x)) {
    //     m_ray_length_x *= m_ray_step_x;
    // }
    
    // if (!std::isinf(m_ray_step_y)) {
    //     m_ray_length_y *= m_ray_step_y;
    // }
}