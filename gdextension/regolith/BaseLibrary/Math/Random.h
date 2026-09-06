#pragma once

#include "glm/vec2.hpp"
#include "glm/vec3.hpp"
#include "glm/vec4.hpp"
using namespace glm;

#include "Coordinate/Transform.h"

#include <cstdint>

void random_seed(int seed);

uint32_t random_get_state();
void random_set_state(uint32_t state);

int random_int();
bool random_bool();
float random_float();
vec2 random_float2();
vec3 random_float3();

bool random_bool_weighted(float odds);

int random_int_centered();
float random_float_centered();
vec2 random_float2_centered();
vec3 random_float3_centered();

int random_int_max(int max);
float random_float_max(float max);
vec2 random_float2_max(vec2 max);
vec3 random_float3_max(vec3 max);
vec2 random_float2_max(float maxX, float maxY);
vec3 random_float3_max(float maxX, float maxY, float maxZ);

int random_int_min_max(int min, int max);
float random_float_min_max(float min, float max);
vec2 random_float2_min_max(vec2 min, vec2 max);
vec3 random_float3_min_max(vec3 min, vec3 max);
vec2 random_float2_min_max(float minX, float minY, float maxX, float maxY);
vec3 random_float3_min_max(float minX, float minY, float minZ, float maxX, float maxY, float maxZ);

int random_int_max_addition(int min, int addition);
float random_float_max_addition(float min, float addition);
vec2 random_float2_max_addition(vec2 min, vec2 addition);
vec3 random_float3_max_addition(vec3 min, vec3 addition);
vec2 random_float2_max_addition(float minX, float minY, float additionX, float additionY);
vec3 random_float3_max_addition(float minX, float minY, float minZ, float additionX, float additionY, float additionZ);

int random_int_max_centered(int extent);
float random_float_max_centered(float extent);
vec2 random_float2_max_centered(vec2 extent);
vec3 random_float3_max_centered(vec3 extent);
vec2 random_float2_max_centered(float extentX, float extentY);
vec3 random_float3_max_centered(float extentX, float extentY, float extentZ);

vec2 random_float2_max_centered(vec2 extent, float angle);

vec2 random_in_transform(const Transform& transform);

vec2 random_float2_normalized(float radius);
vec3 random_float3_normalized(float radius);

vec2 random_float2_normalized_centered(float radius);
vec3 random_float3_normalized_centered(float radius);

vec2 random_float2_normalized_max_centered(float maxRadius);
vec3 random_float3_normalized_max_centered(float maxRadius);

vec2 random_float2_normalized_min_max_centered(float minRadius, float maxRadius);
vec3 random_float3_normalized_min_max_centered(float minRadius, float maxRadius);

vec2 random_outside_box(float extentX, float extentY, float paddingX, float paddingY);

template<typename _enum>
_enum random_enum(_enum count) {
	return static_cast<_enum>(random_int_max(count));
}

template<typename _list_like>
auto random_item(const _list_like& list) {
	return list.at(random_int_max(static_cast<int>(list.size())));
}