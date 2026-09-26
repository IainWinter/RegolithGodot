#pragma once

#include "SpriteCell.h"

#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/vector2.hpp>

class Sprite;

// one core of a sprite: every cell of one non filled mask type (Core,
// Weakpoint1-4, Joint1-4) found on load from the mask. the sprite keeps them
// across splits and blows one up once enough of it is shot away. port of the
// SpriteCore struct and SpriteCoreSet component of the original
struct SpriteCore {
    SpriteCellMaskType type = SpriteCellMaskType_Core;
    // center of the core's cells in grid points of the owning sprite
    godot::Vector2 grid_point_offset;
    int initial_cell_count = 0;
};

// a core that went unstable this update, the SpriteCoreExplodedEvent
struct SpriteCoreExploded {
    SpriteCellMaskType type = SpriteCellMaskType_Core;
    godot::Vector2 grid_point_offset;
    // cells left or half the initial count, whichever is more
    int power = 0;
};

class SpriteCoreSet {
public:
    const godot::LocalVector<SpriteCore>& cores() const {
        return m_cores;
    }

    godot::LocalVector<SpriteCore>& cores() {
        return m_cores;
    }

    SpriteCore* get_core_by_type(SpriteCellMaskType core_type) {
        for (SpriteCore& core : m_cores) {
            if (core.type == core_type) {
                return &core;
            }
        }

        return nullptr;
    }

    void remove_core_by_type(SpriteCellMaskType core_type) {
        for (size_t i = 0; i < m_cores.size();) {
            if (m_cores[i].type == core_type) {
                m_cores.remove_at(i);
            }

            else {
                i++;
            }
        }
    }

    void add_core(const SpriteCore& core) {
        m_cores.push_back(core);
    }

    // moves the core at index into the removed list
    void remove_core(size_t core_index) {
        m_remove_cores.push_back(m_cores[core_index]);
        m_cores.remove_at(core_index);
    }

    void repair_all_cores() {
        for (const SpriteCore& core : m_remove_cores) {
            m_cores.push_back(core);
        }

        m_remove_cores.clear();
        m_unstable = false;
    }

    bool is_unstable() const {
        return m_unstable;
    }

    // every live core explodes on the next update
    void set_unstable() {
        m_unstable = true;
    }

    bool is_empty() const {
        return m_cores.is_empty();
    }

private:
    godot::LocalVector<SpriteCore> m_cores;
    godot::LocalVector<SpriteCore> m_remove_cores;
    bool m_unstable = false;
};

// SpriteCoreProps.explode_damage of the original: a core explodes once this
// share of its cells is gone
constexpr float k_core_explode_damage = 0.7f;

// a core that is not a joint explodes once its cells are more than this
// share of every cell left in the sprite, the hull is gone
constexpr float k_core_share_of_sprite_limit = 0.2f;

// damage of one core, 0 untouched to 1 every cell gone
float sprite_core_damage(const Sprite& sprite, const SpriteCore& core);

// cells of the core still in the sprite
int sprite_core_remaining(const Sprite& sprite, const SpriteCore& core);

// the SpriteCoreUpdateSystem tick for one sprite: a core explodes once its
// damage reaches explode_damage, once the set was marked unstable or, for
// cores that are not joints, once its cells are more than a fifth of what is
// left of the sprite. exploded cores leave the live set and can come back
// with repair_all_cores. exploded lists them in the order they went
void sprite_core_update(const Sprite& sprite, SpriteCoreSet& cores, float explode_damage, godot::LocalVector<SpriteCoreExploded>& exploded);
