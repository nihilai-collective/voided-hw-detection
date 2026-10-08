# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nihilai Collective Corp
# https://github.com/nihilai-collective/voided-hw-detection
# cmake/voided_hw_detection.cmake

include_guard(GLOBAL)

set(VOIDED_HW_DETECTOR_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../detector" CACHE INTERNAL "")

option(VOIDED_HW_DETECT "Run the voided-hw-detection detectors at configure time" ON)

set(VOIDED_HW_CPU_PROPERTIES
    THREAD_COUNT            4
    CPU_L1_CACHE_SIZE       32768
    CPU_L2_CACHE_SIZE       262144
    CPU_L3_CACHE_SIZE       8388608
    HAS_LZCNT               0
    HAS_POPCNT              0
    HAS_BMI1                0
    HAS_BMI2                0
    HAS_CLMUL               0
    HAS_FMA                 0
    HAS_F16C                0
    HAS_AVX                 0
    HAS_AVX2                0
    HAS_AVX512F             0
    HAS_AVX512BW            0
    HAS_AVX512VBMI2         0
    HAS_AVX512              0
    HAS_NEON                0
    HAS_SVE2                0
    SVE2_VECTOR_BITS        0
    CPU_INSTRUCTION_MASK    0
    CACHE INTERNAL ""
)

set(VOIDED_HW_CPU_DERIVED_PROPERTIES
    CPU_ARCH_INDEX
    CPU_ALIGNMENT
    CPU_ARG_ALIGNMENT
    CACHE INTERNAL ""
)

set(VOIDED_HW_GPU_PROPERTIES
    MEMORY_BANDWIDTH_BYTES      0
    FP32_THROUGHPUT_BYTES       0
    MEMORY_BUS_WIDTH            0
    MEMORY_CLOCK_RATE           0
    CORE_CLOCK_RATE             0
    SM_COUNT                    16
    TOTAL_THREADS               16384
    GPU_ALIGNMENT               256
    MAX_THREADS_PER_SM          1024
    MAX_THREADS_PER_BLOCK       1024
    MAX_REGS_PER_THREAD         255
    MAX_REGS_PER_BLOCK          65536
    MAX_REGS_PER_SM             65536
    WARP_SIZE                   32
    CACHE_LINE_SIZE             128
    GPU_L2_CACHE_SIZE           2097152
    MAX_PERSISTING_L2_BYTES     1310720
    SHARED_MEM_PER_BLOCK        49152
    MAX_GRID_SIZE_X             2147483647
    MAX_GRID_SIZE_Y             65535
    MAX_GRID_SIZE_Z             65535
    MAJOR_COMPUTE_CAPABILITY    9
    MINOR_COMPUTE_CAPABILITY    0
    GPU_ARCH_INDEX              0
    HAS_CUDA_9                  1
    HAS_CUDA_10                 0
    HAS_CUDA_11                 0
    HAS_CUDA_12                 0
    CACHE INTERNAL ""
)

set(VOIDED_HW_GPU_DERIVED_PROPERTIES
    GPU_ARG_ALIGNMENT
    CUDA_ARCHITECTURES
    CACHE INTERNAL ""
)

function(_voided_hw_run_detector KIND ENABLED OUTPUT_VARIABLE)
    set(cached_output_variable VOIDED_HW_${KIND}_DETECTOR_OUTPUT)
    set(${OUTPUT_VARIABLE} "" PARENT_SCOPE)

    if(NOT VOIDED_HW_DETECT OR NOT ENABLED)
        return()
    endif()

    if(DEFINED CACHE{${cached_output_variable}})
        set(${OUTPUT_VARIABLE} "$CACHE{${cached_output_variable}}" PARENT_SCOPE)
        return()
    endif()

    if(CMAKE_CROSSCOMPILING)
        message(WARNING "voided-hw-detection: cross-compiling, skipping ${KIND} detection and using fallbacks for unset properties.")
        return()
    endif()

    string(TOLOWER "${KIND}" kind_lower)
    set(build_dir "${CMAKE_BINARY_DIR}/_voided_hw_detection/${kind_lower}")

    set(configure_args
        -S "${VOIDED_HW_DETECTOR_SOURCE_DIR}"
        -B "${build_dir}"
        -G "${CMAKE_GENERATOR}"
        -DCMAKE_BUILD_TYPE=Release
        -DVOIDED_HW_DETECTOR_KIND=${KIND}
    )
    if(CMAKE_GENERATOR_PLATFORM)
        list(APPEND configure_args -A "${CMAKE_GENERATOR_PLATFORM}")
    endif()
    if(CMAKE_GENERATOR_TOOLSET)
        list(APPEND configure_args -T "${CMAKE_GENERATOR_TOOLSET}")
    endif()
    if(CMAKE_CXX_COMPILER AND NOT CMAKE_GENERATOR MATCHES "^Visual Studio")
        list(APPEND configure_args "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}")
    endif()

    execute_process(
        COMMAND "${CMAKE_COMMAND}" ${configure_args}
        RESULT_VARIABLE configure_result
        OUTPUT_VARIABLE configure_log
        ERROR_VARIABLE configure_log
    )
    if(NOT configure_result EQUAL 0)
        message(WARNING "voided-hw-detection: failed to configure the ${KIND} detector, using fallbacks.\n${configure_log}")
        set(${cached_output_variable} "" CACHE INTERNAL "")
        return()
    endif()

    execute_process(
        COMMAND "${CMAKE_COMMAND}" --build "${build_dir}" --config Release
        RESULT_VARIABLE build_result
        OUTPUT_VARIABLE build_log
        ERROR_VARIABLE build_log
    )
    if(NOT build_result EQUAL 0)
        message(WARNING "voided-hw-detection: failed to build the ${KIND} detector, using fallbacks.\n${build_log}")
        set(${cached_output_variable} "" CACHE INTERNAL "")
        return()
    endif()

    find_program(detector_executable
        NAMES voided_hw_${kind_lower}_detector
        PATHS "${build_dir}" "${build_dir}/Release"
        NO_DEFAULT_PATH
        NO_CACHE
    )
    if(NOT detector_executable)
        message(WARNING "voided-hw-detection: could not locate the built ${KIND} detector, using fallbacks.")
        set(${cached_output_variable} "" CACHE INTERNAL "")
        return()
    endif()

    execute_process(
        COMMAND "${detector_executable}"
        RESULT_VARIABLE run_result
        OUTPUT_VARIABLE detector_output
        ERROR_VARIABLE detector_error
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(NOT run_result EQUAL 0 OR NOT detector_output MATCHES "${KIND}_SUCCESS=1")
        message(WARNING "voided-hw-detection: the ${KIND} detector failed (exit code ${run_result}), using fallbacks.\n${detector_output}\n${detector_error}")
        set(detector_output "")
    endif()

    string(REPLACE "\r" "" detector_output "${detector_output}")
    string(REPLACE "\n" ";" detector_output "${detector_output}")

    set(${cached_output_variable} "${detector_output}" CACHE INTERNAL "")
    set(${OUTPUT_VARIABLE} "${detector_output}" PARENT_SCOPE)
endfunction()

function(_voided_hw_set_owned VARIABLE VALUE DOC)
    set(last_variable _VOIDED_HW_LAST_${VARIABLE})
    if(DEFINED CACHE{${last_variable}})
        set(owned_value "$CACHE{${last_variable}}")
    else()
        set(owned_value "${VALUE}")
    endif()
    if(DEFINED ${VARIABLE})
        if(NOT "${${VARIABLE}}" STREQUAL "${owned_value}")
            set_property(GLOBAL APPEND PROPERTY VOIDED_HW_OVERRIDDEN ${VARIABLE})
            return()
        endif()
    endif()
    set(${VARIABLE} "${VALUE}" CACHE STRING "${DOC}" FORCE)
    set(${last_variable} "${VALUE}" CACHE INTERNAL "")
endfunction()

function(_voided_hw_apply_properties KIND PREFIX DETECTOR_OUTPUT)
    foreach(line IN LISTS DETECTOR_OUTPUT)
        string(STRIP "${line}" line)
        if(line MATCHES "^([A-Z0-9_]+)=([0-9]+)$")
            set(detected_${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
        endif()
    endforeach()

    set(properties ${VOIDED_HW_${KIND}_PROPERTIES})
    list(LENGTH properties property_count)
    math(EXPR last_index "${property_count} - 1")

    foreach(name_index RANGE 0 ${last_index} 2)
        math(EXPR fallback_index "${name_index} + 1")
        list(GET properties ${name_index} name)
        list(GET properties ${fallback_index} fallback)

        if(DEFINED detected_${name})
            _voided_hw_set_owned(${PREFIX}_${name} "${detected_${name}}" "${name} (detected by voided-hw-detection)")
        else()
            _voided_hw_set_owned(${PREFIX}_${name} "${fallback}" "${name} (voided-hw-detection fallback)")
        endif()
    endforeach()

    if(DETECTOR_OUTPUT STREQUAL "")
        set(${PREFIX}_${KIND}_DETECTED FALSE CACHE INTERNAL "")
    else()
        set(${PREFIX}_${KIND}_DETECTED TRUE CACHE INTERNAL "")
    endif()
endfunction()

function(_voided_hw_default_instruction_set PREFIX OUTPUT_VARIABLE)
    if(${PREFIX}_HAS_AVX512F AND ${PREFIX}_HAS_AVX512BW)
        set(${OUTPUT_VARIABLE} AVX512 PARENT_SCOPE)
    elseif(${PREFIX}_HAS_AVX2)
        set(${OUTPUT_VARIABLE} AVX2 PARENT_SCOPE)
    elseif(${PREFIX}_HAS_AVX)
        set(${OUTPUT_VARIABLE} AVX PARENT_SCOPE)
    elseif(${PREFIX}_HAS_SVE2 AND ${PREFIX}_SVE2_VECTOR_BITS GREATER 0)
        set(${OUTPUT_VARIABLE} SVE2 PARENT_SCOPE)
    elseif(${PREFIX}_HAS_NEON)
        set(${OUTPUT_VARIABLE} NEON PARENT_SCOPE)
    else()
        set(${OUTPUT_VARIABLE} NONE PARENT_SCOPE)
    endif()
endfunction()

function(_voided_hw_derive_cpu_properties PREFIX)
    _voided_hw_default_instruction_set(${PREFIX} default_instruction_set)
    _voided_hw_set_owned(${PREFIX}_SIMD_TIER ${default_instruction_set} "Instruction set tier to build for: AVX512, AVX2, AVX, SVE2, NEON or NONE")
    if(DEFINED CACHE{${PREFIX}_SIMD_TIER})
        set_property(CACHE ${PREFIX}_SIMD_TIER PROPERTY STRINGS AVX512 AVX2 AVX SVE2 NEON NONE)
    endif()

    set(instruction_set "${${PREFIX}_SIMD_TIER}")
    if(NOT instruction_set MATCHES "^(AVX512|AVX2|AVX|SVE2|NEON|NONE)$")
        message(FATAL_ERROR "voided-hw-detection: ${PREFIX}_SIMD_TIER must be AVX512, AVX2, AVX, SVE2, NEON or NONE, got '${instruction_set}'")
    endif()

    if(instruction_set STREQUAL "AVX512")
        set(arch_index 2)
        set(alignment 64)
    elseif(instruction_set STREQUAL "AVX2")
        set(arch_index 1)
        set(alignment 32)
    elseif(instruction_set STREQUAL "AVX")
        set(arch_index 0)
        set(alignment 16)
    elseif(instruction_set STREQUAL "SVE2")
        set(arch_index 2)
        if(${PREFIX}_SVE2_VECTOR_BITS GREATER 128)
            math(EXPR alignment "${${PREFIX}_SVE2_VECTOR_BITS} / 8")
        else()
            set(alignment 16)
        endif()
    elseif(instruction_set STREQUAL "NEON")
        set(arch_index 1)
        set(alignment 16)
    else()
        set(arch_index 0)
        set(alignment 16)
    endif()

    _voided_hw_set_owned(${PREFIX}_CPU_ARCH_INDEX ${arch_index} "CPU_ARCH_INDEX (derived by voided-hw-detection)")
    _voided_hw_set_owned(${PREFIX}_CPU_ALIGNMENT ${alignment} "CPU_ALIGNMENT (derived by voided-hw-detection)")
    _voided_hw_set_owned(${PREFIX}_CPU_ARG_ALIGNMENT 64 "CPU_ARG_ALIGNMENT (derived by voided-hw-detection)")

    _voided_hw_select_instructions(${PREFIX})
endfunction()

function(_voided_hw_select_instructions PREFIX)
    set(instruction_set "${${PREFIX}_SIMD_TIER}")
    set(mask "${${PREFIX}_CPU_INSTRUCTION_MASK}")
    set(cascade FALSE)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        set(cascade TRUE)
    endif()

    if(instruction_set STREQUAL "SVE2")
        math(EXPR selected "(${mask} & 0x8) | 0x100" OUTPUT_FORMAT DECIMAL)
        set(selected_vector_bits ${${PREFIX}_SVE2_VECTOR_BITS})
    elseif(instruction_set STREQUAL "NEON")
        math(EXPR selected "(${mask} & 0x8) | 0x10" OUTPUT_FORMAT DECIMAL)
        set(selected_vector_bits 0)
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        set(selected 0)
        set(selected_vector_bits 0)
    else()
        math(EXPR selected "${mask} & 0xF" OUTPUT_FORMAT DECIMAL)
        set(selected_vector_bits 0)
        if(instruction_set STREQUAL "AVX512")
            set(kept_bits "0x80 | 0x40 | 0x20")
            set(cascaded_bits "0x40 | 0x20")
        elseif(instruction_set STREQUAL "AVX2")
            set(kept_bits "0x40 | 0x20")
            set(cascaded_bits "0x20")
        elseif(instruction_set STREQUAL "AVX")
            set(kept_bits "0x20")
            set(cascaded_bits "0")
        else()
            set(kept_bits "0")
            set(cascaded_bits "0")
        endif()
        math(EXPR selected "${selected} | (${mask} & (${kept_bits}))" OUTPUT_FORMAT DECIMAL)
        if(cascade)
            math(EXPR selected "${selected} | (${cascaded_bits})" OUTPUT_FORMAT DECIMAL)
        endif()
    endif()

    set(${PREFIX}_SELECTED_CPU_INSTRUCTIONS ${selected} CACHE INTERNAL "")
    set(${PREFIX}_SELECTED_SVE2_VECTOR_BITS ${selected_vector_bits} CACHE INTERNAL "")
endfunction()

function(_voided_hw_manual_instruction_output PREFIX OUTPUT_VARIABLE)
    string(REPLACE "|" ";" parts "${${PREFIX}_CPU_INSTRUCTIONS}")
    set(mask 0)
    foreach(part IN LISTS parts)
        string(STRIP "${part}" part)
        math(EXPR mask "${mask} | (${part})" OUTPUT_FORMAT DECIMAL)
    endforeach()

    set(output "CPU_INSTRUCTION_MASK=${mask}" "HAS_BMI2=0" "HAS_FMA=0" "HAS_F16C=0")
    foreach(feature_bit IN ITEMS LZCNT=0x1 POPCNT=0x2 BMI1=0x4 CLMUL=0x8 NEON=0x10 AVX=0x20 AVX2=0x40 AVX512=0x80 AVX512F=0x80 AVX512BW=0x80 AVX512VBMI2=0x80 SVE2=0x100)
        string(REPLACE "=" ";" feature_bit "${feature_bit}")
        list(GET feature_bit 0 feature)
        list(GET feature_bit 1 bit)
        math(EXPR present "${mask} & ${bit}")
        if(present)
            list(APPEND output "HAS_${feature}=1")
        else()
            list(APPEND output "HAS_${feature}=0")
        endif()
    endforeach()
    if(NOT DEFINED ${PREFIX}_SVE2_VECTOR_BITS)
        list(APPEND output "SVE2_VECTOR_BITS=0")
    endif()

    set(${OUTPUT_VARIABLE} "${output}" PARENT_SCOPE)
endfunction()

function(_voided_hw_derive_gpu_properties PREFIX)
    _voided_hw_set_owned(${PREFIX}_GPU_ARG_ALIGNMENT 16 "GPU_ARG_ALIGNMENT (derived by voided-hw-detection)")
    _voided_hw_set_owned(${PREFIX}_CUDA_ARCHITECTURES "${${PREFIX}_MAJOR_COMPUTE_CAPABILITY}${${PREFIX}_MINOR_COMPUTE_CAPABILITY}" "CUDA architectures (derived by voided-hw-detection)")
endfunction()

function(_voided_hw_cpu_flags PREFIX MSVC_OUTPUT GNU_OUTPUT)
    set(instruction_set "${${PREFIX}_SIMD_TIER}")
    set(msvc_flags "")
    set(gnu_flags "")

    if(instruction_set STREQUAL "AVX512")
        list(APPEND msvc_flags /arch:AVX512)
        list(APPEND gnu_flags -mavx512f -mavx512bw)
        if(${PREFIX}_HAS_AVX512VBMI2)
            list(APPEND gnu_flags -mavx512vbmi2)
        endif()
    elseif(instruction_set STREQUAL "AVX2")
        list(APPEND msvc_flags /arch:AVX2)
    elseif(instruction_set STREQUAL "AVX")
        list(APPEND msvc_flags /arch:AVX)
    endif()

    if(instruction_set MATCHES "^(AVX512|AVX2)$")
        list(APPEND gnu_flags -mavx2 -mavx -msse4.2)
        foreach(feature_flag IN ITEMS FMA=-mfma F16C=-mf16c)
            string(REPLACE "=" ";" feature_flag "${feature_flag}")
            list(GET feature_flag 0 feature)
            list(GET feature_flag 1 flag)
            if(${PREFIX}_HAS_${feature})
                list(APPEND gnu_flags ${flag})
            endif()
        endforeach()
    elseif(instruction_set STREQUAL "AVX")
        list(APPEND gnu_flags -mavx)
    endif()

    if(NOT instruction_set MATCHES "^(SVE2|NEON)$" AND NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        foreach(feature_flag IN ITEMS LZCNT=-mlzcnt POPCNT=-mpopcnt BMI1=-mbmi BMI2=-mbmi2 CLMUL=-mpclmul)
            string(REPLACE "=" ";" feature_flag "${feature_flag}")
            list(GET feature_flag 0 feature)
            list(GET feature_flag 1 flag)
            if(${PREFIX}_HAS_${feature})
                list(APPEND gnu_flags ${flag})
            endif()
        endforeach()
    endif()

    if(instruction_set STREQUAL "SVE2")
        if(${PREFIX}_HAS_CLMUL)
            list(APPEND gnu_flags -march=armv9-a+sve2+aes)
        else()
            list(APPEND gnu_flags -march=armv9-a+sve2)
        endif()
        if(${PREFIX}_SVE2_VECTOR_BITS GREATER 0)
            list(APPEND gnu_flags -msve-vector-bits=${${PREFIX}_SVE2_VECTOR_BITS})
        endif()
    endif()

    set(${MSVC_OUTPUT} "${msvc_flags}" PARENT_SCOPE)
    set(${GNU_OUTPUT} "${gnu_flags}" PARENT_SCOPE)
endfunction()

function(_voided_hw_setup_cpu_target PREFIX TARGET_NAME CUDA_HOST_FLAGS NO_DEFINITIONS)
    _voided_hw_cpu_flags(${PREFIX} msvc_flags gnu_flags)

    if(WIN32 AND NOT MINGW)
        set(cuda_host_flags ${msvc_flags})
    else()
        set(cuda_host_flags ${gnu_flags})
    endif()

    set(simd_flags "")
    foreach(flag IN LISTS msvc_flags)
        list(APPEND simd_flags "$<$<OR:$<COMPILE_LANG_AND_ID:CXX,MSVC>,$<COMPILE_LANG_AND_ID:C,MSVC>>:${flag}>")
    endforeach()
    foreach(flag IN LISTS gnu_flags)
        list(APPEND simd_flags "$<$<OR:$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang,IntelLLVM>,$<COMPILE_LANG_AND_ID:C,GNU,Clang,AppleClang,IntelLLVM>>:${flag}>")
    endforeach()
    if(CUDA_HOST_FLAGS)
        foreach(flag IN LISTS cuda_host_flags)
            list(APPEND simd_flags "$<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler=${flag}>")
        endforeach()
    endif()

    set(instruction_set "${${PREFIX}_SIMD_TIER}")
    set(simd_definitions "")
    foreach(tier IN ITEMS SVE2 AVX512 AVX2 AVX NEON)
        if(instruction_set STREQUAL tier)
            list(APPEND simd_definitions ${PREFIX}_${tier}=1)
        else()
            list(APPEND simd_definitions ${PREFIX}_${tier}=0)
        endif()
    endforeach()
    if(instruction_set STREQUAL "NONE")
        list(APPEND simd_definitions ${PREFIX}_FALLBACK=1)
    else()
        list(APPEND simd_definitions ${PREFIX}_FALLBACK=0)
    endif()

    set(${PREFIX}_SIMD_FLAGS "${simd_flags}" CACHE INTERNAL "")
    set(${PREFIX}_SIMD_DEFINITIONS "${simd_definitions}" CACHE INTERNAL "")
    set(${PREFIX}_INSTRUCTION_SET_NAME "${instruction_set}" CACHE INTERNAL "")

    if(NOT TARGET ${TARGET_NAME})
        add_library(${TARGET_NAME} INTERFACE)
    endif()
    set_property(TARGET ${TARGET_NAME} PROPERTY INTERFACE_COMPILE_OPTIONS "${simd_flags}")
    if(NO_DEFINITIONS)
        set_property(TARGET ${TARGET_NAME} PROPERTY INTERFACE_COMPILE_DEFINITIONS "")
    else()
        set_property(TARGET ${TARGET_NAME} PROPERTY INTERFACE_COMPILE_DEFINITIONS "${simd_definitions};${PREFIX}_INSTRUCTION_SET_NAME=\"${instruction_set}\"")
    endif()
endfunction()

function(_voided_hw_setup_gpu_target PREFIX TARGET_NAME)
    set(cuda_definitions "")
    set(selected FALSE)
    foreach(version IN ITEMS 12 11 10 9)
        if(NOT selected AND ${PREFIX}_HAS_CUDA_${version})
            list(APPEND cuda_definitions ${PREFIX}_CUDA_${version}=1)
            set(selected TRUE)
        else()
            list(APPEND cuda_definitions ${PREFIX}_CUDA_${version}=0)
        endif()
    endforeach()

    set(${PREFIX}_CUDA_DEFINITIONS "${cuda_definitions}" CACHE INTERNAL "")

    if(NOT TARGET ${TARGET_NAME})
        add_library(${TARGET_NAME} INTERFACE)
    endif()
    set_property(TARGET ${TARGET_NAME} PROPERTY INTERFACE_COMPILE_DEFINITIONS "${cuda_definitions}")
endfunction()

function(_voided_hw_generate_header KIND PREFIX HEADER NAMESPACE)
    string(TOLOWER "${KIND}" kind_lower)

    if(${PREFIX}_${KIND}_DETECTED)
        set(detected_value 1)
        set(detected_bool true)
    else()
        set(detected_value 0)
        set(detected_bool false)
    endif()

    set(macros "#define ${PREFIX}_${KIND}_DETECTED ${detected_value}\n")
    set(members "\t\tstatic constexpr bool detected = ${detected_bool};\n")

    set(properties ${VOIDED_HW_${KIND}_PROPERTIES})
    list(LENGTH properties property_count)
    math(EXPR last_index "${property_count} - 1")

    set(names "")
    foreach(name_index RANGE 0 ${last_index} 2)
        list(GET properties ${name_index} name)
        list(APPEND names ${name})
    endforeach()
    list(APPEND names ${VOIDED_HW_${KIND}_DERIVED_PROPERTIES})

    foreach(name IN LISTS names)
        set(value "${${PREFIX}_${name}}")
        string(TOLOWER "${name}" member)

        string(APPEND macros "#define ${PREFIX}_${name} ${value}\n")

        if(name MATCHES "^HAS_")
            if(value)
                string(APPEND members "\t\tstatic constexpr bool ${member} = true;\n")
            else()
                string(APPEND members "\t\tstatic constexpr bool ${member} = false;\n")
            endif()
        else()
            string(APPEND members "\t\tstatic constexpr uint64_t ${member} = ${value}ull;\n")
        endif()
    endforeach()

    if(KIND STREQUAL "CPU")
        string(APPEND macros
            "\n"
            "#define ${PREFIX}_ISA_LZCNT (1u << 0)\n"
            "#define ${PREFIX}_ISA_POPCNT (1u << 1)\n"
            "#define ${PREFIX}_ISA_BMI1 (1u << 2)\n"
            "#define ${PREFIX}_ISA_CLMUL (1u << 3)\n"
            "#define ${PREFIX}_ISA_NEON (1u << 4)\n"
            "#define ${PREFIX}_ISA_AVX (1u << 5)\n"
            "#define ${PREFIX}_ISA_AVX2 (1u << 6)\n"
            "#define ${PREFIX}_ISA_AVX512 (1u << 7)\n"
            "#define ${PREFIX}_ISA_SVE2 (1u << 8)\n"
            "#define ${PREFIX}_CPU_INSTRUCTIONS ${${PREFIX}_SELECTED_CPU_INSTRUCTIONS}\n"
            "#define ${PREFIX}_CHECK_FOR_INSTRUCTION(x) ((${PREFIX}_CPU_INSTRUCTIONS & (x)) != 0)\n"
            "\n"
            "#if ${PREFIX}_CHECK_FOR_INSTRUCTION(${PREFIX}_ISA_NEON) && ${PREFIX}_CHECK_FOR_INSTRUCTION(${PREFIX}_ISA_SVE2)\n"
            "\t#error \"${PREFIX}_ISA_NEON and ${PREFIX}_ISA_SVE2 are mutually exclusive backends.\"\n"
            "#endif\n"
            "#if ${PREFIX}_CHECK_FOR_INSTRUCTION(${PREFIX}_ISA_SVE2) && ${PREFIX}_SVE2_VECTOR_BITS == 0\n"
            "\t#error \"${PREFIX}_ISA_SVE2 is selected but ${PREFIX}_SVE2_VECTOR_BITS is 0.\"\n"
            "#endif\n"
        )
        string(APPEND members "\t\tstatic constexpr uint64_t cpu_instructions = ${${PREFIX}_SELECTED_CPU_INSTRUCTIONS}ull;\n")
    endif()

    get_filename_component(header_name "${HEADER}" NAME)

    file(CONFIGURE OUTPUT "${HEADER}" CONTENT
"/*
 * Generated by voided-hw-detection - https://github.com/nihilai-collective/voided-hw-detection
 * ${header_name}
 */
#pragma once

#include <cstdint>

${macros}
namespace ${NAMESPACE} {

\tstruct ${kind_lower}_properties {
${members}\t};

}
" @ONLY)
endfunction()

function(_voided_hw_detect KIND)
    cmake_parse_arguments(PARSE_ARGV 1 arg "CUDA_HOST_FLAGS;NO_DEFINITIONS" "PREFIX;HEADER;NAMESPACE;TEMPLATE;TARGET" "")
    string(TOLOWER "${KIND}" kind_lower)
    if(NOT arg_PREFIX)
        message(FATAL_ERROR "voided_hw_detect_${kind_lower} requires PREFIX")
    endif()
    if(arg_TEMPLATE AND NOT arg_HEADER)
        message(FATAL_ERROR "voided-hw-detection: TEMPLATE requires HEADER")
    endif()

    string(TOLOWER "${arg_PREFIX}" prefix_lower)
    if(NOT arg_TARGET)
        set(arg_TARGET voided_hw_${prefix_lower}_${kind_lower})
    endif()

    option(${arg_PREFIX}_DETECT_${KIND} "Run the voided-hw-detection ${KIND} detector for ${arg_PREFIX}; OFF uses fallbacks and manually set values" ON)

    set_property(GLOBAL PROPERTY VOIDED_HW_OVERRIDDEN "")

    _voided_hw_run_detector(${KIND} "${${arg_PREFIX}_DETECT_${KIND}}" detector_output)

    if(KIND STREQUAL "CPU" AND DEFINED ${arg_PREFIX}_CPU_INSTRUCTIONS)
        _voided_hw_manual_instruction_output(${arg_PREFIX} manual_output)
        list(APPEND detector_output ${manual_output})
        set_property(GLOBAL APPEND PROPERTY VOIDED_HW_OVERRIDDEN ${arg_PREFIX}_CPU_INSTRUCTIONS)
    endif()
    _voided_hw_apply_properties(${KIND} ${arg_PREFIX} "${detector_output}")

    if(KIND STREQUAL "CPU")
        _voided_hw_derive_cpu_properties(${arg_PREFIX})
        _voided_hw_setup_cpu_target(${arg_PREFIX} ${arg_TARGET} "${arg_CUDA_HOST_FLAGS}" "${arg_NO_DEFINITIONS}")
    else()
        _voided_hw_derive_gpu_properties(${arg_PREFIX})
        _voided_hw_setup_gpu_target(${arg_PREFIX} ${arg_TARGET})
    endif()

    if(NOT TARGET voided_hw::${prefix_lower}_${kind_lower})
        add_library(voided_hw::${prefix_lower}_${kind_lower} ALIAS ${arg_TARGET})
    endif()

    if(arg_TEMPLATE)
        configure_file("${arg_TEMPLATE}" "${arg_HEADER}" @ONLY)
    elseif(arg_HEADER)
        if(NOT arg_NAMESPACE)
            set(arg_NAMESPACE ${prefix_lower})
        endif()
        _voided_hw_generate_header(${KIND} ${arg_PREFIX} "${arg_HEADER}" ${arg_NAMESPACE})
    endif()

    get_property(overridden GLOBAL PROPERTY VOIDED_HW_OVERRIDDEN)
    if(overridden)
        list(JOIN overridden ", " overridden)
        message(STATUS "voided-hw-detection [${arg_PREFIX}] ${KIND}: using manually set ${overridden}")
    endif()
endfunction()

function(voided_hw_detect_cpu)
    _voided_hw_detect(CPU ${ARGN})
    cmake_parse_arguments(PARSE_ARGV 0 arg "CUDA_HOST_FLAGS;NO_DEFINITIONS" "PREFIX;HEADER;NAMESPACE;TEMPLATE;TARGET" "")

    set(features "")
    foreach(feature IN ITEMS LZCNT POPCNT BMI1 BMI2 CLMUL FMA F16C AVX AVX2 AVX512F AVX512BW AVX512VBMI2 NEON SVE2)
        if(${arg_PREFIX}_HAS_${feature})
            list(APPEND features ${feature})
        endif()
    endforeach()
    list(JOIN features " " features)

    message(STATUS "voided-hw-detection [${arg_PREFIX}] CPU: ${${arg_PREFIX}_SIMD_TIER}, ${${arg_PREFIX}_THREAD_COUNT} threads, L1 ${${arg_PREFIX}_CPU_L1_CACHE_SIZE}B, L2 ${${arg_PREFIX}_CPU_L2_CACHE_SIZE}B, L3 ${${arg_PREFIX}_CPU_L3_CACHE_SIZE}B, alignment ${${arg_PREFIX}_CPU_ALIGNMENT}, instructions ${${arg_PREFIX}_SELECTED_CPU_INSTRUCTIONS}, detected ${${arg_PREFIX}_CPU_DETECTED}")
    message(STATUS "voided-hw-detection [${arg_PREFIX}] CPU features: ${features}")
endfunction()

function(voided_hw_detect_gpu)
    _voided_hw_detect(GPU ${ARGN})
    cmake_parse_arguments(PARSE_ARGV 0 arg "" "PREFIX;HEADER;NAMESPACE;TEMPLATE;TARGET" "")

    message(STATUS "voided-hw-detection [${arg_PREFIX}] GPU: ${${arg_PREFIX}_SM_COUNT} SMs, ${${arg_PREFIX}_TOTAL_THREADS} total threads, compute ${${arg_PREFIX}_MAJOR_COMPUTE_CAPABILITY}.${${arg_PREFIX}_MINOR_COMPUTE_CAPABILITY}, detected ${${arg_PREFIX}_GPU_DETECTED}")
endfunction()
