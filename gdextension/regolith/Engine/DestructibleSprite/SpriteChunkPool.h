#pragma once

#include "SpriteChunk.h"
#include "SpriteCell.h"
#include "Assets/SpriteAsset.h"

#include "Memory/FreeListChunkAllocator.h"
#include "Memory/FreeList.h"

#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/templates/spin_lock.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include "glm/vec3.hpp"

#include <unordered_map>
#include <unordered_set>
#include <vector>

/*
    Owns every chunk's cell memory and the atlas textures they render from.
    Sprites hold chunk pointers. Each atlas page is one layer of a
    Texture2DArray, color is RGBA8 and the cell mask bits are RG8. Dirty
    chunks write into their page's byte buffer and every touched page uploads
    once per commit.
*/
class SpriteChunkPool {
public:
    SpriteChunkPool() = default;
    SpriteChunkPool(int chunk_size, int atlas_page_size, int atlas_page_count);

    // allocates the chunk memory and atlas pages, once
    void create(int chunk_size, int atlas_page_size, int atlas_page_count);
    bool is_created() const;

    godot::Ref<godot::Texture2DArray> color_texture() const;
    godot::Ref<godot::Texture2DArray> mask_texture() const;

    int chunk_size() const;
    int atlas_page_size() const;
    int atlas_page_count() const;
    size_t alive_count() const;
    size_t capacity() const;

    SpriteChunk* create_chunk_empty();

    SpriteChunk* create_chunk(const SpriteAssetChunk& asset);

    void delete_chunk(SpriteChunk* chunk);

    void mark_dirty_chunk(SpriteChunk* chunk);

    // applies queued creates / deletes, writes dirty chunk pixels into their
    // page and uploads every touched page
    void commit_chunks();

    SpriteChunk* get_chunk(SpriteChunkId id);

private:
    void free_chunk(SpriteChunk* chunk);
    void write_chunk_pixels(SpriteChunk* chunk);
    void clear_chunk_pixels(SpriteChunk* chunk);
    void upload_pages();

    void mark_chunk(SpriteChunk* chunk, SpriteChunkState state);

    // only for testing
public:
    ivec3 atlas_index_to_xyz(size_t index) const;

private:
    uint32_t m_chunk_size = 0;
    uint32_t m_atlas_page_size = 0;
    uint32_t m_atlas_page_count = 0;

    FreeList<uint32_t> m_free;

    FreeListChunkAllocator<SpriteChunk> m_sprite_chunk_allocator;
    FreeListChunkAllocator<Color4> m_color_allocator;
    FreeListChunkAllocator<Color4> m_normal_allocator;
    FreeListChunkAllocator<SpriteCellMask> m_mask_allocator;
    FreeListChunkAllocator<float> m_distance_allocator;

    std::unordered_map<SpriteChunk*, SpriteChunkState> m_dirty;

    std::unordered_set<SpriteChunkId> m_alive;

    std::vector<godot::PackedByteArray> m_color_pages;
    std::vector<godot::PackedByteArray> m_mask_pages;
    std::vector<bool> m_page_dirty;

    godot::Ref<godot::Texture2DArray> m_color_texture;
    godot::Ref<godot::Texture2DArray> m_mask_texture;

    // guards alloc / free / dirty marking so sprite commits can run in parallel
    godot::SpinLock m_commit_lock;
};
