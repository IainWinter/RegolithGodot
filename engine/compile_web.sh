#!/usr/bin/env bash
set -e
: "${EMSDK:?set EMSDK to your emsdk root}"
source "$EMSDK/emsdk_env.sh" > /dev/null
cd "$(dirname "$0")"
cmake -S . -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake" -DGODOTCPP_THREADS=OFF
cmake --build build-web
