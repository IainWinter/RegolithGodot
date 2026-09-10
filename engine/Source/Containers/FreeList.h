#pragma once

#include <godot_cpp/templates/list.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/templates/pair.hpp>
#include <assert.h>

template<typename T>
class FreeList {
public:
    FreeList() = default;

    FreeList(T size) {
        ranges.push_back({0, size});
    }

    T allocate() {
        assert(!ranges.is_empty() && "Out of memory!");

        typename godot::List<godot::Pair<T, T>>::Element* first = ranges.front();
        godot::Pair<T, T>& firstRange = first->get();
        T index = firstRange.first;
        firstRange.first++;

        if (firstRange.first >= firstRange.second) {
            ranges.pop_front();
        }

        return index;
    }

    void deallocate(T index) {
        typename godot::List<godot::Pair<T, T>>::Element* it = ranges.front();
        while (it && index >= it->get().first) {
            if (index < it->get().second) {
                return;
            }
            it = it->next();
        }

        typename godot::List<godot::Pair<T, T>>::Element* newIt;
        if (it) {
            newIt = ranges.insert_before(it, {index, index + 1});
        } else {
            ranges.push_back({index, index + 1});
            newIt = ranges.back();
        }

        typename godot::List<godot::Pair<T, T>>::Element* prev = newIt->prev();
        if (prev && prev->get().second == newIt->get().first) {
            prev->get().second = newIt->get().second;
            ranges.erase(newIt);
            newIt = prev;
        }

        typename godot::List<godot::Pair<T, T>>::Element* next = newIt->next();
        if (next && newIt->get().second == next->get().first) {
            newIt->get().second = next->get().second;
            ranges.erase(next);
        }
    }

    godot::LocalVector<godot::Pair<T, T>> snapshot_ranges() const {
        godot::LocalVector<godot::Pair<T, T>> out;
        for (const godot::Pair<T, T>& r : ranges) {
            out.push_back(r);
        }
        return out;
    }

    void restore_ranges(const godot::LocalVector<godot::Pair<T, T>>& snapshot) {
        ranges.clear();
        for (const godot::Pair<T, T>& r : snapshot) {
            ranges.push_back(r);
        }
    }

private:
    godot::List<godot::Pair<T, T>> ranges;
};
