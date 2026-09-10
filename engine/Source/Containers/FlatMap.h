#pragma once

#include <godot_cpp/templates/local_vector.hpp>
#include <assert.h>
#include <godot_cpp/templates/pair.hpp>

template<typename T>
class FlatMap {
public:
    FlatMap() = default;

    FlatMap(int size) {
        m_map.resize(size);
        for (uint32_t _i = 0; _i < m_map.size(); _i++) m_map[_i] = -1;
    }

    T& emplace(int key, const T& value) {
        assert(!contains(key));

        if (key >= static_cast<int>(m_map.size())) {
            uint32_t _old = m_map.size();
            m_map.resize(key + 1);
            for (uint32_t _i = _old; _i < m_map.size(); _i++) m_map[_i] = -1;
        }

        m_map[key] = static_cast<int>(m_items.size());
        m_items.push_back(value);
        m_keys.push_back(key);

        return m_items[m_items.size() - 1];
    }

    T& emplace(int key, T&& value) {
        assert(!contains(key));

        if (key >= static_cast<int>(m_map.size())) {
            uint32_t _old = m_map.size();
            m_map.resize(key + 1);
            for (uint32_t _i = _old; _i < m_map.size(); _i++) m_map[_i] = -1;
        }

        m_map[key] = static_cast<int>(m_items.size());
        m_items.push_back({std::forward<T>(value)});
        m_keys.push_back(key);

        return m_items[m_items.size() - 1];
    }

    void erase(int key) {
        assert(contains(key));

        int index_to_remove = m_map[key];
        int last_index = static_cast<int>(m_items.size()) - 1;

        if (index_to_remove != last_index) {
            m_items[index_to_remove] = std::move(m_items[last_index]);
            m_keys[index_to_remove] = m_keys[last_index];

            int moved_key = m_keys[index_to_remove];
            m_map[moved_key] = index_to_remove;
        }

        m_items.remove_at(m_items.size() - 1);
        m_keys.remove_at(m_keys.size() - 1);

        m_map[key] = -1;
    }

    bool contains(int key) const {
        return key >= 0
            && key < static_cast<int>(m_map.size())
            && m_map[key] != -1;
    }

    bool has(int key) const { return contains(key); }

    T& at(int key) {
        assert(contains(key));
        return m_items[m_map[key]];
    }

    const T& at(int key) const {
        assert(contains(key));
        return m_items[m_map[key]];
    }

    T& operator[](int key) { return at(key); }
    const T& operator[](int key) const { return at(key); }

    T get_or(int key, T fallback) const {
        const T* found = try_get(key);
        if (!found) {
            return fallback;
        }

        return *found;
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

    bool try_get(int key, T* out) const {
        if (key < 0 || key >= static_cast<int>(m_map.size())) {
            return false;
	    }

        int index = m_map[key];
        if (index == -1) {
            return false;
	    }

        *out = m_items[index];
        return true;
    }

    void clear() { 
        m_map.clear(); 
        m_items.clear(); 
        m_keys.clear();
    }

    auto size() const { return m_items.size(); }

    class Iterator {
    public:
        using value_type = godot::Pair<int, T&>;
        using reference = value_type;
        using pointer = void;

        Iterator(godot::LocalVector<int>::Iterator k, typename godot::LocalVector<T>::Iterator v)
            : m_key_it(k), m_val_it(v) {}

        reference operator*() const { return { *m_key_it, *m_val_it }; }

        Iterator& operator++() { ++m_key_it; ++m_val_it; return *this; }
        Iterator operator++(int) { auto tmp = *this; ++(*this); return tmp; }

        bool operator==(const Iterator& other) const { return m_key_it == other.m_key_it; }
        bool operator!=(const Iterator& other) const { return !(*this == other); }

    private:
        godot::LocalVector<int>::Iterator m_key_it;
        typename godot::LocalVector<T>::Iterator m_val_it;
    };

    class ConstIterator {
    public:
        using value_type = godot::Pair<int, const T&>;
        using reference = value_type;
        using pointer = void;

        ConstIterator(godot::LocalVector<int>::ConstIterator k, typename godot::LocalVector<T>::ConstIterator v)
            : m_key_it(k), m_val_it(v) {}

        reference operator*() const { return { *m_key_it, *m_val_it }; }

        ConstIterator& operator++() { ++m_key_it; ++m_val_it; return *this; }
        ConstIterator operator++(int) { auto tmp = *this; ++(*this); return tmp; }

        bool operator==(const ConstIterator& other) const { return m_key_it == other.m_key_it; }
        bool operator!=(const ConstIterator& other) const { return !(*this == other); }

    private:
        godot::LocalVector<int>::ConstIterator m_key_it;
        typename godot::LocalVector<T>::ConstIterator m_val_it;
    };

    Iterator begin() { return Iterator(m_keys.begin(), m_items.begin()); }
    Iterator end() { return Iterator(m_keys.end(), m_items.end()); }
    ConstIterator begin() const { return ConstIterator(m_keys.begin(), m_items.begin()); }
    ConstIterator end() const { return ConstIterator(m_keys.end(), m_items.end()); }
    ConstIterator cbegin() const { return ConstIterator(m_keys.begin(), m_items.begin()); }
    ConstIterator cend() const { return ConstIterator(m_keys.end(), m_items.end()); }

    const godot::LocalVector<int>& keys() const { return m_keys; }
    const godot::LocalVector<T>& items() const { return m_items; }
    godot::LocalVector<T>& items() { return m_items; }

private:
    godot::LocalVector<int> m_map;
    godot::LocalVector<int> m_keys;
    godot::LocalVector<T> m_items;
};
