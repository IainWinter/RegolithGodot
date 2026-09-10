#pragma once

#include <godot_cpp/templates/local_vector.hpp>

template<typename T>
void pop_erase(size_t* index, godot::LocalVector<T>& vector) {
    if (vector.size() == 1) {
        vector.remove_at(vector.size() - 1);
    }

    else {
        vector[*index] = std::move(vector[vector.size() - 1]);
        vector.remove_at(vector.size() - 1);
        *index -= 1;
    }
}

template<typename A, typename B>
void pop_erase2(size_t* index, godot::LocalVector<A>& vectorA, godot::LocalVector<B>& vectorB) {
    assert(vectorA.size() == vectorB.size());
    if (vectorA.size() == 1) {
        vectorA.remove_at(vectorA.size() - 1);
        vectorB.remove_at(vectorB.size() - 1);
    }

    else {
        vectorA[*index] = std::move(vectorA[vectorA.size() - 1]);
        vectorA.remove_at(vectorA.size() - 1);
        vectorB[*index] = std::move(vectorB[vectorB.size() - 1]);
        vectorB.remove_at(vectorB.size() - 1);
        *index -= 1;
    }
}

template<typename T>
void pop_erase(int* index, godot::LocalVector<T>& vector) {
    size_t i = static_cast<size_t>(*index);
    pop_erase(&i, vector);
    *index = static_cast<int>(i);
}

template<typename T>
T&& pop_erase_keep(size_t* index, godot::LocalVector<T>& vector) {
    T item = std::move(vector[index]);

    if (vector.size() == 1) {
        vector.remove_at(vector.size() - 1);
    }

    else {
        vector[*index] = std::move(vector[vector.size() - 1]);
        vector.remove_at(vector.size() - 1);
        *index -= 1;
    }

    return std::move(item);
}