file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS *.cpp)
add_library(godot_bindings STATIC ${SOURCES})
target_include_directories(godot_bindings PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(godot_bindings PUBLIC engine)
