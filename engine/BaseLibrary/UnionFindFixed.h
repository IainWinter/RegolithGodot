#pragma once

#include <vector>

class UnionFindFixed {
public:
    UnionFindFixed() = default;

    UnionFindFixed(int count) {
        reset(count);
    }

    void reset(int count) {
        parent.resize(count);

        for (int i = 0; i < count; i++) {
            parent[i] = i;
        }
    }

    int find(int a) {
        while (parent[a] != a) {
            parent[a] = parent[parent[a]];
            a = parent[a];
        }

        return a;
    }

    void merge(int a, int b) {
        parent[find(a)] = find(b);
    }

private:
    std::vector<int> parent;
};
