#pragma once

#include "Math/Vector.h"

#include <godot_cpp/templates/pair.hpp>
#include <godot_cpp/templates/local_vector.hpp>

float angle(godot::Vector2 v);

godot::Vector2 vector(float angle);

godot::Vector3 vector3(float phi, float theta);

godot::Vector2 right(godot::Vector2 v);

int length_squared(godot::Vector2i v);

float length_squared(godot::Vector2 v);

float cross(godot::Vector2 a, godot::Vector2 b);

godot::Vector2 cross(float a, godot::Vector2 b);

float clamp(float x, float min, float max);

int wrap_value(int value, int range);

float mod_angle(float a);

float lerp_angle(float a, float b, float w);

float lerp(float a, float b, float w);

godot::Vector2 lerp(const godot::Vector2& a, const godot::Vector2& b, float w);

godot::Vector4 lerp(const godot::Vector4& a, const godot::Vector4& b, float w);

float dampen(float x, float damping, float deltaTime);

godot::Vector2 dampen(godot::Vector2 vec, float damping, float deltaTime);

godot::Vector2 rotate_local_point(godot::Vector2 localPoint, float angle);

godot::Vector2 rotate_local_point(godot::Vector2 localPoint, float angleSin, float angleCos);

godot::Vector2 rotate_around_pivot_point(godot::Vector2 point, godot::Vector2 pivot, float angle);

godot::Pair<godot::Vector2, float> rotate_object_with_center_of_mass(godot::Vector2 center_of_mass, godot::Vector2 position, float angle,
                                                    godot::Vector2 linear_velocity, float angular_velocity, float delta_time);

bool inbounds(int index, godot::Vector2i dimensions);

godot::Vector2 safe_normalize(godot::Vector2 vec);

godot::Pair<godot::Vector2, float> safe_normalize_distance(godot::Vector2 vec);

godot::Pair<godot::Vector2, float> safe_normalize_distance(godot::Vector2 vec, float length_sqr);

godot::Vector2 limit_length(godot::Vector2 vec, float length);

float max_element(godot::Vector2 vec);

float min_element(godot::Vector2 vec);

godot::Vector2 velocity_at_local_point(godot::Vector2 velocity, float angularVelocity, godot::Vector2 centerOfMass, godot::Vector2 localPoint);

float penetration_in_circle(godot::Vector2 point, godot::Vector2 center, float radius);

godot::Vector2 turn_vector_towards(godot::Vector2 current, godot::Vector2 target, float strength);

float closest_t_on_segment(godot::Vector2 a, godot::Vector2 b, godot::Vector2 point);

godot::Vector2 closest_point_on_segment(godot::Vector2 a, godot::Vector2 b, godot::Vector2 point);

// closest parameters between segments a0-a1 and b0-b1
void closest_segment_segment(godot::Vector2 a0, godot::Vector2 a1, godot::Vector2 b0, godot::Vector2 b1, float* s, float* t);

godot::Vector2 closest_point_on_polygon(const godot::Vector2* points, int point_count, godot::Vector2 point);

bool is_point_in_polygon(const godot::Vector2* points, int point_count, godot::Vector2 point);

godot::Vector2 polygon_centroid(const godot::Vector2* points, int point_count);

bool is_clockwise(const godot::Vector2& centroid, const godot::Vector2& a, const godot::Vector2& b);

godot::Vector2 lerp_list(const godot::LocalVector<godot::Vector2>& points, float w);

float list_length(const godot::LocalVector<godot::Vector2>& points);

bool is_circle_circle_overlapping(godot::Vector2 center_0, float radius_0, godot::Vector2 center_1, float radius_1);

float infinity();

godot::Vector2 transform_r_from_local_space(godot::Vector2 local_point, godot::Vector2 center_of_mass, godot::Vector2 scale, float angle);

int edge_index_up(int x, int y, int width);

int edge_index_down(int x, int y, int width);

int edge_index_left(int x, int y, int width);

int edge_index_right(int x, int y, int width);

template <typename T> godot::Pair<T, T> max_min(const T& a, const T& b) {
    return a > b ? godot::Pair<T, T>{a, b} : godot::Pair<T, T>{b, a};
}

struct Unpack3 { int x, y, z; };

template <typename T> Unpack3 unpack3(const T& v) {
    return { v.x, v.y, v.z };
}
