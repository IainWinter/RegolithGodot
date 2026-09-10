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
    int blocks_per_page = chunks_per_page() * chunks_per_page();

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

int SpriteChunkPool::atlas_slot_size() const {
    return m_chunk_size + 2 * k_atlas_chunk_padding;
}

int SpriteChunkPool::chunks_per_page() const {
    return m_chunk_size == 0 ? 0 : m_atlas_page_size / atlas_slot_size();
}

size_t SpriteChunkPool::alive_count() const {
    return m_alive.size();
}

bool SpriteChunkPool::is_created() const {
    return m_atlas_page_count > 0;
}

size_t SpriteChunkPool::capacity() const {
    int per_page = chunks_per_page() * chunks_per_page();
    return static_cast<size_t>(per_page) * m_atlas_page_count;
}

SpriteChunk* SpriteChunkPool::create_chunk_empty() {
    m_commit_lock.lock();

    SpriteChunkId id = m_free.allocate();

    godot::Vector3i slot = atlas_index_to_xyz(id);
    godot::Vector3i pixel_offset = godot::Vector3i(slot.x * atlas_slot_size() + k_atlas_chunk_padding, slot.y * atlas_slot_size() + k_atlas_chunk_padding, slot.z);
    godot::Vector3 uvw_offset = godot::Vector3(float(pixel_offset.x) / float(m_atlas_page_size), float(pixel_offset.y) / float(m_atlas_page_size), float(slot.z));

    SpriteChunk* chunk = m_sprite_chunk_allocator.allocate(id).data();
    chunk->id = id;
    chunk->index = 0;
    chunk->color = m_color_allocator.allocate(id, Color4());
    chunk->normal = m_normal_allocator.allocate(id, Color4{128, 128, 255, 255});
    chunk->mask = m_mask_allocator.allocate(id, SpriteCellMaskType_Empty);
    chunk->distance = m_distance_allocator.allocate(id, k_sdf_band_cells);
    chunk->activePixelCount = 0;
    chunk->gridPixelOffset = godot::Vector2i(0, 0);
    chunk->atlasPixelOffset = pixel_offset;
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

    bool has_normal = !asset.normal.is_empty();

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

    uint8_t* color = m_color_pages[z].ptrw();
    uint8_t* mask = m_mask_pages[z].ptrw();

    for (uint32_t row = 0; row < m_chunk_size; row++) {
        size_t dst = static_cast<size_t>(y + row) * m_atlas_page_size + x;
        size_t src = static_cast<size_t>(row) * m_chunk_size;

        memcpy(color + dst * sizeof(Color4), chunk->color.ptr() + src, m_chunk_size * sizeof(Color4));
        memcpy(mask + dst * sizeof(SpriteCellMask), chunk->mask.ptr() + src, m_chunk_size * sizeof(SpriteCellMask));
    }

    m_page_dirty[z] = true;
}

void SpriteChunkPool::clear_chunk_pixels(SpriteChunk* chunk) {
    auto [x, y, z] = unpack3(chunk->atlasPixelOffset);

    uint8_t* color = m_color_pages[z].ptrw();
    uint8_t* mask = m_mask_pages[z].ptrw();

    for (uint32_t row = 0; row < m_chunk_size; row++) {
        size_t dst = static_cast<size_t>(y + row) * m_atlas_page_size + x;

        memset(color + dst * sizeof(Color4), 0, m_chunk_size * sizeof(Color4));
        memset(mask + dst * sizeof(SpriteCellMask), 0, m_chunk_size * sizeof(SpriteCellMask));
    }

    m_page_dirty[z] = true;
}

void SpriteChunkPool::upload_pages() {
    for (uint32_t page = 0; page < m_atlas_page_count; page++) {
        if (!m_page_dirty[page]) {
            continue;
        }

        m_page_dirty[page] = false;

        godot::Ref<godot::Image> color = godot::Image::create_from_data(m_atlas_page_size, m_atlas_page_size, false, godot::Image::FORMAT_RGBA8, m_color_pages[page]);
        godot::Ref<godot::Image> mask = godot::Image::create_from_data(m_atlas_page_size, m_atlas_page_size, false, godot::Image::FORMAT_RG8, m_mask_pages[page]);

        m_color_texture->update_layer(color, page);
        m_mask_texture->update_layer(mask, page);
    }
}

void SpriteChunkPool::mark_chunk(SpriteChunk* chunk, SpriteChunkState state) {
    if (!m_dirty.has(chunk)) {
        m_dirty.insert(chunk, state);
        return;
    }

    SpriteChunkState current = m_dirty[chunk];

    constexpr SpriteChunkState valid[3][3] = {{SpriteChunkState_New, SpriteChunkState_New, SpriteChunkState_Delete},
                                              {SpriteChunkState_Dirty, SpriteChunkState_Dirty, SpriteChunkState_Delete},
                                              {SpriteChunkState_Delete, SpriteChunkState_Delete, SpriteChunkState_Delete}};

    m_dirty[chunk] = valid[current][state];
}

SpriteChunk* SpriteChunkPool::get_chunk(SpriteChunkId id) {
    return m_sprite_chunk_allocator[id];
}

godot::Vector3i SpriteChunkPool::atlas_index_to_xyz(size_t index) const {
    int per_row = chunks_per_page();

    int i = int(index);

    int x = i % per_row;
    int y = (i / per_row) % per_row;
    int z = i / (per_row * per_row);
    return godot::Vector3i(x, y, z);
}
