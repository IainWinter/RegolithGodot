#pragma once

#include "DestructibleSprite/SpriteChunk.h"

#include "UnionFind.h"
#include "DestructibleSprite/Algorithm/FloodFill.h"

#include "Coordinate/Grid.h"
#include "FlatMap.h"

#include <vector>
#include <queue>
#include <unordered_set>

void print_filled_chunks(const FlatMap<SpriteChunk*>& chunks, ivec2 chunkCount, int chunkPixelSize);

struct SpriteSplit {
    int totalCount;
    std::array<int, SpriteCellMaskType_Count> typeCounts;
    std::vector<FloodFillResult> islands;
};

class SpriteCutter {
public:
    using ChunkIndex = int;
    using IslandId = int;

    struct AdjacentChunk {
        ChunkIndex chunkIndex;
        FloodFillAdjacencyArray index;
    };

    struct SingleEdgeToSearch {
        int originIslandCellCount;

        ChunkIndex chunkIndex;
        IslandId islandId;

        AdjacentChunk adjacent;
    };

    struct Search {
        int rootIslandId;
    };

    struct SmallestIslandComparator {
        bool operator() (const SingleEdgeToSearch& l, const SingleEdgeToSearch& r) const { 
            return l.originIslandCellCount > r.originIslandCellCount;
        }
    };

    enum SearchState {
        SearchState_Done,
        SearchState_Continue
    };

public:
    /**
     * Construct a cutter from the internals of a Sprite. See Sprite::start_cutter
    */
    SpriteCutter(const Grid& grid, const FlatMap<SpriteChunk*>& chunks, const std::unordered_set<SpriteChunk*>& dirtyChunks);

    SpriteCutter(const SpriteCutter&) = delete;
    SpriteCutter(SpriteCutter&&) = default;
    
    ~SpriteCutter();

    void enable_debug();

    std::vector<SpriteSplit> execute_search();

private:
    bool has_any_pixel_in_index_filled(const SpriteChunk* chunk, const FloodFillAdjacencyArray& indices) const;

    std::vector<AdjacentChunk> collect_adjacent_chunks(ChunkIndex chunk, const FloodFillResult& island) const;

    int add_adjacent_chunks_to_search(int cellIndex, ChunkIndex chunkIndex, IslandId islandId, int originIslandCellCount, const ArrayView<SpriteCellMask>& mask, ArrayView<int>& fill);

    ArrayView<int> get_flood_fill_array(ChunkIndex chunkIndex);

    IslandId combine_adjacent_islands(IslandId current, IslandId adjacent);

    void execute_search_full();

    // only for test
public:
    SearchState execute_search_single_step();

    // only for test
public:
    std::vector<SpriteSplit> combine_results();

private:
    // Reference to Sprite internals
    const Grid& m_grid;
    const FlatMap<SpriteChunk*>& m_chunks;

    std::unordered_map<IslandId, FloodFillResult> m_islands; // each unique island (many in one chunk)
    std::unordered_map<ChunkIndex, ArrayView<int>> m_fills; // each chunks fill state (one per chunk, size of mask)
    
    std::priority_queue<SingleEdgeToSearch, std::vector<SingleEdgeToSearch>, SmallestIslandComparator> m_searches;
    std::unordered_map<IslandId, int> m_numberOfSearches;
    
    UnionFind m_connections;

    bool m_debug;

    int m_debugFloodFillCount;
    Color4 m_debugFloodFillColorMark;
};