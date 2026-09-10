#include <godot_cpp/templates/pair.hpp>
#include "MathUtil.h"

#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdlib.h>

static constexpr float _pi = godot::Math::PI;
static constexpr float _2pi = godot::Math::TAU;

float angle(godot::Vector2 v) {
    return atan2(v.y, v.x);
}

godot::Vector2 vector(float angle) {
    return godot::Vector2(cos(angle), sin(angle));
}

godot::Vector3 vector3(float phi, float theta) {
    float x = sin(phi) * cos(theta);
    float y = sin(phi) * sin(theta);
    float z = cos(phi);

    return godot::Vector3(x, y, z);
}

godot::Vector2 right(godot::Vector2 v) {
    return godot::Vector2(v.y, -v.x);
}

int length_squared(godot::Vector2i v) {
    return v.x * v.x + v.y * v.y;
}

float length_squared(godot::Vector2 v) {
    return v.x * v.x + v.y * v.y;
}

float cross(godot::Vector2 a, godot::Vector2 b) {
    return a.x * b.y - a.y * b.x;
}

godot::Vector2 cross(float a, godot::Vector2 b) {
    return godot::Vector2(-a * b.y, a * b.x);
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

godot::Vector2 lerp(const godot::Vector2& a, const godot::Vector2& b, float w) {
    return godot::Vector2(lerp(a.x, b.x, w), lerp(a.y, b.y, w));
}

godot::Vector4 lerp(const godot::Vector4& a, const godot::Vector4& b, float w) {
    return godot::Vector4(lerp(a.x, b.x, w), lerp(a.y, b.y, w), lerp(a.z, b.z, w), lerp(a.w, b.w, w));
}

float dampen(float x, float damping, float deltaTime) {
    return x * clamp(1.f - damping * deltaTime, 0.f, 1.f);
}

godot::Vector2 dampen(godot::Vector2 vec, float damping, float deltaTime) {
    return godot::Vector2(dampen(vec.x, damping, deltaTime), dampen(vec.y, damping, deltaTime));
}

godot::Vector2 rotate_local_point(godot::Vector2 localPoint, float angle) {
    float s = sinf(angle);
    float c = cosf(angle);
    return rotate_local_point(localPoint, s, c);
}

godot::Vector2 rotate_local_point(godot::Vector2 localPoint, float angleSin, float angleCos) {
    return godot::Vector2(localPoint.x * angleCos - localPoint.y * angleSin, localPoint.x * angleSin + localPoint.y * angleCos);
}

godot::Vector2 rotate_around_pivot_point(godot::Vector2 point, godot::Vector2 pivot, float angle) {
    godot::Vector2 local = point - pivot;
    return rotate_local_point(local, angle) + pivot;
}

godot::Pair<godot::Vector2, float> rotate_object_with_center_of_mass(godot::Vector2 center_of_mass, godot::Vector2 position, float angle,
                                                    godot::Vector2 linear_velocity, float angular_velocity, float delta_time) {
    godot::Vector2 delta_position = linear_velocity * delta_time;
    float delta_angle = angular_velocity * delta_time;

    position += delta_position;
    angle += delta_angle;

    godot::Vector2 correction = rotate_local_point(position - center_of_mass, delta_angle);
    position = center_of_mass + correction;

    return {position, angle};
}

bool inbounds(int index, godot::Vector2i dimensions) {
    return index >= 0 && index < dimensions.x * dimensions.y;
}

godot::Vector2 safe_normalize(godot::Vector2 vec) {
    return safe_normalize_distance(vec).first;
}

godot::Pair<godot::Vector2, float> safe_normalize_distance(godot::Vector2 vec) {
    float len = vec.length();
    if (len == 0.0) {
        return {vec, len};
    }

    return {vec / len, len};
}

godot::Pair<godot::Vector2, float> safe_normalize_distance(godot::Vector2 vec, float length_sqr) {
    if (length_sqr == 0.f) {
        return {vec, 0.f};
    }

    float len = sqrt(length_sqr);

    return {vec / len, len};
}

godot::Vector2 limit_length(godot::Vector2 vec, float length) {
    float l = vec.length();
    if (l > length) {
        return vec / l * length;
    }

    return vec;
}

godot::Vector2i pixel_position_from_index(int index, int width) {
    int x = index % width;
    int y = index / width;

    return godot::Vector2i(x, y);
}

float max_element(godot::Vector2 vec) {
    return vec.x > vec.y ? vec.x : vec.y;
}

float min_element(godot::Vector2 vec) {
    return vec.x < vec.y ? vec.x : vec.y;
}

godot::Vector2 velocity_at_local_point(godot::Vector2 velocity, float angularVelocity, godot::Vector2 centerOfMass, godot::Vector2 localPoint) {
    godot::Vector2 r = localPoint - centerOfMass;
    godot::Vector2 angularLinearComponent = godot::Vector2(-r.y, r.x) * angularVelocity;
    return velocity + angularLinearComponent;
}

float penetration_in_circle(godot::Vector2 point, godot::Vector2 center, float radius) {
    godot::Vector2 d = point - center;
    float distanceSqr = d.dot(d);
    float radiusSqr = radius * radius;

    if (distanceSqr > radiusSqr) {
        return 0.f;
    }

    return radiusSqr - distanceSqr; // dont really need to sqr
}

godot::Vector2 turn_vector_towards(godot::Vector2 current, godot::Vector2 target, float strength) {
    godot::Vector2 n_curent = safe_normalize(current);
    godot::Vector2 n_target = safe_normalize(target);
    godot::Vector2 delta = (n_target - n_curent) * strength;

    return safe_normalize(current + delta) * current.length();
}

float closest_t_on_segment(godot::Vector2 a, godot::Vector2 b, godot::Vector2 point) {
    godot::Vector2 ab = b - a;
    float len2 = ab.dot(ab);

    if (len2 < 1e-12f) {
        return 0.f;
    }

    return clamp((point - a).dot(ab) / len2, 0.f, 1.f);
}

godot::Vector2 closest_point_on_segment(godot::Vector2 a, godot::Vector2 b, godot::Vector2 point) {
    return a + closest_t_on_segment(a, b, point) * (b - a);
}

void closest_segment_segment(godot::Vector2 a0, godot::Vector2 a1, godot::Vector2 b0, godot::Vector2 b1, float* s, float* t) {
    godot::Vector2 d1 = a1 - a0;
    godot::Vector2 d2 = b1 - b0;
    godot::Vector2 r = a0 - b0;

    float len1 = d1.dot(d1);
    float len2 = d2.dot(d2);
    float f = d2.dot(r);

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

    float c = d1.dot(r);

    if (len2 < 1e-12f) {
        *t = 0.f;
        *s = clamp(-c / len1, 0.f, 1.f);

        return;
    }

    float b = d1.dot(d2);
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

godot::Vector2 closest_point_on_polygon(const godot::Vector2* points, int point_count, godot::Vector2 point) {
    if (point_count == 0) {
        return point;
    }

    godot::Vector2 closest;
    float min_dist = std::numeric_limits<float>::max();

    for (int i = 0; i < point_count; i++) {
        const godot::Vector2& a = points[i];
        const godot::Vector2& b = points[(i + 1) % point_count];

        godot::Vector2 candidate = closest_point_on_segment(a, b, point);
        godot::Vector2 d = candidate - point;
        float dist = d.dot(d);

        if (dist < min_dist) {
            min_dist = dist;
            closest = candidate;
        }
    }

    return closest;
}

bool is_point_in_polygon(const godot::Vector2* points, int point_count, godot::Vector2 point) {
    bool inside = false;

    for (int i = 0, j = point_count - 1; i < point_count; j = i++) {
        godot::Vector2 pi = points[i];
        godot::Vector2 pj = points[j];

        bool intersect = ((pi.y > point.y) != (pj.y > point.y))
                      && (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x);

        if (intersect)
            inside = !inside;
    }

    return inside;
}

godot::Vector2 polygon_centroid(const godot::Vector2* points, int point_count) {
    godot::Vector2 centeroid = godot::Vector2(0.f, 0.f);
    for (int i = 0; i < point_count; i++) {
        centeroid += points[i];
    }

    return centeroid / static_cast<float>(point_count);
}

bool is_clockwise(const godot::Vector2& centroid, const godot::Vector2& a, const godot::Vector2& b) {
    return cross(a - centroid, b - centroid) < 0;
}

godot::Vector2 lerp_list(const godot::LocalVector<godot::Vector2>& points, float w) {
    if (points.is_empty()) {
        return godot::Vector2(0.0f, 0.0f);
    }

    if (points.size() == 1) {
        return points[0];
    }

    w = std::clamp(w, 0.0f, 1.0f);

    float scaled = w * (points.size() - 1);
    size_t i = static_cast<size_t>(scaled);
    float t = scaled - i;

    if (i >= points.size() - 1) {
        return points[points.size() - 1];
    }

    return (1.0f - t) * points[i] + t * points[i + 1];
}

float list_length(const godot::LocalVector<godot::Vector2>& points) {
    float len = 0.f;

    for (size_t i = 1; i < points.size(); i++) {
        len += points[i - 1].distance_to(points[i]);
    }

    return len;
}

bool is_circle_circle_overlapping(godot::Vector2 center_0, float radius_0, godot::Vector2 center_1, float radius_1) {
    godot::Vector2 vec_01 = center_1 - center_0;
    float radius_01 = radius_0 + radius_1;
    float dist_sqr = vec_01.dot(vec_01);
    return dist_sqr < radius_01 * radius_01;
}

float infinity() {
    return std::numeric_limits<float>::infinity();
}

godot::Vector2 transform_r_from_local_space(godot::Vector2 local_point, godot::Vector2 center_of_mass, godot::Vector2 scale, float angle) {
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
