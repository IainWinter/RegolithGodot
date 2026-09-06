#include "AxisAlignedAreaTree.h"

#include <godot_cpp/core/error_macros.hpp>

static constexpr int s_empty = -1;

AxisAlignedAreaTreeIndex::AxisAlignedAreaTreeIndex() 
    : m_root (s_empty)
{}

void AxisAlignedAreaTreeIndex::insert(const AxisAlignedBox& box, int item_index) {
    int leaf_index = create_node(box, item_index);
    
    // Only for inserting the first item
    if (m_root == s_empty) {
        m_root = leaf_index;
        return;
    }

    m_root = insert_recursive(m_root, leaf_index);
}

void AxisAlignedAreaTreeIndex::query(const AxisAlignedBox& box, std::vector<int>& out) const {
    query_recursive(m_root, box, out);
}

void AxisAlignedAreaTreeIndex::query_ray(vec2 origin, vec2 direction, float max_length, std::vector<int>& out) const {
    query_ray_recursive(m_root, origin, direction, max_length, out);
}

const AxisAlignedBox& AxisAlignedAreaTreeIndex::get_box(int item_index) const {
    // add a list of boxes instead of this
    for (const Node& node : m_nodes) {
        if (node.item_index == item_index) {
            return node.box;
        }
    }

    CRASH_NOW_MSG("item is not in the tree");

    static const AxisAlignedBox none;
    return none;
}

const std::vector<AxisAlignedAreaTreeIndex::Node>& AxisAlignedAreaTreeIndex::nodes() const {
    return m_nodes;
}

void AxisAlignedAreaTreeIndex::clear() {
    m_nodes.clear();
    m_root = s_empty;
}

int AxisAlignedAreaTreeIndex::create_node(const AxisAlignedBox& box, int item_index) {
    Node node{};
    node.box = box;
    node.item_index = item_index;

    m_nodes.push_back(node);
    return static_cast<int>(m_nodes.size() - 1);
}

int AxisAlignedAreaTreeIndex::insert_recursive(int root_index, int leaf_index) {
    Node* current = &get_node(root_index);

    if (current->item_index != s_empty) {
        // create_node may reallocate m_nodes, so grab the box by value first
        AxisAlignedBox combined = current->box.combine_box(get_node(leaf_index).box);
        int parent_index = create_node(combined, s_empty);

        Node& parent = get_node(parent_index);
        parent.left_index = root_index;
        parent.right_index = leaf_index;

        get_node(root_index).parent_index = parent_index;
        get_node(leaf_index).parent_index = parent_index;

        return parent_index;
    }

    int left_index = current->left_index;
    int right_index = current->right_index;

    // copy boxes by value, insert_recursive reallocates m_nodes
    AxisAlignedBox leaf_box = get_node(leaf_index).box;
    AxisAlignedBox left_box = get_node(left_index).box;
    AxisAlignedBox right_box = get_node(right_index).box;

    float left_area_increase = left_box.combine_box(leaf_box).area() - left_box.area();
    float right_area_increase = right_box.combine_box(leaf_box).area() - right_box.area();

    if (left_area_increase < right_area_increase) {
        int new_left_index = insert_recursive(left_index, leaf_index);
        current = &get_node(root_index);
        current->left_index = new_left_index;
        current->box = get_node(new_left_index).box.combine_box(right_box);
    }

    else {
        int new_right_index = insert_recursive(right_index, leaf_index);
        current = &get_node(root_index);
        current->right_index = new_right_index;
        current->box = get_node(new_right_index).box.combine_box(left_box);
    }

    return root_index;
}

void AxisAlignedAreaTreeIndex::query_recursive(int root_index, const AxisAlignedBox& box, std::vector<int>& out) const {
    if (root_index == s_empty) {
        return;
    }

    const Node& current = m_nodes[root_index];

    if (!current.box.intersects_box(box)) {
        return;
    }

    if (current.item_index == s_empty) {
        query_recursive(current.left_index, box, out);
        query_recursive(current.right_index, box, out);
        return;
    } 

    out.push_back(current.item_index);
}

void AxisAlignedAreaTreeIndex::query_ray_recursive(int root_index, vec2 origin, vec2 direction, float max_length, std::vector<int>& out) const {
    if (root_index == s_empty) {
        return;
    }

    const Node& current = m_nodes[root_index];

    if (!current.box.intersects_ray(origin, direction, max_length)) {
        return;
    }

    if (current.item_index == s_empty) {
        query_ray_recursive(current.left_index, origin, direction, max_length, out);
        query_ray_recursive(current.right_index, origin, direction, max_length, out);
        return;
    } 

    out.push_back(current.item_index);
}

AxisAlignedAreaTreeIndex::Node& AxisAlignedAreaTreeIndex::get_node(int index) {
    return m_nodes.at(index);
}