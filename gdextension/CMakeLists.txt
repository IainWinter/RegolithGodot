cmake_minimum_required(VERSION 3.30)

set(GODOTCPP_DIR "C:/dev/Source/Packages/godot-cpp-master" CACHE PATH "godot-cpp checkout")

# emscripten has no shared libraries as cmake knows them, godot-cpp's hack turns them on
set(CMAKE_PROJECT_regolith_INCLUDE ${GODOTCPP_DIR}/cmake/emsdkHack.cmake)

project(regolith CXX)
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "")
set(GODOTCPP_TARGET "template_debug" CACHE STRING "")
set(GODOTCPP_USE_STATIC_CPP OFF CACHE BOOL "")
set(GODOTCPP_DISABLE_EXCEPTIONS OFF CACHE BOOL "")
set(GODOTCPP_USE_HOT_RELOAD ON CACHE BOOL "")

if (EMSCRIPTEN)
    set(GODOTCPP_USE_HOT_RELOAD OFF CACHE BOOL "" FORCE)
    set(GODOTCPP_DISABLE_EXCEPTIONS ON CACHE BOOL "" FORCE)

    # at -O3 the side module traps with "function signature mismatch" in
    # D_METHOD as soon as the extension registers its classes, -O2 runs fine
    set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "" FORCE)
endif()

add_subdirectory(${GODOTCPP_DIR} godot-cpp)

file(GLOB_RECURSE REGOLITH_SOURCES CONFIGURE_DEPENDS regolith/*.cpp src/*.cpp)

add_library(regolith SHARED ${REGOLITH_SOURCES})

target_include_directories(regolith PRIVATE
    regolith/BaseLibrary
    regolith/Common
    regolith/Engine
    third_party
    src
)

target_compile_definitions(regolith PRIVATE
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
    GLM_ENABLE_EXPERIMENTAL
)

if (MSVC)
    target_compile_options(regolith PRIVATE /MP /wd5030 /bigobj /utf-8)
else()
    target_compile_options(regolith PRIVATE -Wno-attributes -Wno-unknown-attributes)
endif()

if (EMSCRIPTEN)
    set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../bin/web")
    set(OUTPUT_SUFFIX ".wasm")
else()
    set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../bin/windows")
    set(OUTPUT_SUFFIX "${CMAKE_SHARED_LIBRARY_SUFFIX}")
endif()

target_link_libraries(regolith PRIVATE godot-cpp)

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

set_target_properties(regolith PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
    LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PDB_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PREFIX "lib"
    SUFFIX "${OUTPUT_SUFFIX}"
    OUTPUT_NAME "regolith${GODOTCPP_SUFFIX}"
)
