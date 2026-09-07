#pragma once

#include <array>

template<typename T>
class StaticArray {
public:
    StaticArray(size_t size) {
        m_array = new T[size];
        m_size = size;
    }

    ~StaticArray() {
        delete[] m_array;
    }

    size_t size() const { 
        return m_size; 
    }

    T& at(size_t index) { return m_array[index]; }
    const T& at(size_t index) const { return m_array[index]; }
    T* begin() { return m_array; }
    T* begin() const { return m_array; }
    T* end() { return m_array + m_size; }
    T* end() const { return m_array + m_size; }

private:
    T* m_array;
    size_t m_size;
};