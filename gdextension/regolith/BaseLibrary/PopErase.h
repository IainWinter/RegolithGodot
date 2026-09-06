#pragma once

#include <vector>

template<typename T>
void pop_erase(size_t* index, std::vector<T>& vector) {
    if (vector.size() == 1) {
        vector.pop_back();
    }

    else {
        vector.at(*index) = std::move(vector.back());
        vector.pop_back();
        *index -= 1;
    }
}

template<typename A, typename B>
void pop_erase2(size_t* index, std::vector<A>& vectorA, std::vector<B>& vectorB) {
    assert(vectorA.size() == vectorB.size());
    if (vectorA.size() == 1) {
        vectorA.pop_back();
        vectorB.pop_back();
    }

    else {
        vectorA.at(*index) = std::move(vectorA.back());
        vectorA.pop_back();
        vectorB.at(*index) = std::move(vectorB.back());
        vectorB.pop_back();
        *index -= 1;
    }
}

template<typename T>
void pop_erase(int* index, std::vector<T>& vector) {
    size_t i = static_cast<size_t>(*index);
    pop_erase(&i, vector);
    *index = static_cast<int>(i);
}

template<typename T>
T&& pop_erase_keep(size_t* index, std::vector<T>& vector) {
    T item = std::move(vector.at(index));

    if (vector.size() == 1) {
        vector.pop_back();
    }

    else {
        vector.at(*index) = std::move(vector.back());
        vector.pop_back();
        *index -= 1;
    }

    return std::move(item);
}