#include "SpriteCore.h"

#include "DestructibleSprite/Sprite.h"

#include <algorithm>

int sprite_core_remaining(const Sprite& sprite, const SpriteCore& core) {
    return sprite.group(core.type).activeCount;
}

float sprite_core_damage(const Sprite& sprite, const SpriteCore& core) {
    if (core.initial_cell_count <= 0) {
        return 0.f;
    }

    float ratio_remaining = sprite_core_remaining(sprite, core) / static_cast<float>(core.initial_cell_count);

    return 1.f - std::clamp(ratio_remaining, 0.f, 1.f);
}

void sprite_core_update(const Sprite& sprite, SpriteCoreSet& cores, float explode_damage, godot::LocalVector<SpriteCoreExploded>& exploded) {
    int total_remaining = sprite.active_cell_count();

    for (size_t i = 0; i < cores.cores().size();) {
        const SpriteCore& core = cores.cores()[i];

        int remaining = sprite_core_remaining(sprite, core);
        float ratio_of_core_to_total = total_remaining == 0 ? 0.f : remaining / static_cast<float>(total_remaining);
        float damage = sprite_core_damage(sprite, core);

        bool is_unstable = cores.is_unstable() || damage >= explode_damage;

        if (!sprite_cell_type_is_joint(core.type)) {
            is_unstable |= ratio_of_core_to_total > k_core_share_of_sprite_limit;
        }

        if (!is_unstable) {
            i++;
            continue;
        }

        exploded.push_back({
            core.type,
            core.grid_point_offset,
            std::max(remaining, core.initial_cell_count / 2),
        });

        cores.remove_core(i);
    }
}
