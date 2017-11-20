cmake_minimum_required(VERSION 2.8)

project(CPP-LRU_CACHE)

find_package(Threads REQUIRED)

set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(EXT_PROJECTS_DIR ${PROJECT_SOURCE_DIR}/ext)
add_subdirectory(${EXT_PROJECTS_DIR}/gtest)

enable_testing()

include_directories(
    ${GTEST_INCLUDE_DIRS}
    ${PROJECT_SOURCE_DIR}/include)

add_executable(
    cpp-lru-cache-test
    src/test)

add_dependencies(cpp-lru-cache-test googletest)

target_link_libraries(
    cpp-lru-cache-test
    ${GTEST_LIBS_DIR}/libgtest.a
    ${GTEST_LIBS_DIR}/libgtest_main.a
    ${CMAKE_THREAD_LIBS_INIT})

set_target_properties(cpp-lru-cache-test PROPERTIES
    PREFIX ""
    SUFFIX ""
    COMPILE_FLAGS "-std=c++0x -W -Wall -pedantic")

set(CMAKE_CXX_FLAGS_DEBUG "-O0 -g3")
set(CMAKE_CSS_FLAGS_RELEASE "-03 -g")

add_test(
    NAME cpp-lru-cache-test
    COMMAND cpp-lru-cache-test
)

add_custom_target(check COMMAND ${CMAKE_CTEST_COMMAND} --verbose
    DEPENDS cpp-lru-cache-test)
