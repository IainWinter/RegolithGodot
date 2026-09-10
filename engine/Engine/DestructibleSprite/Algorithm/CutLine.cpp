#include <godot_cpp/templates/pair.hpp>
#include "CutLine.h"

#include "DestructibleSprite/Sprite.h"

#include "Coordinate/Iterator/GridLineIterator.h"
#include "Coordinate/Transform.h"
#include "Math/MathUtil.h"

int cut_sprite_line_grid(Sprite& sprite, godot::Vector2 grid_begin, godot::Vector2 grid_end) {
    auto [dir, len] = safe_normalize_distance(grid_end - grid_begin);

    int removed = 0;

    for (GridLineIterator itr(grid_begin, dir, len); itr.has_more(); itr.next()) {
        godot::Vector2i grid_point = itr.current();

        if (!sprite.grid().is_grid_index_position_valid(grid_point)) {
            continue;
        }

        auto [chunk_index, cell_index] = sprite.grid().to_chunk_cell_index(grid_point);

        if (sprite.is_cell_active(chunk_index, cell_index)) {
            sprite.remove_cell(chunk_index, cell_index);
            removed += 1;
        }
    }

    return removed;
}

int cut_sprite_line(Sprite& sprite, const Transform& transform, godot::Vector2 world_begin, godot::Vector2 world_end) {
    godot::Vector2 grid_begin = sprite.grid().to_grid_point(transform.to_local_point(world_begin));
    godot::Vector2 grid_end = sprite.grid().to_grid_point(transform.to_local_point(world_end));

    return cut_sprite_line_grid(sprite, grid_begin, grid_end);
}

int cut_sprite_lines(Sprite& sprite, const Transform& transform, const godot::LocalVector<godot::Pair<godot::Vector2, godot::Vector2>>& world_lines) {
    int removed = 0;

    for (const auto& [world_begin, world_end] : world_lines) {
        removed += cut_sprite_line(sprite, transform, world_begin, world_end);
    }

    return removed;
}
