#pragma once

#include <chrono>

// writes how long a scope took, milliseconds
struct ScopeMs {
    float& out;
    std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();

    ~ScopeMs() {
        out = std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - start).count();
    }
};
