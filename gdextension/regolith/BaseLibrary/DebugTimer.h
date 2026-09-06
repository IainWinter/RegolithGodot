#pragma once

#include <chrono>

class DebugTimer {
public:
    DebugTimer() {
        m_start = std::chrono::steady_clock::now();
    }

    float milliseconds() const {
        std::chrono::steady_clock::time_point now = std::chrono::steady_clock::now();
        return std::chrono::duration<float, std::milli>(now - m_start).count();
    }

private:
    std::chrono::steady_clock::time_point m_start;
};