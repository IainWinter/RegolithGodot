#include "VectorUtil.h"
#pragma once

#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/templates/hash_map.hpp>

#include <mutex>

class UnionFind {
public:
    UnionFind() {}

    bool contains(int x) {
        return x >= 0 && x < (int)parent.size();
    }

    bool has(int x) { return contains(x); }

    int find(int x) {
        ensure_exists(x);
        
        int root = x;
        while (parent[root] != root) {
            root = parent[root];
        }

        while (parent[x] != root) {
            int next = parent[x];
            parent[x] = root;
            x = next;
        }

        return root;
    }

    int unite(int x, int y) {
        ensure_exists(std::max(x, y));

        int rootX = find(x);
        int rootY = find(y);
        
        if (rootX == rootY) {
            return -1;
        }

        if (rank[rootX] > rank[rootY]) {
            parent[rootY] = rootX;
            return rootY;
        }
        
        if (rank[rootX] < rank[rootY]) {
            parent[rootX] = rootY;
            return rootX;
        }
        
        parent[rootY] = rootX;
        rank[rootX]++;
        return rootY;
    }

    godot::HashMap<int, godot::LocalVector<int>> get_groups() {
        godot::HashMap<int, godot::LocalVector<int>> groups;
        groups.reserve(parent.size());

        for (int i = 0; i < (int)parent.size(); ++i) {
            int root = find(i);
            groups[root].push_back(i);
        }

        return groups;
    }

private:
    void ensure_exists(int x) {
        int size = static_cast<int>(parent.size());
        if (x < size) {
            return;
        }

        int new_size = x + 1;
        parent.resize(new_size);
        vector_fill(rank, new_size,  0);
        for (int i = size; i < new_size; ++i) {
            parent[i] = i;
        }
    }

private:
    godot::LocalVector<int> parent;
    godot::LocalVector<int> rank;
};