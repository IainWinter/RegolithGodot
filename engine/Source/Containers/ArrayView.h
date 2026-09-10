#pragma once

#include <cstddef>
#include <assert.h>

// A wrapper around a pointer which checks the bounds
// This does not own the memory
template<typename T>
class ArrayView {
public:
    ArrayView()
        : m_array (nullptr)
        , m_size  (0)
    {}

    ArrayView(T* array, size_t size)
        : m_array (array)
        , m_size  (size)
    {}

    T& operator[](size_t i) {
        assert(i < m_size && "index out of bounds");
        return m_array[i];
    }
    
    const T& operator[](size_t i) const {
        assert(i < m_size && "index out of bounds");
        return m_array[i];
    }

    operator T*() {
        return m_array;
    }

    operator const T*() const {
        return m_array;
    }

    ArrayView<T> operator+(size_t i) const {
        return ArrayView(m_array + i, m_size - i);
    }

    T* data() {
        return m_array;
    }

    const T* data() const {
        return m_array;
    }

    T* ptr() { return m_array; }
    const T* ptr() const { return m_array; }

    size_t size() const {
        return m_size;
    }

private:
    T* m_array;
    size_t m_size;
};