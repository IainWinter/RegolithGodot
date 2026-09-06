#include "SpriteChunkPool.h"

#include "Constants.h"
#include "Math/MathUtil.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <string.h>

SpriteChunkPool::SpriteChunkPool(int chunk_size, int atlas_page_size, int atlas_page_count) {
    create(chunk_size, atlas_page_size, atlas_page_count);
}

void SpriteChunkPool::create(int chunk_size, int atlas_page_size, int atlas_page_count) {
    m_chunk_size = chunk_size;
    m_atlas_page_size = atlas_page_size;
    m_atlas_page_count = atlas_page_count;

    int total_chunk_size = m_chunk_size * m_chunk_size;
    int blocks_per_page = (m_atlas_page_size / m_chunk_size) * (m_atlas_page_size / m_chunk_size);

    m_free = FreeList<uint32_t>(blocks_per_page * m_atlas_page_count);

    m_sprite_chunk_allocator = FreeListChunkAllocator<SpriteChunk>(1, blocks_per_page);
    m_color_allocator = FreeListChunkAllocator<Color4>(total_chunk_size, blocks_per_page);
    m_normal_allocator = FreeListChunkAllocator<Color4>(total_chunk_size, blocks_per_page);
    m_mask_allocator = FreeListChunkAllocator<SpriteCellMask>(total_chunk_size, blocks_per_page);
    m_distance_allocator = FreeListChunkAllocator<float>(total_chunk_size, blocks_per_page);

    size_t page_pixels = static_cast<size_t>(m_atlas_page_size) * m_atlas_page_size;

    godot::TypedArray<godot::Image> color_images;
    godot::TypedArray<godot::Image> mask_images;

    for (uint32_t page = 0; page < m_atlas_page_count; page++) {
        godot::PackedByteArray color;
        color.resize(page_pixels * sizeof(Color4));
        color.fill(0);

        godot::PackedByteArray mask;
        mask.resize(page_pixels * sizeof(SpriteCellMask));
        mask.fill(0);

        color_images.push_back(godot::Image::create_from_data(m_atlas_page_size, m_atlas_page_size, false, godot::Image::FORMAT_RGBA8, color));
        mask_images.push_back(godot::Image::create_from_data(m_atlas_page_size, m_atlas_page_size, false, godot::Image::FORMAT_RG8, mask));

        m_color_pages.push_back(std::move(color));
        m_mask_pages.push_back(std::move(mask));
        m_page_dirty.push_back(false);
    }

    m_color_texture.instantiate();
    m_color_texture->create_from_images(color_images);

    m_mask_texture.instantiate();
    m_mask_texture->create_from_images(mask_images);
}

godot::Ref<godot::Texture2DArray> SpriteChunkPool::color_texture() const {
    return m_color_texture;
}

godot::Ref<godot::Texture2DArray> SpriteChunkPool::mask_texture() const {
    return m_mask_texture;
}

int SpriteChunkPool::chunk_size() const {
    return m_chunk_size;
}

int SpriteChunkPool::atlas_page_size() const {
    return m_atlas_page_size;
}

int SpriteChunkPool::atlas_page_count() const {
    return m_atlas_page_count;
}

size_t SpriteChunkPool::alive_count() const {
    return m_alive.size();
}

bool SpriteChunkPool::is_created() const {
    return m_atlas_page_count > 0;
}

size_t SpriteChunkPool::capacity() const {
    if (m_chunk_size == 0) {
        return 0;
    }

    int per_page = (m_atlas_page_size / m_chunk_size) * (m_atlas_page_size / m_chunk_size);
    return static_cast<size_t>(per_page) * m_atlas_page_count;
}

SpriteChunk* SpriteChunkPool::create_chunk_empty() {
    m_commit_lock.lock();

    SpriteChunkId id = m_free.allocate();

    int chunks_per_page = m_atlas_page_size / m_chunk_size;

    ivec3 atlas_offset = atlas_index_to_xyz(id);
    vec3 uvw_offset = vec3(vec2(atlas_offset) / float(chunks_per_page), float(atlas_offset.z));

    SpriteChunk* chunk = m_sprite_chunk_allocator.allocate(id).data();
    chunk->id = id;
    chunk->index = 0;
    chunk->color = m_color_allocator.allocate(id, Color4());
    chunk->normal = m_normal_allocator.allocate(id, Color4{128, 128, 255, 255});
    chunk->mask = m_mask_allocator.allocate(id, SpriteCellMaskType_Empty);
    chunk->distance = m_distance_allocator.allocate(id, k_sdf_band_cells);
    chunk->activePixelCount = 0;
    chunk->gridPixelOffset = ivec2(0);
    chunk->atlasPixelOffset = atlas_offset * ivec3(m_chunk_size, m_chunk_size, 1);
    chunk->uvwOffset = uvw_offset;

    m_alive.insert(id);

    mark_chunk(chunk, SpriteChunkState_New);

    m_commit_lock.unlock();

    return chunk;
}

SpriteChunk* SpriteChunkPool::create_chunk(const SpriteAssetChunk& asset) {
    SpriteChunk* chunk = create_chunk_empty();
    chunk->index = asset.index;
    chunk->gridPixelOffset = asset.gridPixelOffset;
    chunk->activePixelCount = asset.activePixelCount;

    bool has_normal = !asset.normal.empty();

    for (int i = 0; i < k_cells_per_chunk_total; i++) {
        SpriteCellMask mask(asset.mask[i]);

        if (mask.is_core_type()) {
            mask.set_emissive(true);
        }

        chunk->color[i] = asset.color[i];
        chunk->mask[i] = mask;
        chunk->normal[i] = has_normal ? asset.normal[i] : Color4{128, 128, 255, 255};
    }

    return chunk;
}

void SpriteChunkPool::delete_chunk(SpriteChunk* chunk) {
    m_commit_lock.lock();
    mark_chunk(chunk, SpriteChunkState_Delete);
    m_commit_lock.unlock();
}

void SpriteChunkPool::mark_dirty_chunk(SpriteChunk* chunk) {
    m_commit_lock.lock();
    mark_chunk(chunk, SpriteChunkState_Dirty);
    m_commit_lock.unlock();
}

void SpriteChunkPool::commit_chunks() {
    for (const auto& [chunk, state] : m_dirty) {
        switch (state) {
            case SpriteChunkState_New:
            case SpriteChunkState_Dirty: {
                write_chunk_pixels(chunk);
                break;
            }
            case SpriteChunkState_Delete: {
                free_chunk(chunk);
                break;
            }
        }
    }

    m_dirty.clear();

    upload_pages();
}

void SpriteChunkPool::free_chunk(SpriteChunk* chunk) {
    clear_chunk_pixels(chunk);

    m_alive.erase(chunk->id);
    m_free.deallocate(chunk->id);
    m_color_allocator.free(chunk->id);
    m_normal_allocator.free(chunk->id);
    m_mask_allocator.free(chunk->id);
    m_distance_allocator.free(chunk->id);
    m_sprite_chunk_allocator.free(chunk->id);
}

void SpriteChunkPool::write_chunk_pixels(SpriteChunk* chunk) {
    auto [x, y, z] = unpack3(chunk->atlasPixelOffset);

    uint8_t* color = m_color_pages.at(z).ptrw();
    uint8_t* mask = m_mask_pages.at(z).ptrw();

    for (uint32_t row = 0; row < m_chunk_size; row++) {
        size_t dst = static_cast<size_t>(y + row) * m_atlas_page_size + x;
        size_t src = static_cast<size_t>(row) * m_chunk_size;

        memcpy(color + dst * sizeof(Color4), chunk->color.data() + src, m_chunk_size * sizeof(Color4));
        memcpy(mask + dst * sizeof(SpriteCellMask), chunk->mask.data() + src, m_chunk_size * sizeof(SpriteCellMask));
    }

    m_page_dirty.at(z) = true;
}

void SpriteChunkPool::clear_chunk_pixels(SpriteChunk* chunk) {
    auto [x, y, z] = unpack3(chunk->atlasPixelOffset);

    uint8_t* color = m_color_pages.at(z).ptrw();
    uint8_t* mask = m_mask_pages.at(z).ptrw();

    for (uint32_t row = 0; row < m_chunk_size; row++) {
        size_t dst = static_cast<size_t>(y + row) * m_atlas_page_size + x;

        memset(color + dst * sizeof(Color4), 0, m_chunk_size * sizeof(Color4));
        memset(mask + dst * sizeof(SpriteCellMask), 0, m_chunk_size * sizeof(SpriteCellMask));
    }

    m_page_dirty.at(z) = true;
}

void SpriteChunkPool::upload_pages() {
    for (uint32_t page = 0; page < m_atlas_page_count; page++) {
        if (!m_page_dirty.at(page)) {
            continue;
        }

        m_page_dirty.at(page) = false;

        godot::Ref<godot::Image> color = godot::Image::create_from_data(m_atlas_page_size, m_atlas_page_size, false, godot::Image::FORMAT_RGBA8, m_color_pages.at(page));
        godot::Ref<godot::Image> mask = godot::Image::create_from_data(m_atlas_page_size, m_atlas_page_size, false, godot::Image::FORMAT_RG8, m_mask_pages.at(page));

        m_color_texture->update_layer(color, page);
        m_mask_texture->update_layer(mask, page);
    }
}

void SpriteChunkPool::mark_chunk(SpriteChunk* chunk, SpriteChunkState state) {
    auto itr = m_dirty.find(chunk);
    if (itr == m_dirty.end()) {
        m_dirty.emplace_hint(itr, chunk, state);
        return;
    }

    // [ New ] --------> [ Delete ]
    //              |
    // [ Dirty ] ---^

    const SpriteChunkState& current = itr->second;

    constexpr SpriteChunkState valid[3][3] = {{SpriteChunkState_New, SpriteChunkState_New, SpriteChunkState_Delete},
                                              {SpriteChunkState_Dirty, SpriteChunkState_Dirty, SpriteChunkState_Delete},
                                              {SpriteChunkState_Delete, SpriteChunkState_Delete, SpriteChunkState_Delete}};

    SpriteChunkState next = valid[current][state];
    itr->second = next;
}

SpriteChunk* SpriteChunkPool::get_chunk(SpriteChunkId id) {
    return m_sprite_chunk_allocator.at(id);
}

ivec3 SpriteChunkPool::atlas_index_to_xyz(size_t index) const {
    int chunks_per_page = m_atlas_page_size / m_chunk_size;

    int i = int(index);

    int x = i % chunks_per_page;
    int y = (i / chunks_per_page) % chunks_per_page;
    int z = i / (chunks_per_page * chunks_per_page);
    return ivec3(x, y, z);
}
