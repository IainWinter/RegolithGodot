cmake_minimum_required(VERSION 3.30)

set(GODOTCPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Thirdparty/godot-cpp" CACHE PATH "godot-cpp checkout")

set(CMAKE_PROJECT_regolith_INCLUDE ${GODOTCPP_DIR}/cmake/emsdkHack.cmake)

project(regolith CXX)

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
add_subdirectory(Thirdparty/glm)
add_subdirectory(BaseLibrary)
add_subdirectory(Common)
add_subdirectory(Engine)
add_subdirectory(GodotClasses)

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

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/regolith_stub.cpp "")
add_library(regolith SHARED ${CMAKE_CURRENT_BINARY_DIR}/regolith_stub.cpp)

target_link_libraries(regolith PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,godot_bindings>"
)

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)

set_target_properties(regolith PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PDB_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
    PREFIX "lib"
    SUFFIX "${OUTPUT_SUFFIX}"
    OUTPUT_NAME "regolith${GODOTCPP_SUFFIX}"
)
