#include "DestructibleSprite/Sprite.h"

#include "DestructibleSprite/Algorithm/SpriteCutter.h"
#include "DestructibleSprite/Algorithm/SpriteDistanceField.h"

#include "Math/Hash.h"
#include "Containers/PopErase.h"


#include <algorithm>
#include <bitset>
#include <godot_cpp/templates/pair.hpp>

Sprite::Sprite(SpriteChunkPool& chunk_pool, Grid grid, const godot::LocalVector<SpriteChunk*>& chunks, bool repairable)
    : m_chunk_pool(&chunk_pool)
    , m_grid(grid)
    , m_chunks(grid.total_chunks_in_grid())
    , m_active_cell_count(0)
    , m_cells_dim(0, 0)
    , m_is_m_repairable(repairable) {
    for (int i = 0; i < SpriteCellMaskType_Count; i++) m_groups[i] = {};

    for (SpriteChunk* chunk : chunks) {
        m_chunks.emplace(chunk->index, chunk);
        m_dirty.insert(chunk);
        m_active_cell_count += chunk->activePixelCount;

        bool chunk_hot = false;

        // todo: chunks could store these lists as well and this could just be a sum
        // like the action pixel count
        for (int i = 0; i < m_grid.total_cells_in_chunk(); i++) {
            godot::Vector2i grid_pos = grid.to_grid_index_position(chunk->index, i);
            SpriteCellMaskType type = chunk->mask[i].get_type();
            m_groups[type].activeCount += 1;
            m_groups[type].root_grid_index_position += grid_pos;

            if (chunk->mask[i].is_filled()) {
                m_cells_dim = m_cells_dim.max(godot::Vector2i(grid_pos.x + 1, grid_pos.y + 1));
            }

            if (!chunk_hot && chunk->mask[i].get_heat() > 0) {
                chunk_hot = true;
            }
        }

        if (chunk_hot) {
            m_hot_chunks.insert(chunk->index);
        }
    }

    for (SpriteCellGroup& group : m_groups) {
        if (group.activeCount == 0) {
            continue;
        }

        group.root_grid_index_position /= group.activeCount;
    }

    m_mass = sprite_mass_init(m_grid, m_chunks);
}

Sprite::Sprite(SpriteChunkPool& chunk_pool, const SpriteAsset& asset, bool repairable)
    : m_chunk_pool(&chunk_pool)
    , m_grid(k_cells_per_chunk, asset.chunkCount)
    , m_chunks(m_grid.total_chunks_in_grid())
    , m_active_cell_count(asset.activePixelCount)
    , m_cells_dim(asset.cellCount)
    , m_is_m_repairable(repairable) {
    for (int i = 0; i < SpriteCellMaskType_Count; i++) m_groups[i] = {};

    for (int i = 0; i < SpriteCellMaskType_Count; i++) {
        SpriteCellGroup& group = m_groups[i];
        const SpriteAssetCellGroup& groupAsset = asset.groups[i];
        group.activeCount = groupAsset.activeCount;
        group.root_grid_index_position = groupAsset.root_grid_index_position;
    }

    for (const SpriteAssetChunk& chunkAsset : asset.chunks) {
        SpriteChunk* chunk = m_chunk_pool->create_chunk(chunkAsset);
        m_chunks.emplace(chunk->index, chunk);
        m_dirty.insert(chunk);

        for (int i = 0; i < m_grid.total_cells_in_chunk(); i++) {
            if (chunk->mask[i].get_heat() > 0) {
                m_hot_chunks.insert(chunk->index);
                break;
            }
        }
    }

    m_mass = sprite_mass_init(m_grid, m_chunks);
}

Sprite::~Sprite() {
    for (SpriteChunk* chunk : m_chunks.items()) {
        m_chunk_pool->delete_chunk(chunk);
    }
}

Sprite::Sprite(Sprite&& move)
    : m_chunk_pool(std::move(move.m_chunk_pool))
    , m_grid(std::move(move.m_grid))
    , m_mass(std::move(move.m_mass))
    , m_chunks(std::move(move.m_chunks))
    , m_dirty(std::move(move.m_dirty))
    , m_hot_chunks(std::move(move.m_hot_chunks))
    , m_active_cell_count(std::move(move.m_active_cell_count))
    , m_cells_dim(std::move(move.m_cells_dim))
    , m_is_m_repairable(std::move(move.m_is_m_repairable))
    , m_damageable_classes(std::move(move.m_damageable_classes)) {
    for (int i = 0; i < SpriteCellMaskType_Count; i++) {
        m_groups[i] = std::move(move.m_groups[i]);
        move.m_groups[i] = {};
    }
    move.m_chunk_pool = {};
    move.m_grid = {};
    move.m_mass = {};
    move.m_chunks = {};
    move.m_dirty = {};
    move.m_hot_chunks = {};
    move.m_active_cell_count = {};
    move.m_cells_dim = {};
    move.m_is_m_repairable = {};
    move.m_damageable_classes = 0xFFFF;
}

Sprite& Sprite::operator=(Sprite&& move) {
    for (SpriteChunk* chunk : m_chunks.items()) {
        m_chunk_pool->delete_chunk(chunk);
    }

    m_chunk_pool = std::move(move.m_chunk_pool);
    m_grid = std::move(move.m_grid);
    m_mass = std::move(move.m_mass);
    m_chunks = std::move(move.m_chunks);
    m_dirty = std::move(move.m_dirty);
    m_hot_chunks = std::move(move.m_hot_chunks);
    for (int i = 0; i < SpriteCellMaskType_Count; i++) {
        m_groups[i] = std::move(move.m_groups[i]);
        move.m_groups[i] = {};
    }
    m_active_cell_count = std::move(move.m_active_cell_count);
    m_cells_dim = std::move(move.m_cells_dim);
    m_is_m_repairable = std::move(move.m_is_m_repairable);
    m_damageable_classes = std::move(move.m_damageable_classes);

    move.m_chunk_pool = {};
    move.m_grid = {};
    move.m_mass = {};
    move.m_chunks = {};
    move.m_dirty = {};
    move.m_hot_chunks = {};
    move.m_active_cell_count = {};
    move.m_cells_dim = {};
    move.m_is_m_repairable = {};
    move.m_damageable_classes = 0xFFFF;

    return *this;
}

const Grid& Sprite::grid() const {
    return m_grid;
}

const FlatMap<SpriteChunk*>& Sprite::chunks() const {
    return m_chunks;
}

const godot::HashSet<SpriteChunk*>& Sprite::dirty_chunks() const {
    return m_dirty;
}

const SpriteCellGroup& Sprite::group(const SpriteCellMaskType& type) const {
    return m_groups[type];
}

const SpriteMassInfo Sprite::mass_info() const {
    return sprite_mass_get_info(m_mass, m_grid);
}

int Sprite::active_cell_count() const {
    return m_active_cell_count;
}

godot::Vector2i Sprite::cell_dim() const {
    return m_cells_dim;
}

bool Sprite::is_repairable() const {
    return m_is_m_repairable;
}

void Sprite::set_repairable(bool repairable) {
    m_is_m_repairable = repairable;
}

uint16_t Sprite::damageable_classes() const {
    return m_damageable_classes;
}

void Sprite::set_damageable_classes(uint16_t mask) {
    m_damageable_classes = mask;
}

bool Sprite::is_chunk_active(int chunkIndex) const {
    return m_chunks.has(chunkIndex);
}

bool Sprite::is_cell_active(int chunkIndex, int cellIndex) const {
    if (!m_grid.is_chunk_index_valid(chunkIndex)) {
        return false;
    }

    if (!m_grid.is_cell_index_valid(cellIndex)) {
        return false;
    }

    if (!m_chunks.has(chunkIndex)) {
        return false;
    }

    SpriteChunk* chunk = m_chunks[chunkIndex];

    return chunk->mask[cellIndex].is_filled();
}

SpriteCell Sprite::get_cell(int chunkIndex, int cellIndex) const {
    if (!m_chunks.has(chunkIndex)) {
        return {};
    }

    SpriteChunk* chunk = m_chunks[chunkIndex];

    return {chunk->color[cellIndex], chunk->mask[cellIndex]};
}

void Sprite::write_display_cell(int chunkIndex, int cellIndex, Color4 color, SpriteCellMask mask) {
    if (!m_chunks.has(chunkIndex)) {
        return;
    }

    SpriteChunk* chunk = m_chunks[chunkIndex];

    chunk->color[cellIndex] = color;
    chunk->mask[cellIndex] = mask;

    if (mask.get_heat() > 0) {
        m_hot_chunks.insert(chunkIndex);
    }

    m_chunk_pool->mark_dirty_chunk(chunk);
}

bool Sprite::has_hot_chunks() const {
    return !m_hot_chunks.is_empty();
}

void Sprite::decay_heat(uint16_t levels) {
    if (m_hot_chunks.is_empty()) {
        return;
    }

    godot::LocalVector<int> to_remove;
    for (int chunk_index : m_hot_chunks) {
        SpriteChunk* chunk = nullptr;

        if (!m_chunks.try_get(chunk_index, &chunk)) {
            to_remove.push_back(chunk_index);
            continue;
        }

        bool still_hot = false;
        bool changed = false;
        int total = m_grid.total_cells_in_chunk();

        for (int i = 0; i < total; i++) {
            SpriteCellMask mask = chunk->mask[i];
            uint8_t heat = mask.get_heat();

            if (heat == 0) {
                continue;
            }

            if (levels & (1u << heat)) {
                heat--;
                mask.set_heat(heat);
                chunk->mask[i] = mask;
                changed = true;
            }

            if (heat > 0) {
                still_hot = true;
            }
        }

        if (changed) {
            m_chunk_pool->mark_dirty_chunk(chunk);
        }

        if (!still_hot) {
            to_remove.push_back(chunk_index);
        }
    }
    for (int idx : to_remove) {
        m_hot_chunks.erase(idx);
    }
}

void Sprite::remove_cell(int chunkIndex, int cellIndex) {
    // printf("%d %d\n", chunkIndex, cellIndex);

    if (!m_chunks.has(chunkIndex)) {
        return;
    }

    SpriteChunk* chunk = m_chunks[chunkIndex];

    if (chunk->mask[cellIndex].get_removed()) {
        return;
    }

    godot::Vector2i chunkIndexPosition = m_grid.to_chunk_index_position(chunkIndex);
    godot::Vector2i cellIndexPosition = m_grid.to_cell_index_position(cellIndex);
    godot::Vector2i gridIndexPosition = m_grid.to_grid_index_position(chunkIndexPosition, cellIndexPosition);

    remove_chunk_cell(chunk, cellIndex, gridIndexPosition);

    m_dirty.insert(chunk);

    GridCellNeighbors neighbors = m_grid.get_cell_neighbors_in_bordering_chunks(chunkIndexPosition, cellIndexPosition);

    for (const auto& neighbor : neighbors.cells) {
        if (neighbor.exists) {
            int neighbor_chunk_index = m_grid.to_chunk_index(neighbor.chunkIndexPosition);
            int neighbor_cell_index = m_grid.to_cell_index(neighbor.cellIndexPosition);

            if (!m_chunks.has(neighbor_chunk_index)) {
                continue;
            }

            SpriteChunk* neighbor_chunk = m_chunks[neighbor_chunk_index];

            if (neighbor_chunk->mask[neighbor_cell_index].is_empty()) {
                continue;
            }

            m_dirty.insert(neighbor_chunk);
        }
    }
}

void Sprite::paint_cell(godot::Vector2i gridIndexPosition, Color4 color, SpriteCellMask mask) {
    if (!m_grid.is_grid_index_position_valid(gridIndexPosition)) {
        return;
    }

    auto [chunkIndex, cellIndex] = m_grid.to_chunk_cell_index(gridIndexPosition);

    SpriteChunk* chunk = nullptr;

    if (!m_chunks.try_get(chunkIndex, &chunk)) {
        if (mask.is_empty()) {
            return;
        }

        chunk = m_chunk_pool->create_chunk_empty();
        chunk->index = chunkIndex;
        chunk->gridPixelOffset = m_grid.to_chunk_index_position(chunkIndex) * m_grid.chunkSize;
        m_chunks.emplace(chunkIndex, chunk);
    }

    if (chunk->mask[cellIndex].is_filled()) {
        m_groups[chunk->mask[cellIndex].get_type()].activeCount -= 1;
        m_active_cell_count -= 1;
        chunk->activePixelCount -= 1;
        sprite_mass_remove_cell(m_mass, gridIndexPosition);
    }

    if (mask.is_filled()) {
        mask.set_removed(false);

        chunk->color[cellIndex] = color;
        chunk->mask[cellIndex] = mask;

        m_groups[mask.get_type()].activeCount += 1;
        m_active_cell_count += 1;
        chunk->activePixelCount += 1;
        m_cells_dim = m_cells_dim.max(godot::Vector2i(gridIndexPosition.x + 1, gridIndexPosition.y + 1));
        sprite_mass_add_cell(m_mass, gridIndexPosition);
    }

    else {
        chunk->color[cellIndex] = Color4();
        chunk->mask[cellIndex] = SpriteCellMask(SpriteCellMaskType_Empty);
    }

    m_dirty.insert(chunk);
    m_chunk_pool->mark_dirty_chunk(chunk);
}

void Sprite::damage_cell(int chunkIndex, int cellIndex) {
    if (!m_chunks.has(chunkIndex)) {
        return;
    }

    SpriteChunk* chunk = m_chunks[chunkIndex];

    if (chunk->mask[cellIndex].get_removed()) {
        return;
    }

    uint8_t cell_class = chunk->mask[cellIndex].get_class();

    if (!(m_damageable_classes & (1u << cell_class))) {
        return;
    }

    if (cell_class > 0) {
        SpriteCellMask hit = chunk->mask[cellIndex];
        hit.set_class(cell_class - 1);

        write_display_cell(chunkIndex, cellIndex, chunk->color[cellIndex], hit);

        return;
    }

    remove_cell(chunkIndex, cellIndex);
}

void Sprite::mark_chunk_dirty(int chunkIndex) {
    SpriteChunk* chunk;

    if (m_chunks.try_get(chunkIndex, &chunk)) {
        m_dirty.insert(chunk);
    }
}

void Sprite::repair_cell(SpriteCellMaskType type) {
    SpriteCellGroup& group = m_groups[type];

    // The entire group is empty, heal the entire thing at once?
    // there is going to be no candidate
    if (group.activeCount == 0) {
        return;
    }

    const godot::Vector2i& root = group.root_grid_index_position;
    godot::LocalVector<godot::Vector2i>& candidates = group.removed;

    if (candidates.size() == 0) {
        return;
    }

    constexpr godot::Vector2i offsets[8] = {godot::Vector2i(-1, -1), godot::Vector2i(0, -1), godot::Vector2i(1, -1), godot::Vector2i(-1, 0), godot::Vector2i(1, 0), godot::Vector2i(-1, 1), godot::Vector2i(0, 1), godot::Vector2i(1, 1)};

    float best_score = 0.f;
    size_t best_candidate_index = -1;

    for (size_t i = 0; i < candidates.size(); i++) {
        const godot::Vector2i& candidate = candidates[i];

        int dist_to_root = std::abs(candidate.x - root.x) + std::abs(candidate.y - root.y); // Manhattan distance
        int neighbor_count = 0;

        for (const godot::Vector2i& offset : offsets) {
            godot::Vector2i candidate_offset = candidate + offset;

            auto [chunk_index, cell_index] = m_grid.to_chunk_cell_index(candidate_offset);
            if (is_cell_active(chunk_index, cell_index)) {
                neighbor_count += 1;
            }
        }

        if (neighbor_count == 0) {
            continue;
        }

        float score = neighbor_count / static_cast<float>(dist_to_root);

        if (score > best_score) {
            best_score = score;
            best_candidate_index = i;
        }
    }

    assert(best_candidate_index != -1ull && "fix me");

    godot::Vector2i candidate = candidates[best_candidate_index];
    auto [chunk_index, cell_index] = m_grid.to_chunk_cell_index(candidate);

    repair_chunk_cell(m_chunks[chunk_index], cell_index, candidate);
    pop_erase(&best_candidate_index, group.removed);

    m_dirty.insert(m_chunks[chunk_index]);
}

void Sprite::take_loose_pixels(godot::LocalVector<godot::Pair<godot::Vector2i, Color4>>& out) {
    for (const godot::Pair<godot::Vector2i, Color4>& p : m_loose_pixels) {
        out.push_back(p);
    }
    m_loose_pixels.clear();
}

void Sprite::remove_all_cells() {
    for (SpriteChunk* chunk : m_chunks.items()) {
        for (int i = 0; i < m_grid.total_cells_in_chunk(); i++) {
            if (chunk->mask[i].is_filled()) {
                remove_cell(chunk->index, i);
            }
        }

        chunk->reset();
    }
}

void Sprite::repair_all_cells() {
    for (SpriteCellGroup& group : m_groups) {
        for (godot::Vector2i grid_index_position : group.removed) {
            auto [chunk_index, cell_index] = m_grid.to_chunk_cell_index(grid_index_position);
            SpriteChunk* chunk = m_chunks[chunk_index];
            repair_chunk_cell(chunk, cell_index, grid_index_position);

            m_dirty.insert(chunk);
        }

        group.removed.clear();
    }
}

SpriteCutter Sprite::start_cutter() const {
    return SpriteCutter(m_grid, m_chunks, m_dirty);
}

SpriteCommitResult Sprite::commit_dirty_chunks(const Transform& transform, const SpriteCommitConfig& config) {

    godot::LocalVector<SpriteCut> cuts;

    // 1. If the sprite is too small, it should be removed

    if (m_active_cell_count < config.smallestIslandsToSplit) {
        SpriteCommitResult result;
        result.selfIsEmpty = true;
        get_all_pixels_colors(result.removedPixelColors);

        for (SpriteChunk* chunk : m_dirty) {
            m_chunk_pool->mark_dirty_chunk(chunk);
        }

        return result;
    }

    // 2. Remove all empty chunks

    godot::LocalVector<SpriteChunk*> to_delete;
    for (SpriteChunk* chunk : m_dirty) {
        if (chunk->activePixelCount == 0) {
            to_delete.push_back(chunk);
        }
    }
    for (SpriteChunk* chunk : to_delete) {
        delete_chunk(chunk);
        m_dirty.erase(chunk);
    }

    // 3. Find all splits

    SpriteCutter cutter = start_cutter();

    if (config.debug) {
        cutter.enable_debug();
    }

    godot::LocalVector<SpriteSplit> splits = cutter.execute_search();

    // 4. Split

    godot::LocalVector<godot::Pair<godot::Vector2i, Color4>> removedPixelColors;

    // Donn't split small islands, just remove them. Do this first so the split_index_with_majority_of_type isn't filled
    // with splits which are too small
    for (size_t i = 0; i < splits.size(); i++) {
        const SpriteSplit& split = splits[i];

        if (split.totalCount > config.smallestIslandsToSplit) {
            continue;
        }

        for (const FloodFillResult& island : split.islands) {
            SpriteChunk* chunk = m_chunks[island.chunkIndex];
            for (const int& cellIndex : island.index) {
                Color4 color = chunk->color[cellIndex];
                godot::Vector2i gridIndexPosition = m_grid.to_grid_index_position(chunk->index, cellIndex);

                removedPixelColors.push_back({gridIndexPosition, color});
                remove_chunk_cell(chunk, cellIndex, gridIndexPosition);
            }

            if (chunk->activePixelCount == 0) {
                m_dirty.erase(chunk);
                delete_chunk(chunk);
            }

            else {
                m_dirty.insert(chunk);
            }
        }

        pop_erase(&i, splits);
    }

    // Check if one of the splits has the most core cells if more then the self
    godot::HashMap<SpriteCellMaskType, size_t> split_index_with_majority_of_type;

    if (splits.size() > 0) {
        for (int cell_type = SpriteCellMaskType_Core; cell_type < SpriteCellMaskType_Count; cell_type++) {
            int self_count_after_split = group(static_cast<SpriteCellMaskType>(cell_type)).activeCount;

            if (self_count_after_split == 0) {
                continue;
            }

            for (const SpriteSplit& split : splits) {
                self_count_after_split -= split.typeCounts[cell_type];
            }

            int max_split_cell_count = 0;
            size_t split_index_to_move_self = -1;
            for (size_t i = 0; i < splits.size(); i++) {
                const SpriteSplit& split = splits[i];
                int split_cell_count = split.typeCounts[cell_type];
                if (self_count_after_split <= split_cell_count) {
                    if (max_split_cell_count < split_cell_count) {
                        max_split_cell_count = split_cell_count;
                        split_index_to_move_self = i;
                    }
                }
            }

            if (split_index_to_move_self != -1) {
                split_index_with_majority_of_type.insert(static_cast<SpriteCellMaskType>(cell_type), split_index_to_move_self);
            }
        }
    }

    for (const SpriteSplit& split : splits) {
        Sprite cutSprite;
        godot::Vector2 cutGridOffset;
        godot::Vector2 cutGridMin;
        cut_island(split.islands, removedPixelColors, cutSprite, cutGridOffset, cutGridMin);
        godot::Vector2 cutScale = transform.scale / godot::Vector2(m_grid.chunks.x, m_grid.chunks.y);
        godot::Vector2 cutLocalPos = m_grid.to_local_point(cutGridOffset);
        godot::Vector2 cutWorldPos = transform.to_world_point(cutLocalPos);

        Transform cutTransform;
        cutTransform.position = cutWorldPos;
        cutTransform.scale = cutScale * godot::Vector2(cutSprite.m_grid.chunks.x, cutSprite.m_grid.chunks.y);
        cutTransform.angle = transform.angle;

        cuts.push_back({std::move(cutTransform), std::move(cutSprite), cutGridMin});
    }

    // 5. Hand the dirty chunks to the commit system. Their surfaces and
    // distance fields get recomputed in parallel passes over every sprite at once

    godot::LocalVector<SpriteChunk*> dirty_chunks;
    for (SpriteChunk* c : m_dirty) dirty_chunks.push_back(c);
    m_dirty.clear();

    SpriteCommitResult result;
    result.splits = std::move(cuts);
    result.removedPixelColors = std::move(removedPixelColors);
    result.selfIsEmpty = m_active_cell_count < config.smallestIslandsToSplit;
    result.offset = godot::Vector2(0.f, 0.f);
    result.split_index_with_majority_of_type = split_index_with_majority_of_type;
    result.dirty_chunks = std::move(dirty_chunks);

    if (result.selfIsEmpty) {
        get_all_pixels_colors(result.removedPixelColors);
    }

    return result;
}

#include "Coordinate/Iterator/GridLineIterator.h"
#include "DebugLineList.h"

Optional<godot::Vector2i> Sprite::ray_cast(godot::Vector2 local_origin, godot::Vector2 local_end) const {
    godot::Vector2 grid_origin = m_grid.to_grid_point(local_origin);
    godot::Vector2 grid_end = m_grid.to_grid_point(local_end);
    auto [grid_direction, grid_length] = safe_normalize_distance(grid_end - grid_origin);

    godot::Vector2 chunk_origin = grid_origin / static_cast<float>(m_grid.chunkSize);
    godot::Vector2 chunk_end = grid_end / static_cast<float>(m_grid.chunkSize);
    auto [chunk_direction, chunk_length] = safe_normalize_distance(chunk_end - chunk_origin);

    for (GridLineIterator chunk_itr(chunk_origin, chunk_direction, chunk_length); chunk_itr.has_more(); chunk_itr.next()) {
        godot::Vector2i chunk_cur = chunk_itr.current();

        if (!m_grid.is_chunk_index_position_valid(chunk_cur)) {
            continue;
        }

        int chunk_index = m_grid.to_chunk_index(chunk_cur);

        SpriteChunk* chunk;
        if (!m_chunks.try_get(chunk_index, &chunk)) {
            continue;
        }

        AxisAlignedBox chunk_box(chunk->gridPixelOffset, chunk->gridPixelOffset + godot::Vector2i(32, 32));

        auto [chunk_clip_ray_min, chunk_clip_ray_max] = chunk_box.clip_ray(grid_origin, grid_direction, grid_length);

        godot::Vector2 cell_origin = grid_origin + grid_direction * chunk_clip_ray_min;
        godot::Vector2 cell_end = grid_origin + grid_direction * chunk_clip_ray_max;
        auto [cell_direction, cell_length] = safe_normalize_distance(cell_end - cell_origin);

        for (GridLineIterator cell_itr(cell_origin, cell_direction, cell_length); cell_itr.has_more(); cell_itr.next()) {
            godot::Vector2i cell_cur = cell_itr.current() - chunk->gridPixelOffset;

            if (!m_grid.is_cell_index_position_valid(cell_cur)) {
                continue;
            }

            int cell_index = m_grid.to_cell_index(cell_cur);

            if (chunk->mask[cell_index].is_empty()) {
                continue;
            }

            return cell_itr.current();
        }
    }

    return Nothing{};
}

godot::Vector2 Sprite::optimize_grid(Transform& transform) {

    // Find min and max all islands
    godot::Vector2i min = godot::Vector2i(INT_MAX, INT_MAX);
    godot::Vector2i max = godot::Vector2i(-INT_MAX, -INT_MAX);
    for (const SpriteChunk* chunk : m_chunks.items()) {
        godot::Vector2i chunkPosition = godot::Vector2i(chunk->gridPixelOffset / m_grid.chunkSize); // could store chunkIndexPosition in chunk

        if (min.x > chunkPosition.x)
            min.x = chunkPosition.x;
        if (min.y > chunkPosition.y)
            min.y = chunkPosition.y;
        if (max.x < chunkPosition.x)
            max.x = chunkPosition.x;
        if (max.y < chunkPosition.y)
            max.y = chunkPosition.y;
    }

    godot::Vector2 currentCenter = godot::Vector2((float)m_grid.chunks.x, (float)m_grid.chunks.y) / 2.f;
    godot::Vector2 newCenter = godot::Vector2((float)(max.x + min.x + 1), (float)(max.y + min.y + 1)) / 2.f;

    godot::Vector2 gridOffset = (newCenter - currentCenter) * godot::Vector2(float(m_grid.chunkSize), float(m_grid.chunkSize));
    godot::Vector2 localOffset = gridOffset / godot::Vector2((float)m_grid.cells.x, (float)m_grid.cells.y) * 2.f;

    godot::Vector2 chunkScale = transform.scale / godot::Vector2((float)m_grid.chunks.x, (float)m_grid.chunks.y);

    m_grid = Grid(m_grid.chunkSize, godot::Vector2i(max.x - min.x + 1, max.y - min.y + 1));

    FlatMap<SpriteChunk*> chunksReindexed(m_grid.total_chunks_in_grid());

    for (SpriteChunk* chunk : m_chunks.items()) {
        chunk->gridPixelOffset -= godot::Vector2i(min.x * m_grid.chunkSize, min.y * m_grid.chunkSize);

        godot::Vector2i chunkPosition = godot::Vector2i(chunk->gridPixelOffset.x / m_grid.chunkSize, chunk->gridPixelOffset.y / m_grid.chunkSize);
        int chunkIndex = chunkPosition.x + chunkPosition.y * m_grid.chunks.x;

        chunk->index = chunkIndex;

        chunksReindexed.emplace(chunkIndex, chunk);
    }

    m_chunks = std::move(chunksReindexed); // move in new map

    transform.scale = godot::Vector2((float)m_grid.chunks.x, (float)m_grid.chunks.y) * chunkScale;

    return localOffset;
}

void Sprite::remove_cells_of_class(uint8_t cell_class) {
    for (SpriteChunk* chunk : m_chunks.items()) {
        for (int i = 0; i < m_grid.total_cells_in_chunk(); i++) {
            const SpriteCellMask& mask = chunk->mask[i];

            if (mask.is_empty() || mask.get_class() != cell_class) {
                continue;
            }

            remove_cell(chunk->index, i);
        }
    }
}

void Sprite::cut_island(const godot::LocalVector<FloodFillResult>& islands,
                        godot::LocalVector<godot::Pair<godot::Vector2i, Color4>>& colors,
                        Sprite& out_sprite, godot::Vector2& out_offset, godot::Vector2& out_world_offset) {

    // 1. Find the bounds of the region to cut

    godot::Vector2i min = godot::Vector2i(INT_MAX, INT_MAX);
    godot::Vector2i max = godot::Vector2i(-INT_MAX, -INT_MAX);
    for (const FloodFillResult& island : islands) {
        godot::Vector2i pixelOffset = m_chunks[island.chunkIndex]->gridPixelOffset;
        godot::Vector2i islandMin = island.min + pixelOffset;
        godot::Vector2i islandMax = island.max + pixelOffset;

        if (min.x > islandMin.x)
            min.x = islandMin.x;
        if (min.y > islandMin.y)
            min.y = islandMin.y;
        if (max.x < islandMax.x)
            max.x = islandMax.x;
        if (max.y < islandMax.y)
            max.y = islandMax.y;
    }

    // Todo: If the island covers the whole chunk, then it can just be moved
    // no need to reallocate and delete

    // 2. allocate new chunks

    godot::Vector2i cutGridDimensions = godot::Vector2i(max.x - min.x + 1, max.y - min.y + 1);

    Grid cutGrid = Grid::from_cells(m_grid.chunkSize, cutGridDimensions);

    godot::LocalVector<SpriteChunk*> cutChunks;
    cutChunks.reserve(cutGrid.total_chunks_in_grid());

    for (int cy = 0; cy < cutGrid.chunks.y; cy++) {
        for (int cx = 0; cx < cutGrid.chunks.x; cx++) {
            int index = cx + cy * cutGrid.chunks.x;

            SpriteChunk* cutChunk = m_chunk_pool->create_chunk_empty();
            cutChunk->index = index;
            cutChunk->gridPixelOffset = godot::Vector2i(cx, cy) * cutGrid.chunkSize;

            cutChunks.push_back(cutChunk);
        }
    }

    // 3. Copy in chunks

    for (const FloodFillResult& island : islands) {
        SpriteChunk* thisChunk = m_chunks[island.chunkIndex];

        for (const int& thisIndex : island.index) {
            const Color4& thisCellColor = thisChunk->color[thisIndex];
            const SpriteCellMask& thisCellMask = thisChunk->mask[thisIndex];
            godot::Vector2i gridIndexPosition = m_grid.to_grid_index_position(thisChunk->index, thisIndex);

            // To keep the core in the owner, don't move those pixels only remove
            // This cannot happen here anymore cus the core needs to be swapped over to the other entity
            // if (thisCellMask.get_type() == SpriteCellMaskType_Core) {
            //     colors.push_back({gridIndexPosition, thisCellColor});
            //     remove_chunk_cell(thisChunk, thisIndex, gridIndexPosition);

            //     continue;
            // }

            int x = (thisIndex % m_grid.chunkSize) + thisChunk->gridPixelOffset.x - min.x;
            int y = (thisIndex / m_grid.chunkSize) + thisChunk->gridPixelOffset.y - min.y;

            int cx = x / m_grid.chunkSize;
            int cy = y / m_grid.chunkSize;

            x = x - cx * m_grid.chunkSize;
            y = y - cy * m_grid.chunkSize;

            int i = x + y * m_grid.chunkSize;

            size_t cutChunkIndex = cx + cy * cutGrid.chunks.x;

            if (cutChunkIndex >= cutChunks.size()) {
                continue;
            }

            SpriteChunk* cutChunk = cutChunks[cutChunkIndex];

            cutChunk->color[i] = thisCellColor;
            cutChunk->mask[i] = thisCellMask;
            cutChunk->activePixelCount += 1;

            remove_chunk_cell(thisChunk, thisIndex, gridIndexPosition, false);
        }

        if (thisChunk->activePixelCount == 0) {
            m_dirty.erase(thisChunk);
            delete_chunk(thisChunk);
        }

        else {
            m_dirty.insert(thisChunk);
            m_chunk_pool->mark_dirty_chunk(thisChunk);
        }
    }

    godot::Vector2 offset = godot::Vector2(min.x, min.y) + godot::Vector2(cutGrid.chunks.x * cutGrid.chunkSize, cutGrid.chunks.y * cutGrid.chunkSize) / 2.f;

    out_sprite = Sprite(*m_chunk_pool, cutGrid, cutChunks, false);
    out_offset = offset;
    out_world_offset = godot::Vector2(min.x, min.y);
}

void Sprite::get_all_pixels_colors(godot::LocalVector<godot::Pair<godot::Vector2i, Color4>>& colors) const {

    for (const SpriteChunk* chunk : m_chunks.items()) {
        for (int i = 0; i < k_cells_per_chunk_total; i++) {
            if (chunk->mask[i].is_empty()) {
                continue;
            }

            colors.push_back({m_grid.to_grid_index_position(chunk->index, i), chunk->color[i]});
        }
    }
}

void Sprite::remove_chunk_cell(SpriteChunk* chunk, int cellIndex, godot::Vector2i gridIndexPosition, bool loose) {
    if (loose) {
        m_loose_pixels.push_back({gridIndexPosition, chunk->color[cellIndex]});
    }

    chunk->remove_cell(cellIndex);

    SpriteCellGroup& group = m_groups[chunk->mask[cellIndex].get_type()];
    group.activeCount -= 1;

    m_active_cell_count -= 1;

    if (m_is_m_repairable) {
        group.removed.push_back(gridIndexPosition);
    }

    sprite_mass_remove_cell(m_mass, gridIndexPosition);
}

void Sprite::repair_chunk_cell(SpriteChunk* chunk, int cellIndex, godot::Vector2i gridIndexPosition) {

    chunk->repair_cell(cellIndex);

    SpriteCellGroup& group = m_groups[chunk->mask[cellIndex].get_type()];
    group.activeCount += 1;

    m_active_cell_count += 1;

    sprite_mass_add_cell(m_mass, gridIndexPosition);
}

void Sprite::delete_chunk(SpriteChunk* chunk) {

    m_active_cell_count -= chunk->activePixelCount;

    // Never remove chunks for repairable sprites
    if (m_is_m_repairable) {
        return;
    }

    m_hot_chunks.erase(chunk->index);
    m_chunk_pool->delete_chunk(chunk);
    m_chunks.erase(chunk->index);
}

void Sprite::recalc_chunk_surface(SpriteChunk* chunk) {
    chunk->calc_surface(m_grid, gather_surface_neighbors(chunk->index));
    m_chunk_pool->mark_dirty_chunk(chunk);
}

SpriteChunkNeighbors Sprite::gather_surface_neighbors(int chunkIndex) const {
    SpriteChunkNeighbors neighbors{};
    m_chunks.try_get(chunkIndex - 1, &neighbors.left);
    m_chunks.try_get(chunkIndex + 1, &neighbors.right);
    m_chunks.try_get(chunkIndex + m_grid.chunks.x, &neighbors.up);
    m_chunks.try_get(chunkIndex - m_grid.chunks.x, &neighbors.down);
    return neighbors;
}

void Sprite::build_distance_field() {
    sprite_distance_field_build(*this);
}
