#pragma once

#include "Math/Vector.h"

#include <godot_cpp/templates/pair.hpp>
#include <godot_cpp/templates/local_vector.hpp>

class Sprite;
class Transform;

int cut_sprite_line_grid(Sprite& sprite, godot::Vector2 grid_begin, godot::Vector2 grid_end);

int cut_sprite_line(Sprite& sprite, const Transform& transform, godot::Vector2 world_begin, godot::Vector2 world_end);

int cut_sprite_lines(Sprite& sprite, const Transform& transform, const godot::LocalVector<godot::Pair<godot::Vector2, godot::Vector2>>& world_lines);
