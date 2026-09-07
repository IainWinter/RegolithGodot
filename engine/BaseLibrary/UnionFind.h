#pragma once

#include <vector>
#include <unordered_map>

#include <mutex>

class UnionFind {
public:
    UnionFind() {}

    bool contains(int x) {
        return x >= 0 && x < (int)parent.size();
    }

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

    std::unordered_map<int, std::vector<int>> get_groups() {
        std::unordered_map<int, std::vector<int>> groups;
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
        rank.resize(new_size, 0);
        for (int i = size; i < new_size; ++i) {
            parent[i] = i;
        }
    }

private:
    std::vector<int> parent;
    std::vector<int> rank;
};