file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS *.cpp)
add_library(engine STATIC ${SOURCES})
target_include_directories(engine PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(engine PUBLIC common)
