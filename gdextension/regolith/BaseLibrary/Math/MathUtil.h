#pragma once

#include "glm/vec2.hpp"
#include "glm/vec3.hpp"
#include "glm/vec4.hpp"
using namespace glm;

#include <algorithm>
#include <tuple>
#include <utility>
#include <vector>

float angle(vec2 v);

vec2 vector(float angle);

vec3 vector3(float phi, float theta);

vec2 right(vec2 v);

int length_squared(ivec2 v);

float length_squared(vec2 v);

float cross(vec2 a, vec2 b);

vec2 cross(float a, vec2 b);

float clamp(float x, float min, float max);

int wrap_value(int value, int range);

float mod_angle(float a);

float lerp_angle(float a, float b, float w);

float lerp(float a, float b, float w);

vec2 lerp(const vec2& a, const vec2& b, float w);

vec4 lerp(const vec4& a, const vec4& b, float w);

float dampen(float x, float damping, float deltaTime);

vec2 dampen(vec2 vec, float damping, float deltaTime);

vec2 rotate_local_point(vec2 localPoint, float angle);

vec2 rotate_local_point(vec2 localPoint, float angleSin, float angleCos);

vec2 rotate_around_pivot_point(vec2 point, vec2 pivot, float angle);

std::pair<vec2, float> rotate_object_with_center_of_mass(vec2 center_of_mass, vec2 position, float angle,
                                                    vec2 linear_velocity, float angular_velocity, float delta_time);

bool inbounds(int index, ivec2 dimensions);

vec2 safe_normalize(vec2 vec);

std::pair<vec2, float> safe_normalize_distance(vec2 vec);

std::pair<vec2, float> safe_normalize_distance(vec2 vec, float length_sqr);

vec2 limit_length(vec2 vec, float length);

float max_element(vec2 vec);

float min_element(vec2 vec);

vec2 velocity_at_local_point(vec2 velocity, float angularVelocity, vec2 centerOfMass, vec2 localPoint);

float penetration_in_circle(vec2 point, vec2 center, float radius);

vec2 turn_vector_towards(vec2 current, vec2 target, float strength);

float closest_t_on_segment(vec2 a, vec2 b, vec2 point);

vec2 closest_point_on_segment(vec2 a, vec2 b, vec2 point);

// closest parameters between segments a0-a1 and b0-b1
void closest_segment_segment(vec2 a0, vec2 a1, vec2 b0, vec2 b1, float* s, float* t);

vec2 closest_point_on_polygon(const vec2* points, int point_count, vec2 point);

bool is_point_in_polygon(const vec2* points, int point_count, vec2 point);

vec2 polygon_centroid(const vec2* points, int point_count);

bool is_clockwise(const vec2& centroid, const vec2& a, const vec2& b);

vec2 lerp_list(const std::vector<vec2>& points, float w);

float list_length(const std::vector<vec2>& points);

bool is_circle_circle_overlapping(vec2 center_0, float radius_0, vec2 center_1, float radius_1);

float infinity();

vec2 transform_r_from_local_space(vec2 local_point, vec2 center_of_mass, vec2 scale, float angle);

int edge_index_up(int x, int y, int width);

int edge_index_down(int x, int y, int width);

int edge_index_left(int x, int y, int width);

int edge_index_right(int x, int y, int width);

template <typename T> std::pair<T, T> max_min(const T& a, const T& b) {
    return a > b ? std::make_pair(a, b) : std::make_pair(b, a);
}

template <typename T> std::tuple<const int&, const int&, const int&> unpack3(const T& v) {
    return std::tie(v.x, v.y, v.z);
}

template <typename T> std::tuple<const int&, const int&> unpack2(const T& v) {
    return std::tie(v.x, v.y);
}