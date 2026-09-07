#include "Random.h"
#include "MathUtil.h"

#include "glm/gtc/constants.hpp"
#include "glm/geometric.hpp"

#include <limits.h>
#include <cstdint>

static uint32_t g_random_state = 0x12345678u;

static uint32_t _rand_u32() {
    uint32_t x = g_random_state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    g_random_state = x;
    return x;
}

int _rand() {
    return static_cast<int>(_rand_u32() & 0x7FFFFFFFu);
}

void random_seed(int seed) {
    uint32_t s = static_cast<uint32_t>(seed);
    if (s == 0) s = 0x12345678u;
    g_random_state = s;
}

uint32_t random_get_state() {
    return g_random_state;
}

void random_set_state(uint32_t state) {
    if (state == 0) state = 0x12345678u;
    g_random_state = state;
}

int random_int() {
    return _rand();
}

bool random_bool() {
    return _rand() % 2 == 0;
}

float random_float() {
    return _rand() / (float)INT_MAX;
}

vec2 random_float2() {
    return vec2(random_float(), random_float());
}

vec3 random_float3() {
    return vec3(random_float(), random_float(), random_float());
}

bool random_bool_weighted(float odds) {
    return random_float() < odds;
}

int random_int_centered() {
    return random_int_max_centered(1);
}

float random_float_centered() {
    return random_float_max_centered(1.f);
}

vec2 random_float2_centered() {
    return random_float2_max_centered(1.f, 1.f);
}

vec3 random_float3_centered() {
    return random_float3_max_centered(1.f, 1.f, 1.f);
}

int random_int_max(int max) {
    if (max == 0)
        return 0;

    return _rand() % max;
}

float random_float_max(float max) {
    return random_float() * max;
}

vec2 random_float2_max(vec2 max) {
    return random_float2() * max;
}

vec3 random_float3_max(vec3 max) {
    return random_float3() * max;
}

vec2 random_float2_max(float maxX, float maxY) {
    return random_float2_max(vec2(maxX, maxY));
}

vec3 random_float3_max(float maxX, float maxY, float maxZ) {
    return random_float3_max(vec3(maxX, maxY, maxZ));
}

int random_int_min_max(int min, int max) {
    return random_int_max_addition(min, max - min);
}

float random_float_min_max(float min, float max) {
    return random_float_max_addition(min, max - min);
}

vec2 random_float2_min_max(vec2 min, vec2 max) {
    return random_float2_max_addition(min, max - min);
}

vec3 random_float3_min_max(vec3 min, vec3 max) {
    return random_float3_max_addition(min, max - min);
}

vec2 random_float2_min_max(float minX, float minY, float maxX, float maxY) {
    return random_float2_min_max(vec2(minX, minY), vec2(maxX, maxY));
}

vec3 random_float3_min_max(float minX, float minY, float minZ, float maxX, float maxY, float maxZ) {
    return random_float3_min_max(vec3(minX, minY, minZ), vec3(maxX, maxY, maxZ));
}

int random_int_max_addition(int min, int addition) {
    return min + random_int_max(addition);
}

float random_float_max_addition(float min, float addition) {
    return min + random_float_max(addition);
}

vec2 random_float2_max_addition(vec2 min, vec2 addition) {
    return min + random_float2_max(addition);
}

vec3 random_float3_max_addition(vec3 min, vec3 addition) {
    return min + random_float3_max(addition);
}

vec2 random_float2_max_addition(float minX, float minY, float additionX, float additionY) {
    return random_float2_max_addition(vec2(minX, minY), vec2(additionX, additionY));
}

vec3 random_float3_max_addition(float minX, float minY, float minZ, float additionX, float additionY, float additionZ) {
    return random_float3_max_addition(vec3(minX, minY, minZ), vec3(additionX, additionY, additionZ));
}

int random_int_max_centered(int extent) {
    return -extent + random_int_max(extent * 2);
}

float random_float_max_centered(float extent) {
    return -extent + random_float_max(extent * 2.f);
}

vec2 random_float2_max_centered(vec2 extent) {
    return -extent + random_float2_max(extent * 2.f);
}

vec3 random_float3_max_centered(vec3 extent) {
    return -extent + random_float3_max(extent * 2.f);
}

vec2 random_float2_max_centered(float extentX, float extentY) {
    return random_float2_max_centered(vec2(extentX, extentY));
}

vec3 random_float3_max_centered(float extentX, float extentY, float extentZ) {
    return random_float3_max_centered(vec3(extentX, extentY, extentZ));
}

vec2 random_float2_max_centered(vec2 extent, float angle) {
    return rotate_local_point(random_float2_max_centered(extent), angle);
}

vec2 random_in_transform(const Transform& transform) {
    return transform.position + random_float2_max_centered(transform.scale, transform.angle);
}

vec2 random_float2_normalized(float radius) {
    return vector(random_float_min_max(0, half_pi<float>())) * radius;
}

vec3 random_float3_normalized(float radius) {
    // non uniform
    return normalize(random_float3()) * radius;
}

vec2 random_float2_normalized_centered(float radius) {
    return vector(random_float_max(two_pi<float>())) * radius;
}

vec3 random_float3_normalized_centered(float radius) {
    // non uniform
    return normalize(random_float3_centered()) * radius;
}

vec2 random_float2_normalized_max_centered(float maxRadius) {
    return vector(random_float_max(two_pi<float>())) * random_float_max(maxRadius);
}

vec3 random_float3_normalized_max_centered(float maxRadius) {
    float theta = random_float_max(two_pi<float>());
    float phi = acos(random_float_max_centered(1.f));

    return vector3(phi, theta) * random_float_max(maxRadius);
}

vec2 random_float2_normalized_min_max_centered(float minRadius, float maxRadius) {
    return vector(random_float_max(two_pi<float>())) * random_float_min_max(minRadius, maxRadius);
}

vec3 random_float3_normalized_min_max_centered(float minRadius, float maxRadius) {
    float theta = random_float_max(two_pi<float>());
    float phi = acos(random_float_max_centered(1.f));

    return vector3(phi, theta) * random_float_min_max(minRadius, maxRadius);
}

vec2 random_outside_box(float extentX, float extentY, float paddingX, float paddingY) {
	// this seems complex because if you treat the corners as a part of one of the
	// side sections, the probability is off
	
	vec2 insidePadding;

	// push to edge based on sign

	float areaHorizontal = 2 * extentX  * paddingY;
	float areaVertical = 2 * extentY * paddingX;
	float areaCorner = paddingX * paddingY;

	float pickArea = random_float_max(areaHorizontal + areaVertical + areaCorner);

	if (pickArea < areaHorizontal) {
		insidePadding = random_float2_max_centered(extentX, paddingY);

		bool top = insidePadding.y > 0;

		if (top) insidePadding.y += extentY;
		else     insidePadding.y -= extentY;
	}

	else if (pickArea < (areaHorizontal + areaVertical)) {
		insidePadding = random_float2_max_centered(paddingX, extentY);

		bool right = insidePadding.x > 0;

		if (right) insidePadding.x += extentX;
		else       insidePadding.x -= extentX;
	}

	else {
		insidePadding = random_float2_max_centered(paddingX, paddingY);

		bool right = insidePadding.x > 0;
		bool top = insidePadding.y > 0;

		if (right) insidePadding.x += extentX;
		else       insidePadding.x -= extentX;

		if (top) insidePadding.y += extentY;
		else     insidePadding.y -= extentY;
	}

	return insidePadding;
}
