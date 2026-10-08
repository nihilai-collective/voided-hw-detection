# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nihilai Collective Corp
# https://github.com/nihilai-collective/voided-hw-detection
# detector/CMakeLists.txt

cmake_minimum_required(VERSION 3.24)

project(voided_hw_detector LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(VOIDED_HW_DETECTOR_KIND STREQUAL "CPU")
    add_executable(voided_hw_cpu_detector cpu_detector.cpp)

    target_compile_options(voided_hw_cpu_detector PRIVATE
        $<$<AND:$<NOT:$<CXX_COMPILER_ID:MSVC>>,$<NOT:$<STREQUAL:${CMAKE_SYSTEM_PROCESSOR},aarch64>>>:-march=native>
        $<$<AND:$<NOT:$<CXX_COMPILER_ID:MSVC>>,$<STREQUAL:${CMAKE_SYSTEM_PROCESSOR},aarch64>>:-march=armv9-a+sve2>
    )

elseif(VOIDED_HW_DETECTOR_KIND STREQUAL "GPU")
    find_package(CUDAToolkit REQUIRED)

    add_executable(voided_hw_gpu_detector gpu_detector.cpp)

    target_link_libraries(voided_hw_gpu_detector PRIVATE CUDA::cudart)

else()
    message(FATAL_ERROR "VOIDED_HW_DETECTOR_KIND must be CPU or GPU, got '${VOIDED_HW_DETECTOR_KIND}'")
endif()
