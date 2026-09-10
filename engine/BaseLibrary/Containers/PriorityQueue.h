#pragma once

#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/templates/sort_array.hpp>

template <typename T, typename Comparator>
class PriorityQueue {
public:
    uint32_t size() const { return m_data.size(); }
    bool is_empty() const { return m_data.is_empty(); }

    void push(const T& value) {
        m_data.push_back(value);
        godot::SortArray<T, Comparator> sorter;
        sorter.push_heap(0, m_data.size() - 1, 0, value, m_data.ptr());
    }

    const T& top() const {
        return m_data[0];
    }

    void pop() {
        godot::SortArray<T, Comparator> sorter;
        sorter.pop_heap(0, m_data.size(), m_data.ptr());
        m_data.remove_at(m_data.size() - 1);
    }

private:
    godot::LocalVector<T> m_data;
};
