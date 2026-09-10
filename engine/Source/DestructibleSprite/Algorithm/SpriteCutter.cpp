#include "DestructibleSprite/Algorithm/SpriteCutter.h"

#include "Containers/PopErase.h"

#include <godot_cpp/core/memory.hpp>

#include <iostream>
#include <sstream>

// debug
#include "DebugTimer.h"
#include "Math/Random.h"


void print_all_chunks_searching_header(UnionFind& toSeeds, int originChunk, int targetChunk, int groupIndex);

void print_all_chunks(const godot::HashMap<int, ArrayView<int>>& chunkFloodFillStates, UnionFind& toSeeds, godot::Vector2i chunkCount, int chunkPixelSize,
                    int inspecting = -1);

SpriteCutter::SpriteCutter(const Grid& grid, const FlatMap<SpriteChunk*>& chunks, const godot::HashSet<SpriteChunk*>& dirtyChunks)
    : m_grid(grid)
    , m_chunks(chunks)
    , m_debug(false) {

    // put these in enable debug
    m_debugFloodFillCount = 0;
    m_debugFloodFillColorMark = Color4(random_float(), random_float(), random_float(), 1.f);

    for (const SpriteChunk* chunk : dirtyChunks) {
        ArrayView<int> fill = get_flood_fill_array(chunk->index);

        for (int cellIndex = 0; cellIndex < m_grid.total_cells_in_chunk(); cellIndex++) {
            if (chunk->mask[cellIndex].is_empty() || fill[cellIndex] != -1) {
                continue;
            }

            int islandId = static_cast<int>(m_islands.size());
            int adjacentCount = add_adjacent_chunks_to_search(cellIndex, chunk->index, islandId, 0, chunk->mask, fill);

            m_connections.unite(islandId, islandId);

            if (adjacentCount > 0) {
                m_numberOfSearches.insert(islandId, adjacentCount);
            }
        }
    }
}

SpriteCutter::~SpriteCutter() {

    for (auto& [_, fill] : m_fills) {
        godot::memdelete_arr(fill.ptr());
    }
}

void SpriteCutter::enable_debug() {
    m_debug = true;
}

godot::LocalVector<SpriteSplit> SpriteCutter::execute_search() {

    DebugTimer timer;

    if (m_debug) {
        printf("\n\n\nInitial flood fill state:");
        print_all_chunks(m_fills, m_connections, m_grid.chunks, m_grid.chunkSize);
    }

    execute_search_full();

    if (m_debug) {
        printf("\n---\n\n\n\nFinal flood fill state:");
        print_all_chunks(m_fills, m_connections, m_grid.chunks, m_grid.chunkSize);
    }

    auto results = combine_results();

    // print debug values
    // printf("Sprite Cutter Debug:\n");
    // printf("\tDebugFloodFillCount: %d\n", m_debugFloodFillCount);
    // printf("\tTook: %f\n", timer.milliseconds());

    return results;
}

bool SpriteCutter::has_any_pixel_in_index_filled(const SpriteChunk* chunk, const FloodFillAdjacencyArray& indices) const {

    for (const int& index : indices) {
        if (chunk->mask[index].is_filled()) {
            return true;
        }
    }

    return false;
}

godot::LocalVector<SpriteCutter::AdjacentChunk> SpriteCutter::collect_adjacent_chunks(ChunkIndex chunk, const FloodFillResult& island) const {

    godot::LocalVector<AdjacentChunk> adjacentChunks;

    int chunkX = chunk % m_grid.chunks.x;
    int chunkY = chunk / m_grid.chunks.x;

    if (chunkY != m_grid.chunks.y - 1) {
        int chunkUp = chunk + m_grid.chunks.x;
        if (island.max.y == m_grid.chunkSize - 1 && m_grid.is_chunk_index_valid(chunkUp) && m_chunks.has(chunkUp)) {
            adjacentChunks.push_back({chunkUp, island.indexContinueUp});
        }
    }

    if (chunkY != 0) {
        int chunkDown = chunk - m_grid.chunks.x;
        if (island.min.y == 0 && m_grid.is_chunk_index_valid(chunkDown) && m_chunks.has(chunkDown)) {
            adjacentChunks.push_back({chunkDown, island.indexContinueDown});
        }
    }

    if (chunkX != 0) {
        int chunkLeft = chunk - 1;
        if (island.min.x == 0 && m_grid.is_chunk_index_valid(chunkLeft) && m_chunks.has(chunkLeft)) {
            adjacentChunks.push_back({chunkLeft, island.indexContinueLeft});
        }
    }

    if (chunkX != m_grid.chunks.x - 1) {
        int chunkRight = chunk + 1;
        if (island.max.x == m_grid.chunkSize - 1 && m_grid.is_chunk_index_valid(chunkRight) && m_chunks.has(chunkRight)) {
            adjacentChunks.push_back({chunkRight, island.indexContinueRight});
        }
    }

    return adjacentChunks;
}

int SpriteCutter::add_adjacent_chunks_to_search(int cellIndex, ChunkIndex chunkIndex, IslandId islandId, int originIslandCellCount,
                                            const ArrayView<SpriteCellMask>& mask, ArrayView<int>& fill) {

    m_debugFloodFillCount += 1;

    FloodFillResult island = m_grid.chunkSize == k_cells_per_chunk ? flood_fill32(cellIndex, islandId, mask, fill)
                                                             : flood_fill(cellIndex, islandId, m_grid.chunkSize, mask, fill);

    // move this its confusing
    island.chunkIndex = chunkIndex;

    // debug set color of chunk
    // if (m_debug) {
    //     SpriteChunk* chunk = m_chunks[chunkIndex];
    //     for (int i : island.index) {
    //         chunk->color[i] = m_debugFloodFillColorMark;
    //     }
    // }

    godot::LocalVector<AdjacentChunk> adjacent = collect_adjacent_chunks(chunkIndex, island);
    int numberOfAdjacentChunksAddedToSearch = 0;

    for (const AdjacentChunk& adjacentChunk : adjacent) {
        const SpriteChunk* chunk = m_chunks[adjacentChunk.chunkIndex];

        // before adding search, make sure that it would actually do something
        if (!has_any_pixel_in_index_filled(chunk, adjacentChunk.index)) {
            continue;
        }

        numberOfAdjacentChunksAddedToSearch += 1;

        SingleEdgeToSearch edge;
        edge.originIslandCellCount = static_cast<int>(island.index.size()) + originIslandCellCount;
        edge.adjacent = adjacentChunk;
        edge.chunkIndex = chunkIndex;
        edge.islandId = islandId;

        m_searches.push_back(edge);
    }

    m_islands.insert(islandId, std::move(island));

    return numberOfAdjacentChunksAddedToSearch;
}

ArrayView<int> SpriteCutter::get_flood_fill_array(ChunkIndex chunkIndex) {

    ArrayView<int> fill;
    if (m_fills.has(chunkIndex)) {
        fill = m_fills[chunkIndex];
    }

    else {
        int count = m_grid.total_cells_in_chunk();
        int* ptr = memnew_arr(int, count);
        for (int i = 0; i < count; i++) {
            ptr[i] = -1;
        }

        fill = ArrayView<int>(ptr, count);

        m_fills.insert(chunkIndex, fill);
    }

    return fill;
}

SpriteCutter::IslandId SpriteCutter::combine_adjacent_islands(IslandId current, IslandId adjacent) {

    // combine the island ids
    IslandId removedRoot = m_connections.unite(current, adjacent);
    IslandId newCurrent = m_connections.find(adjacent);

    // combine number of searches
    // here is where i think that storing the searches in a list of lists may be better cus this record keeping
    // could be for free
    m_numberOfSearches[newCurrent] += m_numberOfSearches[removedRoot];
    m_numberOfSearches.erase(removedRoot);

    return newCurrent;
}

void SpriteCutter::execute_search_full() {
    // int count = 0;

    while (m_searches.size() > 0) {
        // printf("[execute_search_full] Has %zd active searches:\n", m_searches.size());

        // for (auto [islandId, number] : m_numberOfSearches) {
        //     printf("[execute_search_full] \tisland %d -> %d searches\n", islandId, number);
        // }

        // count++;
        SearchState state = execute_search_single_step();
        if (state == SearchState_Done) {
            break;
        }
    }

    // printf("[execute_search_full] Done %d steps\n", count);
}

SpriteCutter::SearchState SpriteCutter::execute_search_single_step() {

    // exit when all but one search has been exhausted
    if (m_numberOfSearches.size() == 1) {
        return SearchState_Done;
    }

    SmallestIslandComparator cmp;
    uint32_t top_idx = 0;
    for (uint32_t i = 1; i < m_searches.size(); i++) {
        if (cmp(m_searches[top_idx], m_searches[i])) {
            top_idx = i;
        }
    }
    SingleEdgeToSearch step = m_searches[top_idx];
    m_searches.remove_at_unordered(top_idx);

    if (m_debug) {
        printf("\n---\n\n");
        print_all_chunks_searching_header(m_connections, step.chunkIndex, step.adjacent.chunkIndex, step.islandId);
    }

    if (!m_chunks[step.adjacent.chunkIndex]) {
        return SearchState_Continue;
    }

    // get the chunk fill state which we are looking at or create a new one
    // test each pixel, if there is a pixel
    //      if it is a new island id, add it to islands
    //      if it is a old island id, combine ids
    // cannot skip any pixels because one adjacent edge may have many connections

    const SpriteChunk* chunk = m_chunks[step.adjacent.chunkIndex];
    ArrayView<int> fill = get_flood_fill_array(step.adjacent.chunkIndex);

    int current = m_connections.find(step.islandId);

    m_numberOfSearches[current] -= 1;

    for (const int& cellIndex : step.adjacent.index) {
        if (chunk->mask[cellIndex].is_empty()) { // found nothing
            continue;
        }

        // Adding a new island which is adjacent to the current one
        // Join them together.
        if (fill[cellIndex] == -1) {
            int islandId = static_cast<int>(m_islands.size());
            int adjacentCount = add_adjacent_chunks_to_search(cellIndex, step.adjacent.chunkIndex, islandId, step.originIslandCellCount, chunk->mask, fill);

            if (adjacentCount > 0) {
                m_numberOfSearches.insert(islandId, adjacentCount);
                current = combine_adjacent_islands(current, islandId);
            }
        }

        else {
            int test = m_connections.find(fill[cellIndex]);

            // Join to adjacent islands together.
            if (current != test) {
                current = combine_adjacent_islands(current, test);
            }
        }
    }

    // remove
    if (m_numberOfSearches[current] == 0) {
        m_numberOfSearches.erase(current);
    }

    if (m_debug) {
        print_all_chunks(m_fills, m_connections, m_grid.chunks, m_grid.chunkSize, step.adjacent.chunkIndex);
    }

    return SearchState_Continue;
}

godot::LocalVector<SpriteSplit> SpriteCutter::combine_results() {

    godot::HashMap<int, godot::LocalVector<int>> groups = m_connections.get_groups();

    if (groups.size() == 1) { // If there is only a single island, then there is no split to return
        return {};
    }

    // Remove the group which is considered the root. Should only be 1, or 0 if there are no results
    // If there is only a single chunk m_numberOfSearches will be empty, so this is invalid unless/
    // I bring back in the code which tries to not remove the core.
    // I think this actually needs to be replaced with just removing the largest group if there are no
    // special core cells, or the one with the most core cells

    // TODO: detect if we are removing the code and just swap the Sprite components on the split rock and the
    // old entity which needs it as a nice hack around this. If not, if the only island is a core and an incomplete
    // search, then the search will have to complete which could be slow and should be unnessesary

    bool did_not_remove_unfinished_search = true;

    assert((m_numberOfSearches.size() == 0 || m_numberOfSearches.size() == 1) && "Should only ever be 1 last group");
    for (auto [group, numberOfSearches] : m_numberOfSearches) {
        groups.erase(group);
        did_not_remove_unfinished_search = false;
    }

    godot::LocalVector<SpriteSplit> results;

    for (const auto& [root, islandIndices] : groups) {
        SpriteSplit split {};

        for (const int& islandIndex : islandIndices) {
            FloodFillResult& island = m_islands[islandIndex];

            split.totalCount += static_cast<int>(island.index.size());

            for (int i = 0; i < SpriteCellMaskType_Count; i++) {
                split.typeCounts[i] += island.typeCounts[i];
            }

            split.islands.push_back(std::move(island));
        }

        results.push_back({std::move(split)});
    }

    // Keep the largest island if all searches finished
    // need more then 1 island also?
    if (did_not_remove_unfinished_search && results.size() > 1) {
        size_t maxCellIndex = 0;
        size_t maxCoreIndex = 0;

        int maxCellCount = 0;
        int maxCoreCount = 0;

        for (size_t i = 0; i < results.size(); i++) {
            int cellCount = results[i].totalCount;
            int coreCount = results[i].typeCounts[SpriteCellMaskType_Core];

            if (cellCount > maxCellCount) {
                maxCellIndex = i;
                maxCellCount = cellCount;
            }

            if (coreCount > maxCoreCount) {
                maxCoreIndex = i;
                maxCoreCount = coreCount;
            }
        }

        // Remove either island with the most core cells
        // or if there are no islands with core cells, just the most cells

        size_t indexToRemove = maxCoreCount == 0 ? maxCellIndex : maxCoreIndex;
        pop_erase(&indexToRemove, results);
    }

    return results;
}

void print_filled_chunks(const FlatMap<SpriteChunk*>& chunks, godot::Vector2i chunkCount, int chunkPixelSize) {
    std::stringstream ss;

    ss << "\n";

    const unsigned char CH_TL = 218; // ┌
    const unsigned char CH_TR = 191; // ┐
    const unsigned char CH_BL = 192; // └
    const unsigned char CH_BR = 217; // ┘

    const unsigned char CH_H = 196; // ─
    const unsigned char CH_V = 179; // │

    const unsigned char CH_TM = 194; // ┬
    const unsigned char CH_BM = 193; // ┴

    /* Top border */
    for (int cx = 0; cx < chunkCount.x; cx++) {

        if (cx == 0)
            ss << CH_TL;
        else
            ss << CH_TM;

        for (int i = 0; i < chunkPixelSize; i++) {
            ss << CH_H;
        }
    }

    ss << CH_TR << "\n";

    for (int cy = 0; cy < chunkCount.y; cy++) {

        /* Chunk rows */
        for (int y = 0; y < chunkPixelSize; y++) {

            ss << CH_V;

            for (int cx = 0; cx < chunkCount.x; cx++) {

                for (int x = 0; x < chunkPixelSize; x++) {

                    int chunkIndex = cx + cy * chunkCount.x;
                    int cellIndex = x + y * chunkPixelSize;

                    if (chunks.has(chunkIndex)) {

                        ss << (chunks[chunkIndex]->mask[cellIndex].is_empty() ? ' ' : '0');

                    } else {
                        ss << ' ';
                    }
                }

                ss << CH_V;
            }

            ss << "\n";
        }

        /* Bottom border with embedded indices */
        for (int cx = 0; cx < chunkCount.x; cx++) {

            int index = cx + cy * chunkCount.x;
            std::string str = std::format("{}", index);

            if (cx == 0)
                ss << CH_BL;
            else
                ss << CH_BM;

            /* Print index */
            ss << str;

            /* Fill rest with horizontal line */
            for (size_t i = str.size(); i < chunkPixelSize; i++) {
                ss << CH_H;
            }
        }

        ss << CH_BR << "\n";
    }

    std::cout << ss.str();
}

static constexpr char number[] = "0123456789abcdefghijklmnopqrstuvwxyz";

void print_all_chunks_searching_header(UnionFind& toSeeds, int originChunk, int targetChunk, int groupIndex) {
    int originState = toSeeds.has(groupIndex) ? toSeeds.find(groupIndex) : groupIndex;
    printf("Searching:\n    chunk: %d -> chunk: %d\n    group: %c", originChunk, targetChunk, number[originState % (sizeof(number) - 1)]);
}

void set_console_color(int color) {
    printf("\033[38;5;%dm", color);
}

/* CP437 box chars */
static const unsigned char CH_TL = 218; // ┌
static const unsigned char CH_TR = 191; // ┐
static const unsigned char CH_BL = 192; // └
static const unsigned char CH_BR = 217; // ┘

static const unsigned char CH_H = 196; // ─
static const unsigned char CH_V = 179; // │

static const unsigned char CH_TM = 194; // ┬
static const unsigned char CH_BM = 193; // ┴
static const unsigned char CH_LM = 195; // ├
static const unsigned char CH_RM = 180; // ┤
static const unsigned char CH_MM = 197; // ┼

void print_all_chunks(const godot::HashMap<int, ArrayView<int>>& chunkFloodFillStates, UnionFind& toSeeds, godot::Vector2i chunkCount, int chunkPixelSize,
                    int inspecting) {
    set_console_color(15);
    printf("\n");

    int stride = 1;

    for (int cx = 0; cx < chunkCount.x; cx++) {

        if (cx == 0)
            printf("%c", CH_TL);
        else
            printf("%c", CH_TM);

        for (int i = 0; i < chunkPixelSize; i++) {
            printf("%c", CH_H);
        }
    }

    printf("%c\n", CH_TR);

    for (int cy = 0; cy < chunkCount.y; cy++) {
        for (int y = 0; y < chunkPixelSize; y += stride) {
            printf("%c", CH_V);
            for (int cx = 0; cx < chunkCount.x; cx++) {
                for (int x = 0; x < chunkPixelSize; x += stride) {
                    int chunkIndex = cx + cy * chunkCount.x;
                    int cellIndex = x + y * chunkPixelSize;

                    if (chunkFloodFillStates.has(chunkIndex)) {

                        int state = chunkFloodFillStates[chunkIndex][cellIndex];

                        if (state == -1) {
                            printf(" ");
                        } else {

                            int originState = toSeeds.has(state) ? toSeeds.find(state) : state;

                            set_console_color(originState + 1);

                            printf("%c", number[originState % (sizeof(number) - 1)]);

                            set_console_color(15);
                        }

                    } else {
                        printf(" ");
                    }
                }

                printf("%c", CH_V);
            }

            printf("\n");
        }

        for (int cx = 0; cx < chunkCount.x; cx++) {
            int index = cx + cy * chunkCount.x;
            std::string str = std::format("{}", index);

            if (cy == chunkCount.y - 1) {
                if (cx == 0)
                    printf("%c", CH_BL);
                else if (cx == chunkCount.x)
                    printf("%c", CH_BR);
                else
                    printf("%c", CH_BM);
            } else {
                if (cx == 0)
                    printf("%c", CH_LM);
                else if (cx == chunkCount.x)
                    printf("%c", CH_RM);
                else
                    printf("%c", CH_MM);
            }

            if (inspecting == index) {
                set_console_color(200);
            }

            printf("%s", str.c_str());
            set_console_color(15);

            for (size_t i = str.size(); i < chunkPixelSize; i++) {
                printf("%c", CH_H);
            }
        }

        if (cy == chunkCount.y - 1) {
            printf("%c\n", CH_BR);
        } else {
            printf("%c\n", CH_RM);
        }
    }
}