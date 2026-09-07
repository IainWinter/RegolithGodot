#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DGODOTCPP_USE_HOT_RELOAD=ON
cmake --build build
