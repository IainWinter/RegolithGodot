#pragma once

#include "Math/Vector.h"
#include "Coordinate/Transform.h"

#include <cstdint>

void random_seed(int seed);

uint32_t random_get_state();
void random_set_state(uint32_t state);

int random_int();
bool random_bool();
float random_float();
godot::Vector2 random_float2();
godot::Vector3 random_float3();

bool random_bool_weighted(float odds);

int random_int_centered();
float random_float_centered();
godot::Vector2 random_float2_centered();
godot::Vector3 random_float3_centered();

int random_int_max(int max);
float random_float_max(float max);
godot::Vector2 random_float2_max(godot::Vector2 max);
godot::Vector3 random_float3_max(godot::Vector3 max);
godot::Vector2 random_float2_max(float maxX, float maxY);
godot::Vector3 random_float3_max(float maxX, float maxY, float maxZ);

int random_int_min_max(int min, int max);
float random_float_min_max(float min, float max);
godot::Vector2 random_float2_min_max(godot::Vector2 min, godot::Vector2 max);
godot::Vector3 random_float3_min_max(godot::Vector3 min, godot::Vector3 max);
godot::Vector2 random_float2_min_max(float minX, float minY, float maxX, float maxY);
godot::Vector3 random_float3_min_max(float minX, float minY, float minZ, float maxX, float maxY, float maxZ);

int random_int_max_addition(int min, int addition);
float random_float_max_addition(float min, float addition);
godot::Vector2 random_float2_max_addition(godot::Vector2 min, godot::Vector2 addition);
godot::Vector3 random_float3_max_addition(godot::Vector3 min, godot::Vector3 addition);
godot::Vector2 random_float2_max_addition(float minX, float minY, float additionX, float additionY);
godot::Vector3 random_float3_max_addition(float minX, float minY, float minZ, float additionX, float additionY, float additionZ);

int random_int_max_centered(int extent);
float random_float_max_centered(float extent);
godot::Vector2 random_float2_max_centered(godot::Vector2 extent);
godot::Vector3 random_float3_max_centered(godot::Vector3 extent);
godot::Vector2 random_float2_max_centered(float extentX, float extentY);
godot::Vector3 random_float3_max_centered(float extentX, float extentY, float extentZ);

godot::Vector2 random_float2_max_centered(godot::Vector2 extent, float angle);

godot::Vector2 random_in_transform(const Transform& transform);

godot::Vector2 random_float2_normalized(float radius);
godot::Vector3 random_float3_normalized(float radius);

godot::Vector2 random_float2_normalized_centered(float radius);
godot::Vector3 random_float3_normalized_centered(float radius);

godot::Vector2 random_float2_normalized_max_centered(float maxRadius);
godot::Vector3 random_float3_normalized_max_centered(float maxRadius);

godot::Vector2 random_float2_normalized_min_max_centered(float minRadius, float maxRadius);
godot::Vector3 random_float3_normalized_min_max_centered(float minRadius, float maxRadius);

godot::Vector2 random_outside_box(float extentX, float extentY, float paddingX, float paddingY);

template<typename _enum>
_enum random_enum(_enum count) {
	return static_cast<_enum>(random_int_max(count));
}

template<typename _list_like>
auto random_item(const _list_like& list) {
	return list[random_int_max(static_cast<int>(list.size()))];
}
