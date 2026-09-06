#pragma once

#include <vector>
#include <deque>
#include <assert.h>

// Element pointers are always valid
// no deletion
template<typename T>
class StableFlatMap {
public:
    StableFlatMap() = default;

    StableFlatMap(int size) {
        m_map.resize(size, -1);
        m_items.resize(size);
    }

    T& emplace(int key, const T& value) {
        assert(!contains(key));

        if (key >= static_cast<int>(m_map.size())) {
            m_map.resize(key + 1, -1);
        }

        m_map[key] = static_cast<int>(m_items.size());
        m_items.push_back(value);

        return m_items.back();
    }

    T& emplace(int key, T&& value) {
        assert(!contains(key));

        if (key >= static_cast<int>(m_map.size())) {
            m_map.resize(key + 1, -1);
        }

        m_map[key] = static_cast<int>(m_items.size());
        m_items.emplace_back(std::forward<T>(value));

        return m_items.back();
    }

    bool contains(int key) const {
        return key >= 0
            && key < static_cast<int>(m_map.size())
            && m_map[key] != -1;
    }

    T& at(int key) {
        assert(contains(key));
        return m_items[m_map[key]];
    }

    const T& at(int key) const {
        assert(contains(key));
        return m_items[m_map[key]];
    }

    T* try_get(int key) {
        if (key < 0 || key >= static_cast<int>(m_map.size())) {
            return nullptr;
	}

        int index = m_map[key];
        if (index == -1) {
            return nullptr;
	}

        return &m_items[index];
    }

    const T* try_get(int key) const {
        if (key < 0 || key >= static_cast<int>(m_map.size())) {
            return nullptr;
	}

        int index = m_map[key];
        if (index == -1) {
            return nullptr;
	}

        return &m_items[index];
    }

    auto size() const { return m_items.size(); }
    auto begin() { return m_items.begin(); }
    auto begin() const { return m_items.begin(); }
    auto end() { return m_items.end(); }
    auto end() const { return m_items.end(); }

private:
    std::vector<int> m_map;
    std::deque<T> m_items;
};
