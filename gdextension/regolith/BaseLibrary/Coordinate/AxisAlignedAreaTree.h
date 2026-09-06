#pragma once

#include "Coordinate/AxisAlignedBox.h"
#include "Serializer/Serialize.h"

#include <vector>

class AxisAlignedAreaTreeIndex {
public:
    struct [[Struct]] Node {
        reflect_friend(Node)

        AxisAlignedBox box;
        int item_index = -1; // which can be -1 if it is not a leaf
        int left_index = -1;
        int right_index = -1;
        int parent_index = -1;
    };

public:
    AxisAlignedAreaTreeIndex();

    void insert(const AxisAlignedBox& box, int item_index);

    void query(const AxisAlignedBox& box, std::vector<int>& out) const;

    void query_ray(vec2 origin, vec2 direction, float max_length, std::vector<int>& out) const;

    const AxisAlignedBox& get_box(int item_index) const;

    const std::vector<Node>& nodes() const;

    void clear();

    void save(OutputSerializer& s) const {
        write_field(m_nodes);
        write_field(m_root);
    }

    void load(InputSerializer& s) {
        read_field(m_nodes);
        read_field(m_root);
    }

private:
    int create_node(const AxisAlignedBox& box, int item_index);

    int insert_recursive(int root_index, int leaf_index);

    void query_recursive(int root_index, const AxisAlignedBox& box, std::vector<int>& out) const;

    void query_ray_recursive(int root_index, vec2 origin, vec2 direction, float max_length, std::vector<int>& out) const;

    Node& get_node(int index);

private:
    std::vector<Node> m_nodes;
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
        std::vector<int> o; // make a new function
        query(box, o);
        return o.size() > 0;
    }

    void query(const AxisAlignedBox& box, std::vector<int>& out) const {
        m_index.query(box, out);
    }

    void query_ray(vec2 origin, vec2 direction, float max_length, std::vector<int>& out) const {
        m_index.query_ray(origin, direction, max_length, out);
    }

    void query_items(const AxisAlignedBox& box, std::vector<T>& out) const {
        std::vector<int> index;
        m_index.query(box, index);
        out.reserve(out.size() + index.size());
        for (const int& i : index) {
            out.push_back(m_items.at(i));
        }
    }

    void query_ray_items(vec2 origin, vec2 direction, float max_length, std::vector<T>& out) const {
        std::vector<int> index;
        m_index.query_ray(origin, direction, max_length, index);
        out.reserve(out.size() + index.size());
        for (const int& i : index) {
            out.push_back(m_items.at(i));
        }
    }

    const T& get(int index) const {
        return m_items.at(index);
    }

    const AxisAlignedAreaTreeIndex& index() const {
        return m_index;
    }

    void clear() {
        m_index.clear();
        m_items.clear();
    }

    void save(OutputSerializer& s) const {
        write_field(m_index);
        write_field(m_items);
    }

    void load(InputSerializer& s) {
        read_field(m_index);
        read_field(m_items);
    }

private:
    AxisAlignedAreaTreeIndex m_index;
    std::vector<T> m_items;
};

