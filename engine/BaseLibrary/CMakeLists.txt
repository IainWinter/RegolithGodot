file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS *.cpp)
add_library(base_library STATIC ${SOURCES})
target_include_directories(base_library PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(base_library PUBLIC glm godot-cpp)
