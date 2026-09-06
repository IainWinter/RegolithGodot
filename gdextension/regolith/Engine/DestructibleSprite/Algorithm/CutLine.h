#pragma once

#include "Math/Vector.h"

#include <utility>
#include <vector>

class Sprite;
class Transform;

int cut_sprite_line_grid(Sprite& sprite, vec2 grid_begin, vec2 grid_end);

int cut_sprite_line(Sprite& sprite, const Transform& transform, vec2 world_begin, vec2 world_end);

int cut_sprite_lines(Sprite& sprite, const Transform& transform, const std::vector<std::pair<vec2, vec2>>& world_lines);
