#pragma once

#include <array>
#include <assert.h>
#include <stddef.h>

// todo make constexpr?

template<typename T, size_t Capacity>
class FixedArray {
public:
    FixedArray() 
        : m_size (0)
    {}

    FixedArray(std::initializer_list<T> list) 
        : m_size (0)
    {
        for (const auto& t : list) {
            push_back(t);
        }
    }

    void push_back(const T& item) { 
        assert(m_size < Capacity && "FixedArray out of capacity");
        m_items[m_size++] = item; 
    }

    void emplace_back(T&& item) { 
        assert(m_size < Capacity && "FixedArray out of capacity");
        m_items[m_size++] = std::move(item); 
    }

    void pop_back() {
        m_items[--m_size].~T();
    }

    void clear() {
        m_size = 0;
    }

    size_t size() const { 
        return m_size; 
    }

    bool operator==(const FixedArray& other) const { 
        return m_size == other.m_size 
            && m_items == other.m_items; 
    }

    bool operator!=(const FixedArray& other) const { 
        return !operator==(other); 
    }

    auto at(size_t index) { return m_items.at(index); }
    auto at(size_t index) const { return m_items.at(index); }
    auto data() { return m_items.data(); }
    auto data() const { return m_items.data(); }
    auto begin() { return m_items.begin(); }
    auto begin() const { return m_items.begin(); }
    auto end() { return m_items.begin() + m_size; }
    auto end() const { return m_items.begin() + m_size; }

private:
    std::array<T, Capacity> m_items;
    size_t m_size;
};