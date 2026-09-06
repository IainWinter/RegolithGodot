#include "DestructibleSprite/Sprite.h"

#include "DestructibleSprite/Algorithm/SpriteCutter.h"
#include "DestructibleSprite/Algorithm/SpriteDistanceField.h"

#include "Math/Hash.h"
#include "PopErase.h"


#include <algorithm>
#include <bitset>
#include <utility>

Sprite::Sprite(SpriteChunkPool& chunk_pool, Grid grid, const std::vector<SpriteChunk*>& chunks, bool repairable)
    : m_chunk_pool(&chunk_pool)
    , m_grid(grid)
    , m_chunks(grid.total_chunks_in_grid())
    , m_active_cell_count(0)
    , m_cells_dim(0)
    , m_is_m_repairable(repairable) {
    m_groups = {};

    for (SpriteChunk* chunk : chunks) {
        m_chunks.emplace(chunk->index, chunk);
        m_dirty.insert(chunk);
        m_active_cell_count += chunk->activePixelCount;

        bool chunk_hot = false;

        // todo: chunks could store these lists as well and this could just be a sum
        // like the action pixel count
        for (int i = 0; i < m_grid.total_cells_in_chunk(); i++) {
            ivec2 grid_pos = grid.to_grid_index_position(chunk->index, i);
            SpriteCellMaskType type = chunk->mask[i].get_type();
            m_groups.at(type).activeCount += 1;
            m_groups.at(type).root_grid_index_position += grid_pos;

            if (chunk->mask[i].is_filled()) {
                m_cells_dim = max(m_cells_dim, grid_pos + 1);
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
    m_groups = {};

    for (size_t i = 0; i < asset.groups.size(); i++) {
        SpriteCellGroup& group = m_groups.at(i);
        const SpriteAssetCellGroup& groupAsset = asset.groups.at(i);
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
    , m_groups(std::move(move.m_groups))
    , m_active_cell_count(std::move(move.m_active_cell_count))
    , m_cells_dim(std::move(move.m_cells_dim))
    , m_is_m_repairable(std::move(move.m_is_m_repairable))
    , m_damageable_classes(std::move(move.m_damageable_classes)) {
    move.m_chunk_pool = {};
    move.m_grid = {};
    move.m_mass = {};
    move.m_chunks = {};
    move.m_dirty = {};
    move.m_hot_chunks = {};
    move.m_groups = {};
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
    m_groups = std::move(move.m_groups);
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
    move.m_groups = {};
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

const std::unordered_set<SpriteChunk*>& Sprite::dirty_chunks() const {
    return m_dirty;
}

const SpriteCellGroup& Sprite::group(const SpriteCellMaskType& type) const {
    return m_groups.at(type);
}

const SpriteMassInfo Sprite::mass_info() const {
    return sprite_mass_get_info(m_mass, m_grid);
}

int Sprite::active_cell_count() const {
    return m_active_cell_count;
}

ivec2 Sprite::cell_dim() const {
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
    return m_chunks.contains(chunkIndex);
}

bool Sprite::is_cell_active(int chunkIndex, int cellIndex) const {
    if (!m_grid.is_chunk_index_valid(chunkIndex)) {
        return false;
    }

    if (!m_grid.is_cell_index_valid(cellIndex)) {
        return false;
    }

    if (!m_chunks.contains(chunkIndex)) {
        return false;
    }

    SpriteChunk* chunk = m_chunks.at(chunkIndex);

    return chunk->mask[cellIndex].is_filled();
}

SpriteCell Sprite::get_cell(int chunkIndex, int cellIndex) const {
    if (!m_chunks.contains(chunkIndex)) {
        return {};
    }

    SpriteChunk* chunk = m_chunks.at(chunkIndex);

    return {chunk->color[cellIndex], chunk->mask[cellIndex]};
}

void Sprite::write_display_cell(int chunkIndex, int cellIndex, Color4 color, SpriteCellMask mask) {
    if (!m_chunks.contains(chunkIndex)) {
        return;
    }

    SpriteChunk* chunk = m_chunks.at(chunkIndex);

    chunk->color[cellIndex] = color;
    chunk->mask[cellIndex] = mask;

    if (mask.get_heat() > 0) {
        m_hot_chunks.insert(chunkIndex);
    }

    m_chunk_pool->mark_dirty_chunk(chunk);
}

bool Sprite::has_hot_chunks() const {
    return !m_hot_chunks.empty();
}

void Sprite::decay_heat(uint16_t levels) {
    if (m_hot_chunks.empty()) {
        return;
    }

    auto itr = m_hot_chunks.begin();

    while (itr != m_hot_chunks.end()) {
        int chunk_index = *itr;
        SpriteChunk* chunk = nullptr;

        if (!m_chunks.try_get(chunk_index, &chunk)) {
            itr = m_hot_chunks.erase(itr);
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

        if (still_hot) {
            ++itr;
        }

        else {
            itr = m_hot_chunks.erase(itr);
        }
    }
}

void Sprite::remove_cell(int chunkIndex, int cellIndex) {
    // printf("%d %d\n", chunkIndex, cellIndex);

    if (!m_chunks.contains(chunkIndex)) {
        return;
    }

    SpriteChunk* chunk = m_chunks.at(chunkIndex);

    if (chunk->mask[cellIndex].get_removed()) {
        return;
    }

    ivec2 chunkIndexPosition = m_grid.to_chunk_index_position(chunkIndex);
    ivec2 cellIndexPosition = m_grid.to_cell_index_position(cellIndex);
    ivec2 gridIndexPosition = m_grid.to_grid_index_position(chunkIndexPosition, cellIndexPosition);

    remove_chunk_cell(chunk, cellIndex, gridIndexPosition);

    m_dirty.emplace(chunk);

    GridCellNeighbors neighbors = m_grid.get_cell_neighbors_in_bordering_chunks(chunkIndexPosition, cellIndexPosition);

    for (const auto& neighbor : neighbors.cells) {
        if (neighbor.exists) {
            int neighbor_chunk_index = m_grid.to_chunk_index(neighbor.chunkIndexPosition);
            int neighbor_cell_index = m_grid.to_cell_index(neighbor.cellIndexPosition);

            if (!m_chunks.contains(neighbor_chunk_index)) {
                continue;
            }

            SpriteChunk* neighbor_chunk = m_chunks.at(neighbor_chunk_index);

            if (neighbor_chunk->mask[neighbor_cell_index].is_empty()) {
                continue;
            }

            m_dirty.emplace(neighbor_chunk);
        }
    }
}

void Sprite::paint_cell(ivec2 gridIndexPosition, Color4 color, SpriteCellMask mask) {
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
        m_cells_dim = max(m_cells_dim, gridIndexPosition + 1);
        sprite_mass_add_cell(m_mass, gridIndexPosition);
    }

    else {
        chunk->color[cellIndex] = Color4();
        chunk->mask[cellIndex] = SpriteCellMask(SpriteCellMaskType_Empty);
    }

    m_dirty.emplace(chunk);
    m_chunk_pool->mark_dirty_chunk(chunk);
}

void Sprite::damage_cell(int chunkIndex, int cellIndex) {
    if (!m_chunks.contains(chunkIndex)) {
        return;
    }

    SpriteChunk* chunk = m_chunks.at(chunkIndex);

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
    SpriteCellGroup& group = m_groups.at(type);

    // The entire group is empty, heal the entire thing at once?
    // there is going to be no candidate
    if (group.activeCount == 0) {
        return;
    }

    const ivec2& root = group.root_grid_index_position;
    std::vector<ivec2>& candidates = group.removed;

    if (candidates.size() == 0) {
        return;
    }

    constexpr ivec2 offsets[8] = {ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1), ivec2(-1, 0), ivec2(1, 0), ivec2(-1, 1), ivec2(0, 1), ivec2(1, 1)};

    float best_score = 0.f;
    size_t best_candidate_index = -1;

    for (size_t i = 0; i < candidates.size(); i++) {
        const ivec2& candidate = candidates.at(i);

        int dist_to_root = std::abs(candidate.x - root.x) + std::abs(candidate.y - root.y); // Manhattan distance
        int neighbor_count = 0;

        for (const ivec2& offset : offsets) {
            ivec2 candidate_offset = candidate + offset;

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

    ivec2 candidate = candidates.at(best_candidate_index);
    auto [chunk_index, cell_index] = m_grid.to_chunk_cell_index(candidate);

    repair_chunk_cell(m_chunks.at(chunk_index), cell_index, candidate);
    pop_erase(&best_candidate_index, group.removed);

    m_dirty.emplace(m_chunks.at(chunk_index));
}

void Sprite::take_loose_pixels(std::vector<std::pair<ivec2, Color4>>& out) {
    out.insert(out.end(), m_loose_pixels.begin(), m_loose_pixels.end());
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
        for (ivec2 grid_index_position : group.removed) {
            auto [chunk_index, cell_index] = m_grid.to_chunk_cell_index(grid_index_position);
            SpriteChunk* chunk = m_chunks.at(chunk_index);
            repair_chunk_cell(chunk, cell_index, grid_index_position);

            m_dirty.emplace(chunk);
        }

        group.removed.clear();
    }
}

SpriteCutter Sprite::start_cutter() const {
    return SpriteCutter(m_grid, m_chunks, m_dirty);
}

SpriteCommitResult Sprite::commit_dirty_chunks(const Transform& transform, const SpriteCommitConfig& config) {

    std::vector<SpriteCut> cuts;

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

    auto itr = m_dirty.begin();
    while (itr != m_dirty.end()) {
        SpriteChunk* chunk = *itr;
        if (chunk->activePixelCount == 0) {
            delete_chunk(chunk);
            itr = m_dirty.erase(itr);
        }

        else {
            ++itr;
        }
    }

    // 3. Find all splits

    SpriteCutter cutter = start_cutter();

    if (config.debug) {
        cutter.enable_debug();
    }

    std::vector<SpriteSplit> splits = cutter.execute_search();

    // 4. Split

    std::vector<std::pair<ivec2, Color4>> removedPixelColors;

    // Donn't split small islands, just remove them. Do this first so the split_index_with_majority_of_type isn't filled
    // with splits which are too small
    for (size_t i = 0; i < splits.size(); i++) {
        const SpriteSplit& split = splits.at(i);

        if (split.totalCount > config.smallestIslandsToSplit) {
            continue;
        }

        for (const FloodFillResult& island : split.islands) {
            SpriteChunk* chunk = m_chunks.at(island.chunkIndex);
            for (const int& cellIndex : island.index) {
                Color4 color = chunk->color[cellIndex];
                ivec2 gridIndexPosition = m_grid.to_grid_index_position(chunk->index, cellIndex);

                removedPixelColors.emplace_back(gridIndexPosition, color);
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
    std::unordered_map<SpriteCellMaskType, size_t> split_index_with_majority_of_type;

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
                const SpriteSplit& split = splits.at(i);
                int split_cell_count = split.typeCounts[cell_type];
                if (self_count_after_split <= split_cell_count) {
                    if (max_split_cell_count < split_cell_count) {
                        max_split_cell_count = split_cell_count;
                        split_index_to_move_self = i;
                    }
                }
            }

            if (split_index_to_move_self != -1) {
                split_index_with_majority_of_type.emplace(static_cast<SpriteCellMaskType>(cell_type), split_index_to_move_self);
            }
        }
    }

    for (const SpriteSplit& split : splits) {
        auto [cutSprite, cutGridOffset, cutGridMin] = cut_island(split.islands, removedPixelColors);
        vec2 cutScale = transform.scale / vec2(m_grid.chunks);
        vec2 cutLocalPos = m_grid.to_local_point(cutGridOffset);
        vec2 cutWorldPos = transform.to_world_point(cutLocalPos);

        Transform cutTransform;
        cutTransform.position = cutWorldPos;
        cutTransform.scale = cutScale * vec2(cutSprite.m_grid.chunks);
        cutTransform.angle = transform.angle;

        cuts.emplace_back(std::move(cutTransform), std::move(cutSprite), cutGridMin);
    }

    // 5. Hand the dirty chunks to the commit system. Their surfaces and
    // distance fields get recomputed in parallel passes over every sprite at once

    std::vector<SpriteChunk*> dirty_chunks(m_dirty.begin(), m_dirty.end());
    m_dirty.clear();

    SpriteCommitResult result;
    result.splits = std::move(cuts);
    result.removedPixelColors = std::move(removedPixelColors);
    result.selfIsEmpty = m_active_cell_count < config.smallestIslandsToSplit;
    result.offset = vec2(0.f);
    result.split_index_with_majority_of_type = split_index_with_majority_of_type;
    result.dirty_chunks = std::move(dirty_chunks);

    if (result.selfIsEmpty) {
        get_all_pixels_colors(result.removedPixelColors);
    }

    return result;
}

#include "Coordinate/Iterator/GridLineIterator.h"
#include "DebugLineList.h"

std::optional<ivec2> Sprite::ray_cast(vec2 local_origin, vec2 local_end) const {
    vec2 grid_origin = m_grid.to_grid_point(local_origin);
    vec2 grid_end = m_grid.to_grid_point(local_end);
    auto [grid_direction, grid_length] = safe_normalize_distance(grid_end - grid_origin);

    vec2 chunk_origin = grid_origin / static_cast<float>(m_grid.chunkSize);
    vec2 chunk_end = grid_end / static_cast<float>(m_grid.chunkSize);
    auto [chunk_direction, chunk_length] = safe_normalize_distance(chunk_end - chunk_origin);

    for (GridLineIterator chunk_itr(chunk_origin, chunk_direction, chunk_length); chunk_itr.has_more(); chunk_itr.next()) {
        ivec2 chunk_cur = chunk_itr.current();

        if (!m_grid.is_chunk_index_position_valid(chunk_cur)) {
            continue;
        }

        int chunk_index = m_grid.to_chunk_index(chunk_cur);

        SpriteChunk* chunk;
        if (!m_chunks.try_get(chunk_index, &chunk)) {
            continue;
        }

        AxisAlignedBox chunk_box(chunk->gridPixelOffset, chunk->gridPixelOffset + ivec2(32));

        auto [chunk_clip_ray_min, chunk_clip_ray_max] = chunk_box.clip_ray(grid_origin, grid_direction, grid_length);

        vec2 cell_origin = grid_origin + grid_direction * chunk_clip_ray_min;
        vec2 cell_end = grid_origin + grid_direction * chunk_clip_ray_max;
        auto [cell_direction, cell_length] = safe_normalize_distance(cell_end - cell_origin);

        for (GridLineIterator cell_itr(cell_origin, cell_direction, cell_length); cell_itr.has_more(); cell_itr.next()) {
            ivec2 cell_cur = cell_itr.current() - chunk->gridPixelOffset;

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

    return std::nullopt;
}

vec2 Sprite::optimize_grid(Transform& transform) {

    // Find min and max all islands
    ivec2 min = ivec2(INT_MAX, INT_MAX);
    ivec2 max = ivec2(-INT_MAX, -INT_MAX);
    for (const SpriteChunk* chunk : m_chunks.items()) {
        ivec2 chunkPosition = ivec2(chunk->gridPixelOffset / m_grid.chunkSize); // could store chunkIndexPosition in chunk

        if (min.x > chunkPosition.x)
            min.x = chunkPosition.x;
        if (min.y > chunkPosition.y)
            min.y = chunkPosition.y;
        if (max.x < chunkPosition.x)
            max.x = chunkPosition.x;
        if (max.y < chunkPosition.y)
            max.y = chunkPosition.y;
    }

    vec2 currentCenter = vec2(m_grid.chunks) / 2.f; // this assumes that min is 0
    vec2 newCenter = vec2(max + min + 1) / 2.f;     // take the average of min and max

    vec2 gridOffset = (newCenter - currentCenter) * vec2(float(m_grid.chunkSize));
    vec2 localOffset = gridOffset / vec2(m_grid.cells) * 2.f; // scale to local coords

    vec2 chunkScale = transform.scale / vec2(m_grid.chunks);

    m_grid = Grid(m_grid.chunkSize, max - min + 1);

    FlatMap<SpriteChunk*> chunksReindexed(m_grid.total_chunks_in_grid());

    for (SpriteChunk* chunk : m_chunks.items()) { // move chunk placement
        chunk->gridPixelOffset -= min * m_grid.chunkSize;

        ivec2 chunkPosition = ivec2(chunk->gridPixelOffset / m_grid.chunkSize);
        int chunkIndex = chunkPosition.x + chunkPosition.y * m_grid.chunks.x;

        chunk->index = chunkIndex;

        chunksReindexed.emplace(chunkIndex, chunk);
    }

    m_chunks = std::move(chunksReindexed); // move in new map

    transform.scale = vec2(m_grid.chunks) * chunkScale;

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

std::tuple<Sprite, vec2, vec2> Sprite::cut_island(const std::vector<FloodFillResult>& islands, std::vector<std::pair<ivec2, Color4>>& colors) {

    // 1. Find the bounds of the region to cut

    ivec2 min = ivec2(INT_MAX, INT_MAX);
    ivec2 max = ivec2(-INT_MAX, -INT_MAX);
    for (const FloodFillResult& island : islands) {
        ivec2 pixelOffset = m_chunks.at(island.chunkIndex)->gridPixelOffset;
        ivec2 islandMin = island.min + pixelOffset;
        ivec2 islandMax = island.max + pixelOffset;

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

    ivec2 cutGridDimensions = max - min + 1;

    Grid cutGrid = Grid::from_cells(m_grid.chunkSize, cutGridDimensions);

    std::vector<SpriteChunk*> cutChunks;
    cutChunks.reserve(cutGrid.total_chunks_in_grid());

    for (int cy = 0; cy < cutGrid.chunks.y; cy++) {
        for (int cx = 0; cx < cutGrid.chunks.x; cx++) {
            int index = cx + cy * cutGrid.chunks.x;

            SpriteChunk* cutChunk = m_chunk_pool->create_chunk_empty();
            cutChunk->index = index;
            cutChunk->gridPixelOffset = ivec2(cx, cy) * cutGrid.chunkSize;

            cutChunks.push_back(cutChunk);
        }
    }

    // 3. Copy in chunks

    for (const FloodFillResult& island : islands) {
        SpriteChunk* thisChunk = m_chunks.at(island.chunkIndex);

        for (const int& thisIndex : island.index) {
            const Color4& thisCellColor = thisChunk->color[thisIndex];
            const SpriteCellMask& thisCellMask = thisChunk->mask[thisIndex];
            ivec2 gridIndexPosition = m_grid.to_grid_index_position(thisChunk->index, thisIndex);

            // To keep the core in the owner, don't move those pixels only remove
            // This cannot happen here anymore cus the core needs to be swapped over to the other entity
            // if (thisCellMask.get_type() == SpriteCellMaskType_Core) {
            //     colors.emplace_back(gridIndexPosition, thisCellColor);
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

            SpriteChunk* cutChunk = cutChunks.at(cutChunkIndex);

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

    vec2 offset = vec2(min) + vec2(cutGrid.chunks * cutGrid.chunkSize) / 2.f;

    return {Sprite(*m_chunk_pool, cutGrid, cutChunks, false), offset, min};
}

void Sprite::get_all_pixels_colors(std::vector<std::pair<ivec2, Color4>>& colors) const {

    for (const SpriteChunk* chunk : m_chunks.items()) {
        for (int i = 0; i < k_cells_per_chunk_total; i++) {
            if (chunk->mask[i].is_empty()) {
                continue;
            }

            colors.emplace_back(m_grid.to_grid_index_position(chunk->index, i), chunk->color[i]);
        }
    }
}

void Sprite::remove_chunk_cell(SpriteChunk* chunk, int cellIndex, ivec2 gridIndexPosition, bool loose) {
    if (loose) {
        m_loose_pixels.emplace_back(gridIndexPosition, chunk->color[cellIndex]);
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

void Sprite::repair_chunk_cell(SpriteChunk* chunk, int cellIndex, ivec2 gridIndexPosition) {

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
