#include "MathUtil.h"
#include "glm/geometric.hpp"
#include "glm/gtc/constants.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdlib.h>

static constexpr float _pi = glm::pi<float>();
static constexpr float _2pi = glm::two_pi<float>();

float angle(vec2 v) {
    return atan2(v.y, v.x);
}

vec2 vector(float angle) {
    return vec2(cos(angle), sin(angle));
}

vec3 vector3(float phi, float theta) {
    float x = sin(phi) * cos(theta);
    float y = sin(phi) * sin(theta);
    float z = cos(phi);

    return vec3(x, y, z);
}

vec2 right(vec2 v) {
    return vec2(v.y, -v.x);
}

int length_squared(ivec2 v) {
    return v.x * v.x + v.y * v.y;
}

float length_squared(vec2 v) {
    return v.x * v.x + v.y * v.y;
}

float cross(vec2 a, vec2 b) {
    return a.x * b.y - a.y * b.x;
}

vec2 cross(float a, vec2 b) {
    return vec2(-a * b.y, a * b.x);
}

float clamp(float x, float min, float max) {
    if (x < min)
        return min;
    if (x > max)
        return max;
    return x;
}

int wrap_value(int value, int range) {
    int result = value % range;
    return result < 0 ? result + range : result;
}

float mod_angle(float a) {
    return fmodf(a + _pi, _2pi) - _pi;
}

float lerp_angle(float a, float b, float w) {
    a = mod_angle(a);
    b = mod_angle(b);

    float delta = b - a;

    if (delta > _pi) {
        delta -= _2pi;
    }

    else if (delta < -_pi) {
        delta += _2pi;
    }

    return mod_angle(a + w * delta);
}

float lerp(float a, float b, float w) {
    return a + (b - a) * clamp(w, 0.f, 1.f);
}

vec2 lerp(const vec2& a, const vec2& b, float w) {
    return vec2(lerp(a.x, b.x, w), lerp(a.y, b.y, w));
}

vec4 lerp(const vec4& a, const vec4& b, float w) {
    return vec4(lerp(a.x, b.x, w), lerp(a.y, b.y, w), lerp(a.z, b.z, w), lerp(a.w, b.w, w));
}

float dampen(float x, float damping, float deltaTime) {
    return x * clamp(1.f - damping * deltaTime, 0.f, 1.f);
}

vec2 dampen(vec2 vec, float damping, float deltaTime) {
    return vec2(dampen(vec.x, damping, deltaTime), dampen(vec.y, damping, deltaTime));
}

vec2 rotate_local_point(vec2 localPoint, float angle) {
    float s = sinf(angle);
    float c = cosf(angle);
    return rotate_local_point(localPoint, s, c);
}

vec2 rotate_local_point(vec2 localPoint, float angleSin, float angleCos) {
    return vec2(localPoint.x * angleCos - localPoint.y * angleSin, localPoint.x * angleSin + localPoint.y * angleCos);
}

vec2 rotate_around_pivot_point(vec2 point, vec2 pivot, float angle) {
    vec2 local = point - pivot;
    return rotate_local_point(local, angle) + pivot;
}

std::pair<vec2, float> rotate_object_with_center_of_mass(vec2 center_of_mass, vec2 position, float angle,
                                                    vec2 linear_velocity, float angular_velocity, float delta_time) {
    vec2 delta_position = linear_velocity * delta_time;
    float delta_angle = angular_velocity * delta_time;

    position += delta_position;
    angle += delta_angle;

    vec2 correction = rotate_local_point(position - center_of_mass, delta_angle);
    position = center_of_mass + correction;

    return {position, angle};
}

bool inbounds(int index, ivec2 dimensions) {
    return index >= 0 && index < dimensions.x * dimensions.y;
}

vec2 safe_normalize(vec2 vec) {
    return safe_normalize_distance(vec).first;
}

std::pair<vec2, float> safe_normalize_distance(vec2 vec) {
    float len = length(vec);
    if (len == 0.0) {
        return {vec, len};
    }

    return {vec / len, len};
}

std::pair<vec2, float> safe_normalize_distance(vec2 vec, float length_sqr) {
    if (length_sqr == 0.f) {
        return {vec, 0.f};
    }

    float len = sqrt(length_sqr);

    return {vec / len, len};
}

vec2 limit_length(vec2 vec, float length) {
    float l = ::length(vec);
    if (l > length) {
        return vec / l * length;
    }

    return vec;
}

ivec2 pixel_position_from_index(int index, int width) {
    int x = index % width;
    int y = index / width;

    return ivec2(x, y);
}

float max_element(vec2 vec) {
    return vec.x > vec.y ? vec.x : vec.y;
}

float min_element(vec2 vec) {
    return vec.x < vec.y ? vec.x : vec.y;
}

vec2 velocity_at_local_point(vec2 velocity, float angularVelocity, vec2 centerOfMass, vec2 localPoint) {
    vec2 r = localPoint - centerOfMass;
    vec2 angularLinearComponent = vec2(-r.y, r.x) * angularVelocity;
    return velocity + angularLinearComponent;
}

float penetration_in_circle(vec2 point, vec2 center, float radius) {
    vec2 d = point - center;
    float distanceSqr = dot(d, d);
    float radiusSqr = radius * radius;

    if (distanceSqr > radiusSqr) {
        return 0.f;
    }

    return radiusSqr - distanceSqr; // dont really need to sqr
}

vec2 turn_vector_towards(vec2 current, vec2 target, float strength) {
    vec2 n_curent = safe_normalize(current);
    vec2 n_target = safe_normalize(target);
    vec2 delta = (n_target - n_curent) * strength;

    return safe_normalize(current + delta) * length(current);
}

float closest_t_on_segment(vec2 a, vec2 b, vec2 point) {
    vec2 ab = b - a;
    float len2 = dot(ab, ab);

    if (len2 < 1e-12f) {
        return 0.f;
    }

    return clamp(dot(point - a, ab) / len2, 0.f, 1.f);
}

vec2 closest_point_on_segment(vec2 a, vec2 b, vec2 point) {
    return a + closest_t_on_segment(a, b, point) * (b - a);
}

void closest_segment_segment(vec2 a0, vec2 a1, vec2 b0, vec2 b1, float* s, float* t) {
    vec2 d1 = a1 - a0;
    vec2 d2 = b1 - b0;
    vec2 r = a0 - b0;

    float len1 = dot(d1, d1);
    float len2 = dot(d2, d2);
    float f = dot(d2, r);

    if (len1 < 1e-12f && len2 < 1e-12f) {
        *s = 0.f;
        *t = 0.f;

        return;
    }

    if (len1 < 1e-12f) {
        *s = 0.f;
        *t = clamp(f / len2, 0.f, 1.f);

        return;
    }

    float c = dot(d1, r);

    if (len2 < 1e-12f) {
        *t = 0.f;
        *s = clamp(-c / len1, 0.f, 1.f);

        return;
    }

    float b = dot(d1, d2);
    float denom = len1 * len2 - b * b;

    float s_out = denom > 1e-12f ? clamp((b * f - c * len2) / denom, 0.f, 1.f) : 0.f;
    float t_out = (b * s_out + f) / len2;

    if (t_out < 0.f) {
        t_out = 0.f;
        s_out = clamp(-c / len1, 0.f, 1.f);
    }

    else if (t_out > 1.f) {
        t_out = 1.f;
        s_out = clamp((b - c) / len1, 0.f, 1.f);
    }

    *s = s_out;
    *t = t_out;
}

vec2 closest_point_on_polygon(const vec2* points, int point_count, vec2 point) {
    if (point_count == 0) {
        return point;
    }

    vec2 closest;
    float min_dist = std::numeric_limits<float>::max();

    for (int i = 0; i < point_count; i++) {
        const vec2& a = points[i];
        const vec2& b = points[(i + 1) % point_count];

        vec2 candidate = closest_point_on_segment(a, b, point);
        float dist = dot(candidate - point, candidate - point);

        if (dist < min_dist) {
            min_dist = dist;
            closest = candidate;
        }
    }

    return closest;
}

bool is_point_in_polygon(const vec2* points, int point_count, vec2 point) {
    bool inside = false;

    for (int i = 0, j = point_count - 1; i < point_count; j = i++) {
        vec2 pi = points[i];
        vec2 pj = points[j];

        bool intersect = ((pi.y > point.y) != (pj.y > point.y))
                      && (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x);

        if (intersect)
            inside = !inside;
    }

    return inside;
}

vec2 polygon_centroid(const vec2* points, int point_count) {
    vec2 centeroid = vec2(0.f);
    for (int i = 0; i < point_count; i++) {
        centeroid += points[i];
    }

    return centeroid / static_cast<float>(point_count);
}

bool is_clockwise(const vec2& centroid, const vec2& a, const vec2& b) {
    return cross(a - centroid, b - centroid) < 0;
}

vec2 lerp_list(const std::vector<vec2>& points, float w) {
    if (points.empty()) {
        return vec2(0.0f);
    }

    if (points.size() == 1) {
        return points[0];
    }

    w = std::clamp(w, 0.0f, 1.0f);

    float scaled = w * (points.size() - 1);
    size_t i = static_cast<size_t>(scaled);
    float t = scaled - i;

    if (i >= points.size() - 1) {
        return points.back();
    }

    return (1.0f - t) * points[i] + t * points[i + 1];
}

float list_length(const std::vector<vec2>& points) {
    float len = 0.f;

    for (size_t i = 1; i < points.size(); i++) {
        len += distance(points.at(i - 1), points.at(i));
    }

    return len;
}

bool is_circle_circle_overlapping(vec2 center_0, float radius_0, vec2 center_1, float radius_1) {
    vec2 vec_01 = center_1 - center_0;
    float radius_01 = radius_0 + radius_1;
    float dist_sqr = dot(vec_01, vec_01);
    return dist_sqr < radius_01 * radius_01;
}

float infinity() {
    return std::numeric_limits<float>::infinity();
}

vec2 transform_r_from_local_space(vec2 local_point, vec2 center_of_mass, vec2 scale, float angle) {
    return rotate_local_point((local_point - center_of_mass) * scale, angle);
}

int edge_index_up(int x, int y, int width) {
    return x;
}

int edge_index_down(int x, int y, int width) {
    return x + (width - 1) * width;
}

int edge_index_left(int x, int y, int width) {
    return (width - 1) + y * width;
}

int edge_index_right(int x, int y, int width) {
    return y * width;
}