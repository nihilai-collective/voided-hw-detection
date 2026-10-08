cmake_minimum_required(VERSION 3.24)

project(voided_hw_detection_example LANGUAGES CXX)

include(FetchContent)

FetchContent_Declare(
    voided_hw_detection
    GIT_REPOSITORY https://github.com/nihilai-collective/voided-hw-detection.git
    GIT_TAG main
)
FetchContent_MakeAvailable(voided_hw_detection)

option(EXAMPLE_DETECT_GPU "Detect GPU properties" OFF)

voided_hw_detect_cpu(
    PREFIX EXAMPLE
    HEADER ${CMAKE_CURRENT_BINARY_DIR}/generated/example/cpu_properties.hpp
)

if(EXAMPLE_DETECT_GPU)
    voided_hw_detect_gpu(
        PREFIX EXAMPLE
        NAMESPACE example::hw
        HEADER ${CMAKE_CURRENT_BINARY_DIR}/generated/example/gpu_properties.hpp
    )
endif()

add_executable(example main.cpp)

target_compile_features(example PRIVATE cxx_std_20)

target_include_directories(example PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/generated)

target_compile_definitions(example PRIVATE EXAMPLE_WITH_GPU=$<BOOL:${EXAMPLE_DETECT_GPU}>)
