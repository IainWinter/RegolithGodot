file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS *.cpp)
add_library(common STATIC ${SOURCES})
target_include_directories(common PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(common PUBLIC base_library)
