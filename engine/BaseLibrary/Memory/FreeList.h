#pragma once

#include <list>
#include <vector>
#include <utility>
#include <assert.h>

template<typename T>
class FreeList {
public:
    FreeList() = default;

    FreeList(T size) {
        ranges.emplace_back(0, size);
    }

    T allocate() {
        assert(!ranges.empty() && "Out of memory!");

        auto& firstRange = ranges.front();
        T index = firstRange.first;
        firstRange.first++;

        if (firstRange.first >= firstRange.second) {
            ranges.pop_front();
        }

        return index;
    }

    void deallocate(T index) {
        auto it = ranges.begin();
        while (it != ranges.end() && index >= it->first) {
            if (index < it->second) {
                return; // Already allocated
            }
            ++it;
        }

        // Insert new range at the correct position
        auto newIt = ranges.insert(it, {index, index + 1});

        // Merge with previous range if adjacent
        if (newIt != ranges.begin()) {
            auto prev = std::prev(newIt);
            if (prev->second == newIt->first) {
                prev->second = newIt->second;
                ranges.erase(newIt);
                newIt = prev;
            }
        }

        // Merge with next range if adjacent
        auto next = std::next(newIt);
        if (next != ranges.end() && newIt->second == next->first) {
            newIt->second = next->second;
            ranges.erase(next);
        }
    }

    std::vector<std::pair<T, T>> snapshot_ranges() const {
        return std::vector<std::pair<T, T>>(ranges.begin(), ranges.end());
    }

    void restore_ranges(const std::vector<std::pair<T, T>>& snapshot) {
        ranges = std::list<std::pair<T, T>>(snapshot.begin(), snapshot.end());
    }

private:
    std::list<std::pair<T, T>> ranges;
};