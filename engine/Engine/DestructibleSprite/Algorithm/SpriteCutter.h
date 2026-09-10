#pragma once

#include "DestructibleSprite/SpriteChunk.h"

#include "Containers/UnionFind.h"
#include "DestructibleSprite/Algorithm/FloodFill.h"

#include "Coordinate/Grid.h"
#include "Containers/FlatMap.h"

#include "Containers/PriorityQueue.h"

#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/templates/hash_set.hpp>

void print_filled_chunks(const FlatMap<SpriteChunk*>& chunks, godot::Vector2i chunkCount, int chunkPixelSize);

struct SpriteSplit {
    int totalCount;
    int typeCounts[SpriteCellMaskType_Count];
    godot::LocalVector<FloodFillResult> islands;
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
    SpriteCutter(const Grid& grid, const FlatMap<SpriteChunk*>& chunks, const godot::HashSet<SpriteChunk*>& dirtyChunks);

    SpriteCutter(const SpriteCutter&) = delete;
    SpriteCutter(SpriteCutter&&) = default;
    
    ~SpriteCutter();

    void enable_debug();

    godot::LocalVector<SpriteSplit> execute_search();

private:
    bool has_any_pixel_in_index_filled(const SpriteChunk* chunk, const FloodFillAdjacencyArray& indices) const;

    godot::LocalVector<AdjacentChunk> collect_adjacent_chunks(ChunkIndex chunk, const FloodFillResult& island) const;

    int add_adjacent_chunks_to_search(int cellIndex, ChunkIndex chunkIndex, IslandId islandId, int originIslandCellCount, const ArrayView<SpriteCellMask>& mask, ArrayView<int>& fill);

    ArrayView<int> get_flood_fill_array(ChunkIndex chunkIndex);

    IslandId combine_adjacent_islands(IslandId current, IslandId adjacent);

    void execute_search_full();

    // only for test
public:
    SearchState execute_search_single_step();

    // only for test
public:
    godot::LocalVector<SpriteSplit> combine_results();

private:
    // Reference to Sprite internals
    const Grid& m_grid;
    const FlatMap<SpriteChunk*>& m_chunks;

    godot::HashMap<IslandId, FloodFillResult> m_islands; // each unique island (many in one chunk)
    godot::HashMap<ChunkIndex, ArrayView<int>> m_fills; // each chunks fill state (one per chunk, size of mask)
    
    godot::LocalVector<SingleEdgeToSearch> m_searches;
    godot::HashMap<IslandId, int> m_numberOfSearches;
    
    UnionFind m_connections;

    bool m_debug;

    int m_debugFloodFillCount;
    Color4 m_debugFloodFillColorMark;
};