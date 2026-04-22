cmake_minimum_required(VERSION 3.22.1)
project(bagdar_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(bagdar_native SHARED bagdar_native.cpp)

target_link_libraries(bagdar_native PRIVATE android log)
