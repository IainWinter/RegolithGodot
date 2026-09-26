cmake_minimum_required(VERSION 3.30)

set(GODOTCPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Thirdparty/godot-cpp" CACHE PATH "godot-cpp checkout")

set(CMAKE_PROJECT_regolith_INCLUDE ${GODOTCPP_DIR}/cmake/emsdkHack.cmake)

project(regolith C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(GODOTCPP_API_VERSION "4.7" CACHE STRING "")
set(GODOTCPP_TARGET "template_debug" CACHE STRING "")
set(GODOTCPP_USE_STATIC_CPP OFF CACHE BOOL "")
set(GODOTCPP_DISABLE_EXCEPTIONS OFF CACHE BOOL "")
set(GODOTCPP_USE_HOT_RELOAD ON CACHE BOOL "")

if (EMSCRIPTEN)
    set(GODOTCPP_USE_HOT_RELOAD OFF CACHE BOOL "" FORCE)
    set(GODOTCPP_DISABLE_EXCEPTIONS ON CACHE BOOL "" FORCE)
    set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "" FORCE)
endif()

if (MSVC)
    add_compile_definitions(NOMINMAX _CRT_SECURE_NO_WARNINGS)
    add_compile_options(/MP /wd5030 /bigobj /utf-8)
else()
    add_compile_options(-Wno-attributes -Wno-unknown-attributes)
endif()

add_subdirectory(${GODOTCPP_DIR} godot-cpp)

if (EMSCRIPTEN)
    set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../extensions/web")
    set(OUTPUT_SUFFIX ".wasm")
elseif (APPLE)
    set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../extensions/macos")
    set(OUTPUT_SUFFIX "${CMAKE_SHARED_LIBRARY_SUFFIX}")
elseif (UNIX)
    set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../extensions/linux")
    set(OUTPUT_SUFFIX "${CMAKE_SHARED_LIBRARY_SUFFIX}")
else()
    set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../extensions/windows")
    set(OUTPUT_SUFFIX "${CMAKE_SHARED_LIBRARY_SUFFIX}")
endif()

# lua 5.4 as plain c, longjmp errors stay inside lua frames, our c functions
# never raise across c++ objects
file(GLOB LUA_SOURCES CONFIGURE_DEPENDS Thirdparty/lua/*.c)
add_library(lua STATIC ${LUA_SOURCES})
target_include_directories(lua PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/Thirdparty/lua)
set_target_properties(lua PROPERTIES POSITION_INDEPENDENT_CODE ON)

if (MSVC)
    target_compile_options(lua PRIVATE /wd4244 /wd4267 /wd4310 /wd4324 /wd4702)
endif()

file(GLOB_RECURSE REGOLITH_SOURCES CONFIGURE_DEPENDS Source/*.cpp)
add_library(regolith SHARED ${REGOLITH_SOURCES})

target_include_directories(regolith PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/Source
    ${CMAKE_CURRENT_SOURCE_DIR}/Source/Godot
)

target_link_libraries(regolith PRIVATE godot-cpp lua)

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

set_target_properties(regolith PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PDB_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PREFIX "lib"
    SUFFIX "${OUTPUT_SUFFIX}"
    OUTPUT_NAME "regolith${GODOTCPP_SUFFIX}"
)
