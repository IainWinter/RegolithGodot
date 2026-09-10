#include "FloodFill.h"
#include "Math/MathUtil.h"

#include <algorithm>


FloodFillResult flood_fill(int seed, int id, int size, const SpriteCellMask* mask, int* working) {

    FloodFillResult result{};
    result.seedIndex = seed;
    
    godot::LocalVector<godot::Vector2i> stack;
    stack.reserve(size * size);
    stack.push_back({ seed % size, seed / size });

    while (stack.size() > 0) {
        godot::Vector2i cur = stack[stack.size() - 1];
        stack.remove_at(stack.size() - 1);
        
        if (   cur.x < 0 || cur.x >= size 
            || cur.y < 0 || cur.y >= size) 
        {
            continue;
        }
            
        int index = cur.x + cur.y * size;

        int& working_index = working[index];

        if (working_index != -1) {
            continue;
        }

        SpriteCellMask mask_index = mask[index];

        if (mask_index.is_empty()) {
            continue;
        }

        working_index = id;

        result.typeCounts[mask_index.get_type()] += 1;
        result.index.push_back(index);

        constexpr godot::Vector2i offsets[8] = {
            godot::Vector2i(-1, -1),
            godot::Vector2i( 0, -1),
            godot::Vector2i( 1, -1),
            godot::Vector2i(-1,  0),
            godot::Vector2i( 1,  0),
            godot::Vector2i(-1,  1),
            godot::Vector2i( 0,  1),
            godot::Vector2i( 1,  1)
        };
        
        for (const godot::Vector2i& offset : offsets) {
            stack.push_back(cur + offset);
        }

        result.min.x = std::min(result.min.x, cur.x);
        result.min.y = std::min(result.min.y, cur.y);
        result.max.x = std::max(result.max.x, cur.x);
        result.max.y = std::max(result.max.y, cur.y);

        if (cur.y == 0) {
            result.indexContinueDown.push_back(edge_index_down(cur.x, cur.y, size));
        }

        if (cur.y == size - 1) {
            result.indexContinueUp.push_back(edge_index_up(cur.x, cur.y, size));
        }

        if (cur.x == 0) {
            result.indexContinueLeft.push_back(edge_index_left(cur.x, cur.y, size));
        }

        if (cur.x == size - 1) {
            result.indexContinueRight.push_back(edge_index_right(cur.x, cur.y, size));
        }
    }

    result.adjacencyCount = int(0 < result.indexContinueUp.size())
                          + int(0 < result.indexContinueDown.size())
                          + int(0 < result.indexContinueLeft.size())
                          + int(0 < result.indexContinueRight.size());

    return result;
}

// Average - 154us
// Average - 45us Using stack array
FloodFillResult flood_fill32(int seed, int id, const SpriteCellMask* mask, int* working) {

    FloodFillResult result{};
    result.seedIndex = seed;

    if (working[seed] != -1 || mask[seed].is_empty()) {
        return result;
    }

    constexpr int size = k_cells_per_chunk;

    int stack[size * size];
    int stack_index = 0;

    stack[stack_index++] = seed;
    working[seed] = id;

    while (stack_index > 0) {
        int cur_index = stack[--stack_index];
        int x = cur_index % size; // optimizer should replace with bitwise ops
        int y = cur_index / size;

        result.typeCounts[mask[cur_index].get_type()] += 1;
        result.index.push_back(cur_index);

        struct Offset {
            int index;
            int x;
            int y;
        };

        constexpr Offset offsets[8] = {
            { -1 - size, -1, -1 },
            {     -size,  0, -1 },
            {  1 - size,  1, -1 },
            { -1       , -1,  0 },
            {  1       ,  1,  0 },
            { -1 + size, -1,  1 },
            {      size,  0,  1 },
            {  1 + size,  1,  1 }
        };

        for (const Offset& offset : offsets) {
            int next_index = cur_index + offset.index;
            int next_x = x + offset.x;
            int next_y = y + offset.y;

            if (   next_x >= 0 
                && next_x < size 
                && next_y >= 0 
                && next_y < size
                && working[next_index] == -1
                && mask[next_index].is_filled()
                )
            {
                stack[stack_index++] = next_index;
                working[next_index] = id;
            }
        }
        
        result.min.x = std::min(result.min.x, x);
        result.min.y = std::min(result.min.y, y);
        result.max.x = std::max(result.max.x, x);
        result.max.y = std::max(result.max.y, y);

        if (y == 0) {
            result.indexContinueDown.push_back(edge_index_down(x, y, size));
        }

        if (y == size - 1) {
            result.indexContinueUp.push_back(edge_index_up(x, y, size));
        }

        if (x == 0) {
            result.indexContinueLeft.push_back(edge_index_left(x, y, size));
        }

        if (x == size - 1) {
            result.indexContinueRight.push_back(edge_index_right(x, y, size));
        }
    }

    result.adjacencyCount = int(0 < result.indexContinueUp.size())
                          + int(0 < result.indexContinueDown.size())
                          + int(0 < result.indexContinueLeft.size())
                          + int(0 < result.indexContinueRight.size());

    return result;
}