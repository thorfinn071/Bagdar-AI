cmake_minimum_required(VERSION 3.22.1)
project(bagdar_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(BAGDAR_SOURCES vision_guide_native.cpp)

# NCNN integration is optional: if third_party/ncnn libs are present
# (downloaded via tools/ncnn/download_ncnn_android.ps1), the depth
# inference wrapper is compiled in; otherwise it is silently skipped
# and Dart-side code falls back to TFLite or focal-length.
set(NCNN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/ncnn")
set(NCNN_LIB "${NCNN_ROOT}/lib/${ANDROID_ABI}/libncnn.a")

if(EXISTS "${NCNN_LIB}" AND EXISTS "${NCNN_ROOT}/include/net.h")
    message(STATUS "Bagdar: NCNN runtime found for ${ANDROID_ABI}, enabling depth wrapper")
    list(APPEND BAGDAR_SOURCES bagdar_depth_ncnn.cpp)
    set(BAGDAR_HAVE_NCNN ON)
else()
    message(STATUS "Bagdar: NCNN runtime missing for ${ANDROID_ABI}, depth wrapper disabled")
    set(BAGDAR_HAVE_NCNN OFF)
endif()

add_library(bagdar_native SHARED ${BAGDAR_SOURCES})

target_link_libraries(bagdar_native PRIVATE android log)

if(BAGDAR_HAVE_NCNN)
    target_include_directories(bagdar_native PRIVATE "${NCNN_ROOT}/include")
    add_library(ncnn STATIC IMPORTED)
    set_target_properties(ncnn PROPERTIES IMPORTED_LOCATION "${NCNN_LIB}")
    target_link_libraries(bagdar_native PRIVATE ncnn)

    # OpenMP (NCNN expects it for multi-threading).
    find_library(OMP_LIB omp)
    if(OMP_LIB)
        target_link_libraries(bagdar_native PRIVATE ${OMP_LIB})
    endif()

    # Vulkan loader (optional; NCNN works without it but no GPU then).
    find_library(VULKAN_LIB vulkan)
    if(VULKAN_LIB)
        target_link_libraries(bagdar_native PRIVATE ${VULKAN_LIB})
    endif()

    target_compile_definitions(bagdar_native PRIVATE BAGDAR_HAVE_NCNN=1)
endif()
