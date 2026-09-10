#pragma once

#include "Coordinate/AxisAlignedBox.h"

#include <godot_cpp/templates/local_vector.hpp>

class AxisAlignedAreaTreeIndex {
public:
    struct Node {
        AxisAlignedBox box;
        int item_index = -1; // which can be -1 if it is not a leaf
        int left_index = -1;
        int right_index = -1;
        int parent_index = -1;
    };

public:
    AxisAlignedAreaTreeIndex();

    void insert(const AxisAlignedBox& box, int item_index);

    void query(const AxisAlignedBox& box, godot::LocalVector<int>& out) const;

    void query_ray(godot::Vector2 origin, godot::Vector2 direction, float max_length, godot::LocalVector<int>& out) const;

    const AxisAlignedBox& get_box(int item_index) const;

    const godot::LocalVector<Node>& nodes() const;

    void clear();

private:
    int create_node(const AxisAlignedBox& box, int item_index);

    int insert_recursive(int root_index, int leaf_index);

    void query_recursive(int root_index, const AxisAlignedBox& box, godot::LocalVector<int>& out) const;

    void query_ray_recursive(int root_index, godot::Vector2 origin, godot::Vector2 direction, float max_length, godot::LocalVector<int>& out) const;

    Node& get_node(int index);

private:
    godot::LocalVector<Node> m_nodes;
    int m_root;
};

template<typename T>
class AxisAlignedAreaTree {
public:
    void insert(const AxisAlignedBox& box, const T& item) {
        int index = static_cast<int>(m_items.size());
        m_items.push_back(item);
        m_index.insert(box, index);
    }

    bool overlaps(const AxisAlignedBox& box) const {
        godot::LocalVector<int> o; // make a new function
        query(box, o);
        return o.size() > 0;
    }

    void query(const AxisAlignedBox& box, godot::LocalVector<int>& out) const {
        m_index.query(box, out);
    }

    void query_ray(godot::Vector2 origin, godot::Vector2 direction, float max_length, godot::LocalVector<int>& out) const {
        m_index.query_ray(origin, direction, max_length, out);
    }

    void query_items(const AxisAlignedBox& box, godot::LocalVector<T>& out) const {
        godot::LocalVector<int> index;
        m_index.query(box, index);
        out.reserve(out.size() + index.size());
        for (const int& i : index) {
            out.push_back(m_items[i]);
        }
    }

    void query_ray_items(godot::Vector2 origin, godot::Vector2 direction, float max_length, godot::LocalVector<T>& out) const {
        godot::LocalVector<int> index;
        m_index.query_ray(origin, direction, max_length, index);
        out.reserve(out.size() + index.size());
        for (const int& i : index) {
            out.push_back(m_items[i]);
        }
    }

    const T& get(int index) const {
        return m_items[index];
    }

    const AxisAlignedAreaTreeIndex& index() const {
        return m_index;
    }

    void clear() {
        m_index.clear();
        m_items.clear();
    }

private:
    AxisAlignedAreaTreeIndex m_index;
    godot::LocalVector<T> m_items;
};
