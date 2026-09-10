#pragma once

#include "DestructibleSprite/Algorithm/SpriteCutter.h"
#include "DestructibleSprite/SpriteChunkPool.h"

#include "Coordinate/Grid.h"
#include "Coordinate/Transform.h"

#include "Physics/Body.h"

#include "Assets/SpriteAsset.h"
#include "SpriteCell.h"
#include "SpriteMass.h"

#include "Containers/FlatMap.h"
#include "Result.h"

#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/templates/pair.hpp>

struct SpriteCommitConfig {
    bool debug = false;
    int smallestIslandsToSplit = 20;
};

struct SpriteChunkLocation {
    godot::Vector2 pos;
};

struct  SpriteCellGroup {
    int activeCount;
    godot::Vector2i root_grid_index_position;
    godot::LocalVector<godot::Vector2i> removed;
};

class Sprite;
struct SpriteCut;
struct SpriteCommitResult;

class Sprite {
  public:
    Sprite() = default;
    Sprite(SpriteChunkPool& chunk_pool, Grid grid, const godot::LocalVector<SpriteChunk*>& chunks, bool repairable);
    Sprite(SpriteChunkPool& chunk_pool, const SpriteAsset& asset, bool repairable);
    ~Sprite();

    Sprite(Sprite&& move);
    Sprite& operator=(Sprite&& move);

    Sprite(const Sprite& copy) = delete;
    Sprite& operator=(const Sprite& copy) = delete;

  public:
    const Grid& grid() const;
    const FlatMap<SpriteChunk*>& chunks() const;
    const godot::HashSet<SpriteChunk*>& dirty_chunks() const;
    const SpriteCellGroup& group(const SpriteCellMaskType& type) const;
    const SpriteMassInfo mass_info() const;
    int active_cell_count() const;
    godot::Vector2i cell_dim() const;
    bool is_repairable() const;
    void set_repairable(bool repairable);

    uint16_t damageable_classes() const;
    void set_damageable_classes(uint16_t mask);

    bool is_chunk_active(int chunkIndex) const;
    bool is_cell_active(int chunkIndex, int cellIndex) const;
    SpriteCell get_cell(int chunkIndex, int cellIndex) const;

    void remove_cell(int chunkIndex, int cellIndex);

    // editor write. sets color and mask of one cell, creating the chunk when
    // the grid position has none, keeps counts and mass in step. an empty
    // mask clears the cell
    void paint_cell(godot::Vector2i gridIndexPosition, Color4 color, SpriteCellMask mask);
    void damage_cell(int chunkIndex, int cellIndex);
    void repair_cell(SpriteCellMaskType type);

    // recalc every chunk from scratch. for new, loaded, expanded, or swapped
    // sprites where the whole field is invalid
    void build_distance_field();

    // Queue a chunk for the cutter without touching its cells. Used when a
    // rope holding islands together gets cut, so the next commit re-searches
    // the islands around its anchors.
    void mark_chunk_dirty(int chunkIndex);

    // Display-only pixel write. Updates chunk color/mask and queues a gpu
    // upload through the pool. Does not touch structural state, dirty cutter
    // chunks, or active counts.
    void write_display_cell(int chunkIndex, int cellIndex, Color4 color, SpriteCellMask mask);

    // Decrement heat by 1 in every chunk currently in the hot set. Chunks with
    // no heat left after the pass are pruned from the set. Called by the
    // SpriteHeatDecayUpdate system at a fixed interval.
    void decay_heat(uint16_t levels);

    bool has_hot_chunks() const;

    void remove_all_cells();

    // every cell removed since the last take, with its color. the world
    // drains this each commit so no cell leaves without a particle
    void take_loose_pixels(godot::LocalVector<godot::Pair<godot::Vector2i, Color4>>& out);
    void repair_all_cells();

    SpriteCutter start_cutter() const;

    SpriteCommitResult commit_dirty_chunks(const Transform& transform, const SpriteCommitConfig& config);

    void remove_cells_of_class(uint8_t cell_class);

    // recompute one chunk's surface from its neighbors and queue its gpu
    // upload. each call only touches its own sprite so many chunks can run
    // across threads. driven by the commit system's parallel surface pass
    void recalc_chunk_surface(SpriteChunk* chunk);

    Optional<godot::Vector2i> ray_cast(godot::Vector2 local_origin, godot::Vector2 local_end) const;

    // This is annoying because it has to replace all colliders
    // doesn't work right now.
    godot::Vector2 optimize_grid(Transform& transform);

  private:
    // (Sprite, offset, world_offset) — Sprite is move-only so return by out-param
    void cut_island(const godot::LocalVector<FloodFillResult>& islands,
                    godot::LocalVector<godot::Pair<godot::Vector2i, Color4>>& colors,
                    Sprite& out_sprite, godot::Vector2& out_offset, godot::Vector2& out_world_offset);

    void get_all_pixels_colors(godot::LocalVector<godot::Pair<godot::Vector2i, Color4>>& colors) const;

    SpriteChunkNeighbors gather_surface_neighbors(int chunkIndex) const;

    // loose records the cell as gone from the world, off when it moves to a
    // split piece instead
    void remove_chunk_cell(SpriteChunk* chunk, int cellIndex, godot::Vector2i gridIndexPosition, bool loose = true);
    void repair_chunk_cell(SpriteChunk* chunk, int cellIndex, godot::Vector2i gridIndexPosition);

    void delete_chunk(SpriteChunk* chunk);

  private:
    SpriteChunkPool* m_chunk_pool = nullptr;

    Grid m_grid;
    SpriteMass m_mass = {};

    FlatMap<SpriteChunk*> m_chunks;
    godot::HashSet<SpriteChunk*> m_dirty;
    godot::HashSet<int> m_hot_chunks;

    SpriteCellGroup m_groups[SpriteCellMaskType_Count] = {};
    int m_active_cell_count = 0;

    godot::Vector2i m_cells_dim = godot::Vector2i(0, 0); // only for player
    bool m_is_m_repairable = false;

    uint16_t m_damageable_classes = 0xFFFF;

    godot::LocalVector<godot::Pair<godot::Vector2i, Color4>> m_loose_pixels;
};

struct SpriteCut {
    Transform transform;
    Sprite sprite;
    godot::Vector2 offset;
};

struct SpriteCommitResult {
    godot::LocalVector<SpriteCut> splits;
    godot::LocalVector<godot::Pair<godot::Vector2i, Color4>> removedPixelColors;
    bool selfIsEmpty;
    godot::Vector2 offset;
    godot::HashMap<SpriteCellMaskType, size_t> split_index_with_majority_of_type;
    godot::LocalVector<SpriteChunk*> dirty_chunks; // chunks whose cells changed, seed the parallel surface and distance field passes
};

constexpr const char* type_name_of(const Sprite*) {
    return "Sprite";
}
