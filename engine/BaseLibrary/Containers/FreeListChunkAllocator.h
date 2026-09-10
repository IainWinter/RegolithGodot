#pragma once

#include <godot_cpp/core/memory.hpp>

#include <godot_cpp/templates/local_vector.hpp>

// An allocator which assumes that it is givin valid ids from an external FreeList
template<typename T>
class FreeListChunkAllocator {
public:
    FreeListChunkAllocator() = default;

    FreeListChunkAllocator(size_t chunkTotalSize, size_t blockSize)
        : m_chunkTotalSize (chunkTotalSize)
        , m_blockSize      (blockSize)
    {}

    FreeListChunkAllocator(const FreeListChunkAllocator&) = delete;

    FreeListChunkAllocator(FreeListChunkAllocator&& move) 
        : m_chunkTotalSize (std::move(move.m_chunkTotalSize))
        , m_blockSize      (std::move(move.m_blockSize))
        , m_blocks         (std::move(move.m_blocks))
    {}

    FreeListChunkAllocator& operator=(FreeListChunkAllocator&& move) {
        m_chunkTotalSize = std::move(move.m_chunkTotalSize);
        m_blockSize = std::move(move.m_blockSize);
        m_blocks = std::move(move.m_blocks);
        
        return *this;
    }

    ~FreeListChunkAllocator() {
        for (Block& block : m_blocks) {
            memfree(block.memory);
        }
    }

    template<typename... Args>
    ArrayView<T> allocate(size_t id, Args&&... args) {
        size_t blockId = id / m_blockSize;
        size_t instanceId = id % m_blockSize;

        if (blockId >= m_blocks.size()) {
            allocate_new_block();
        }
        
        Block& block = m_blocks[blockId];

        if (block.memory == nullptr) {
            allocate_existing_block(blockId);
        }

        block.instances += 1;

        T* memory = block.memory + instanceId * m_chunkTotalSize;

        for (size_t i = 0; i < m_chunkTotalSize; i++) {
            new (&memory[i]) T(std::forward<Args>(args)...);
        }

        return ArrayView<T>(memory, m_chunkTotalSize);
    }

    ArrayView<T> allocate_copy(size_t id, ArrayView<const T> copy) {
        ArrayView<T> data  = allocate(id);
        for (size_t i = 0; i < m_chunkTotalSize; i++) {
            data[i] = copy[i];
        }

        return data;
    }

    T* operator[](size_t id) { return at(id); }
    const T* operator[](size_t id) const { return at(id); }

    T* at(size_t id) {
        size_t blockId = id / m_blockSize;
        size_t instanceId = id % m_blockSize;
        if (blockId >= m_blocks.size()) return nullptr;
        Block& block = m_blocks[blockId];
        if (block.memory == nullptr) return nullptr;
        return block.memory + instanceId * m_chunkTotalSize;
    }

    const T* at(size_t id) const {
        size_t blockId = id / m_blockSize;
        size_t instanceId = id % m_blockSize;
        if (blockId >= m_blocks.size()) return nullptr;
        const Block& block = m_blocks[blockId];
        if (block.memory == nullptr) return nullptr;
        return block.memory + instanceId * m_chunkTotalSize;
    }

    void free(size_t id) {
        size_t blockId = id / m_blockSize;
        size_t instanceId = id % m_blockSize;

        Block& block = m_blocks[blockId];
        block.instances -= 1;

        T* memory = block.memory + instanceId * m_chunkTotalSize;

        for (size_t i = 0; i < m_chunkTotalSize; i++) {
            memory[i].~T();
        }

        if (block.instances == 0) {
            free_block(blockId);
        }
    }

private:
    void allocate_new_block() {
        Block block;
        block.memory = static_cast<T*>(memalloc(m_chunkTotalSize * m_blockSize * sizeof(T)));
        block.instances = 0;
        m_blocks.push_back(block);
    }

    void allocate_existing_block(size_t blockId) {
        Block& block = m_blocks[blockId];
        block.memory = static_cast<T*>(memalloc(m_chunkTotalSize * m_blockSize * sizeof(T)));
        block.instances = 0;
    }

    void free_block(size_t blockId) {
        Block& block = m_blocks[blockId];
        memfree(block.memory);
        block.memory = nullptr;
    }

private:
    size_t m_chunkTotalSize;
    size_t m_blockSize;

    struct Block {
        T* memory;
        size_t instances;
    };

    godot::LocalVector<Block> m_blocks;
};