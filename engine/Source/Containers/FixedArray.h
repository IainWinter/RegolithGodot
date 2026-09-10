#pragma once

#include <assert.h>
#include <stddef.h>
#include <initializer_list>

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
        if (m_size != other.m_size) return false;
        for (size_t i = 0; i < m_size; i++) if (!(m_items[i] == other.m_items[i])) return false;
        return true;
    }

    bool operator!=(const FixedArray& other) const {
        return !operator==(other);
    }

    T& at(size_t index) { return m_items[index]; }
    const T& at(size_t index) const { return m_items[index]; }
    T& operator[](size_t index) { return m_items[index]; }
    const T& operator[](size_t index) const { return m_items[index]; }
    T* data() { return m_items; }
    const T* data() const { return m_items; }
    T* begin() { return m_items; }
    const T* begin() const { return m_items; }
    T* end() { return m_items + m_size; }
    const T* end() const { return m_items + m_size; }

private:
    T m_items[Capacity];
    size_t m_size;
};
