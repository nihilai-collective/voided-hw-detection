<p align="center"><img src="./Logo.png?raw=true" width="350"/></p>

Detect CPU and GPU hardware properties at **CMake configure time** and use them as **compile-time constants** in C++.

At configure time, voided-hw-detection builds and runs a small probe program for the CPU and, if you ask for it, the GPU. It then gives you:

- **CMake cache variables** for every detected property (`<PREFIX>_THREAD_COUNT`, `<PREFIX>_HAS_AVX2`, `<PREFIX>_SM_COUNT`, ...)
- **An INTERFACE target** that carries the right SIMD compiler flags and preprocessor definitions
- **An optional generated header** with `#define` macros and a `constexpr` struct, so you can use `static_assert` and `if constexpr` on the hardware

If detection fails, for example because you are cross-compiling, there is no CUDA toolkit, or there is no GPU, every property falls back to a sensible default. You can also override any value by hand.

---

## Table of Contents

- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [API](#api)
  - [`voided_hw_detect_cpu`](#voided_hw_detect_cpu)
  - [`voided_hw_detect_gpu`](#voided_hw_detect_gpu)
- [CPU Properties](#cpu-properties)
- [GPU Properties](#gpu-properties)
- [SIMD Tier Selection](#simd-tier-selection)
- [Generated Header](#generated-header)
- [Targets, Flags and Definitions](#targets-flags-and-definitions)
- [Overriding Values](#overriding-values)
- [Options](#options)
- [Caching and Re-detection](#caching-and-re-detection)
- [Cross-Compiling and Fallbacks](#cross-compiling-and-fallbacks)
- [Platform Support](#platform-support)
- [Repository Layout](#repository-layout)
- [License](#license)

---

## Requirements

- CMake **3.24+**
- A C++20 compiler (MSVC, GCC, Clang, AppleClang or IntelLLVM) to build the probes
- For GPU detection: the **CUDA Toolkit** and an NVIDIA GPU visible as device `0`

---

## Quick Start

```cmake
cmake_minimum_required(VERSION 3.24)
project(my_project LANGUAGES CXX)

include(FetchContent)
FetchContent_Declare(
    voided_hw_detection
    GIT_REPOSITORY https://github.com/nihilai-collective/voided-hw-detection.git
    GIT_TAG main
)
FetchContent_MakeAvailable(voided_hw_detection)

voided_hw_detect_cpu(
    PREFIX MYPROJ
    HEADER ${CMAKE_CURRENT_BINARY_DIR}/generated/myproj/cpu_properties.hpp
)

add_executable(my_app main.cpp)
target_compile_features(my_app PRIVATE cxx_std_20)
target_include_directories(my_app PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/generated)
target_link_libraries(my_app PRIVATE voided_hw::myproj_cpu)
```

```cpp
#include <myproj/cpu_properties.hpp>

static_assert(myproj::cpu_properties::thread_count >= 1);

int main() {
    if constexpr (MYPROJ_CHECK_FOR_INSTRUCTION(MYPROJ_ISA_AVX2)) {
        // AVX2 path
    } else {
        // scalar path
    }
}
```

You can also vendor the repository and `include(path/to/cmake/voided_hw_detection.cmake)` directly.

A full working example is in [example/](example/). It covers both CPU and GPU detection (turn the GPU part on with `-DEXAMPLE_DETECT_GPU=ON`).

---

## API

### `voided_hw_detect_cpu`

```cmake
voided_hw_detect_cpu(
    PREFIX     <prefix>              # required
    [HEADER    <path>]               # write a generated header here
    [NAMESPACE <ns>]                 # C++ namespace for the header (default: lowercase prefix)
    [TEMPLATE  <path>]               # use your own configure_file template instead (requires HEADER)
    [TARGET    <name>]               # INTERFACE target name (default: voided_hw_<prefix>_cpu)
    [CUDA_HOST_FLAGS]                # also forward SIMD flags to nvcc via -Xcompiler
    [NO_DEFINITIONS]                 # don't attach compile definitions to the target
)
```

### `voided_hw_detect_gpu`

```cmake
voided_hw_detect_gpu(
    PREFIX     <prefix>              # required
    [HEADER    <path>]
    [NAMESPACE <ns>]                 # may be nested, e.g. myproj::hw
    [TEMPLATE  <path>]
    [TARGET    <name>]               # default: voided_hw_<prefix>_gpu
)
```

Each call:

1. Runs the matching probe, or reuses its cached result
2. Sets a `<PREFIX>_<NAME>` cache variable for every property, using the detected value or the fallback
3. Works out the derived properties
4. Creates an INTERFACE target plus an alias `voided_hw::<prefix>_<kind>` (for example `voided_hw::myproj_cpu`)
5. Generates the header, if you passed `HEADER`
6. Prints a status summary

`PREFIX` namespaces everything, so several projects in one build can each run detection with their own prefixes.

---

## CPU Properties

| Name | Fallback | Description |
|---|---|---|
| `THREAD_COUNT` | 4 | `std::thread::hardware_concurrency()` |
| `CPU_L1_CACHE_SIZE` | 32768 | L1 data cache, bytes |
| `CPU_L2_CACHE_SIZE` | 262144 | L2 cache, bytes |
| `CPU_L3_CACHE_SIZE` | 8388608 | L3 cache, bytes |
| `HAS_LZCNT` | 0 | x86 LZCNT |
| `HAS_POPCNT` | 0 | x86 POPCNT |
| `HAS_BMI1` / `HAS_BMI2` | 0 | x86 BMI1 / BMI2 |
| `HAS_CLMUL` | 0 | x86 PCLMULQDQ or ARM PMULL |
| `HAS_FMA` | 0 | x86 FMA3 |
| `HAS_F16C` | 0 | x86 F16C |
| `HAS_AVX` / `HAS_AVX2` | 0 | Requires OS YMM state support (XCR0) |
| `HAS_AVX512F` / `HAS_AVX512BW` / `HAS_AVX512VBMI2` | 0 | Requires OS ZMM state support (XCR0) |
| `HAS_AVX512` | 0 | Set only when F, BW **and** VBMI2 are all present |
| `HAS_NEON` | 0 | ARM Advanced SIMD |
| `HAS_SVE2` | 0 | ARM SVE2 |
| `SVE2_VECTOR_BITS` | 0 | SVE vector length in bits, when SVE2 is present |
| `CPU_INSTRUCTION_MASK` | 0 | Raw bitmask of detected ISA bits (see below) |

**Derived properties**

| Name | Description |
|---|---|
| `SIMD_TIER` | Selected tier: `AVX512`, `AVX2`, `AVX`, `SVE2`, `NEON` or `NONE` (you can override it) |
| `CPU_ARCH_INDEX` | Index of the tier within its family (AVX=0, AVX2=1, AVX512=2; NONE=0, NEON=1, SVE2=2) |
| `CPU_ALIGNMENT` | Vector alignment for the tier: 64 / 32 / 16, or `SVE2_VECTOR_BITS / 8` for wide SVE2 |
| `CPU_ARG_ALIGNMENT` | 64 |

**Instruction bits** (as `<PREFIX>_ISA_*` in the header):

| Bit | Value |
|---|---|
| `LZCNT` | `0x001` |
| `POPCNT` | `0x002` |
| `BMI1` | `0x004` |
| `CLMUL` | `0x008` |
| `NEON` | `0x010` |
| `AVX` | `0x020` |
| `AVX2` | `0x040` |
| `AVX512` | `0x080` |
| `SVE2` | `0x100` |

---

## GPU Properties

All values come from the CUDA runtime for device `0`.

| Name | Fallback | Description |
|---|---|---|
| `MEMORY_BANDWIDTH_BYTES` | 0 | Estimated peak bandwidth, bytes/s (`mem clock × bus width × 2`) |
| `FP32_THROUGHPUT_BYTES` | 0 | Estimated FP32 throughput × 4 bytes |
| `MEMORY_BUS_WIDTH` | 0 | Bits |
| `MEMORY_CLOCK_RATE` | 0 | kHz |
| `CORE_CLOCK_RATE` | 0 | kHz |
| `SM_COUNT` | 16 | Streaming multiprocessors |
| `TOTAL_THREADS` | 16384 | `maxThreadsPerSM × SM_COUNT` |
| `GPU_ALIGNMENT` | 256 | max(texture, surface alignment, 256) |
| `MAX_THREADS_PER_SM` | 1024 | |
| `MAX_THREADS_PER_BLOCK` | 1024 | |
| `MAX_REGS_PER_THREAD` | 255 | |
| `MAX_REGS_PER_BLOCK` | 65536 | |
| `MAX_REGS_PER_SM` | 65536 | |
| `WARP_SIZE` | 32 | |
| `CACHE_LINE_SIZE` | 128 | |
| `GPU_L2_CACHE_SIZE` | 2097152 | Bytes |
| `MAX_PERSISTING_L2_BYTES` | 1310720 | Bytes |
| `SHARED_MEM_PER_BLOCK` | 49152 | Bytes |
| `MAX_GRID_SIZE_X/Y/Z` | 2147483647 / 65535 / 65535 | |
| `MAJOR_COMPUTE_CAPABILITY` | 9 | |
| `MINOR_COMPUTE_CAPABILITY` | 0 | |
| `GPU_ARCH_INDEX` | 0 | 1–4 for compute capability major 9–12, otherwise 0 |
| `HAS_CUDA_9` … `HAS_CUDA_12` | 1, 0, 0, 0 | Set from the compute capability **major** version |

**Derived properties**

| Name | Description |
|---|---|
| `GPU_ARG_ALIGNMENT` | 16 |
| `CUDA_ARCHITECTURES` | `<major><minor>`, e.g. `90`, ready to pass to `CMAKE_CUDA_ARCHITECTURES` |

---

## SIMD Tier Selection

The default `<PREFIX>_SIMD_TIER` is the highest tier the CPU supports, checked in this order:

```
AVX512 (F+BW) → AVX2 → AVX → SVE2 (with known vector bits) → NEON → NONE
```

`<PREFIX>_SIMD_TIER` is a cache `STRING` with a dropdown in cmake-gui and ccmake, so you can build for a lower tier on purpose:

```bash
cmake -B build -DMYPROJ_SIMD_TIER=AVX2
```

The tier decides the compiler flags, the `<PREFIX>_<TIER>` definitions, `CPU_ALIGNMENT`, `CPU_ARCH_INDEX`, and which ISA bits end up in `<PREFIX>_CPU_INSTRUCTIONS`. On x86, the scalar bits (LZCNT, POPCNT, BMI1, CLMUL) are always kept, and only the vector bits at or below the selected tier are included. With MSVC, lower vector tiers are also implied, matching how `/arch:` behaves. NEON and SVE2 are mutually exclusive; the generated header raises an `#error` if both are selected.

---

## Generated Header

With `HEADER` set, you get something like this:

```cpp
#pragma once

#include <cstdint>

#define MYPROJ_CPU_DETECTED 1
#define MYPROJ_THREAD_COUNT 16
#define MYPROJ_HAS_AVX2 1
...
#define MYPROJ_ISA_AVX2 (1u << 6)
...
#define MYPROJ_CPU_INSTRUCTIONS 111
#define MYPROJ_CHECK_FOR_INSTRUCTION(x) ((MYPROJ_CPU_INSTRUCTIONS & (x)) != 0)

namespace myproj {

    struct cpu_properties {
        static constexpr bool detected = true;
        static constexpr uint64_t thread_count = 16ull;
        static constexpr bool has_avx2 = true;
        ...
        static constexpr uint64_t cpu_instructions = 111ull;
    };

}
```

- Each property is available as a macro, `<PREFIX>_<NAME>`, and as a lowercase struct member. `HAS_*` members are `bool`; all other members are `uint64_t`.
- `<PREFIX>_<KIND>_DETECTED` / `detected` tells you whether the values came from a real probe or are fallbacks.
- The struct is named `cpu_properties` or `gpu_properties`.

To control the format yourself, pass `TEMPLATE my_header.hpp.in`. It is processed with `configure_file(... @ONLY)`, so you can reference any `@MYPROJ_*@` variable.

---

## Targets, Flags and Definitions

Link `voided_hw::<prefix>_cpu` to get:

**Compile options**, chosen per compiler with generator expressions:

| Tier | MSVC | GCC / Clang / IntelLLVM |
|---|---|---|
| AVX512 | `/arch:AVX512` | `-mavx512f -mavx512bw [-mavx512vbmi2] -mavx2 -mavx -msse4.2 [-mfma] [-mf16c]` |
| AVX2 | `/arch:AVX2` | `-mavx2 -mavx -msse4.2 [-mfma] [-mf16c]` |
| AVX | `/arch:AVX` | `-mavx` |
| SVE2 | — | `-march=armv9-a+sve2[+aes] [-msve-vector-bits=N]` |

On x86, `-mlzcnt -mpopcnt -mbmi -mbmi2 -mpclmul` are added for whichever of those features were detected. With `CUDA_HOST_FLAGS`, the same flags are forwarded to the CUDA host compiler using `-Xcompiler=`.

**Compile definitions** (unless you pass `NO_DEFINITIONS`):

```
<PREFIX>_SVE2, <PREFIX>_AVX512, <PREFIX>_AVX2, <PREFIX>_AVX, <PREFIX>_NEON   = 1 for the selected tier, 0 otherwise
<PREFIX>_FALLBACK                                                         = 1 when the tier is NONE
<PREFIX>_INSTRUCTION_SET_NAME                                             = "AVX2" etc.
```

The flags and definitions are also exported as `<PREFIX>_SIMD_FLAGS` and `<PREFIX>_SIMD_DEFINITIONS`, so you can wire them up yourself.

Link `voided_hw::<prefix>_gpu` to get `<PREFIX>_CUDA_9` … `<PREFIX>_CUDA_12`. Exactly one of them is `1`: the highest one detected. They are also exported as `<PREFIX>_CUDA_DEFINITIONS`.

---

## Overriding Values

Every property is a normal cache variable. Set one yourself and voided-hw-detection keeps your value instead of replacing it:

```bash
cmake -B build -DMYPROJ_THREAD_COUNT=8 -DMYPROJ_CPU_L2_CACHE_SIZE=1048576
```

The library remembers which values it wrote, so a value you changed is never overwritten on a later reconfigure. The status output lists every manually set value:

```
-- voided-hw-detection [MYPROJ] CPU: using manually set MYPROJ_THREAD_COUNT, MYPROJ_CPU_L2_CACHE_SIZE
```

**Setting the instruction set by hand.** `<PREFIX>_CPU_INSTRUCTIONS` takes a `|`-separated expression of ISA bits. It replaces the detected mask and the `HAS_*` flags:

```bash
cmake -B build -DMYPROJ_DETECT_CPU=OFF "-DMYPROJ_CPU_INSTRUCTIONS=0x1|0x2|0x4|0x20|0x40"
```

This is the main way to target a machine other than the one doing the build.

---

## Options

| Option | Default | Description |
|---|---|---|
| `VOIDED_HW_DETECT` | `ON` | Master switch. `OFF` skips every probe and uses fallbacks and manually set values. |
| `<PREFIX>_DETECT_CPU` | `ON` | Run the CPU probe for this prefix. |
| `<PREFIX>_DETECT_GPU` | `ON` | Run the GPU probe for this prefix. |
| `<PREFIX>_SIMD_TIER` | detected | See [SIMD Tier Selection](#simd-tier-selection). |

---

## Caching and Re-detection

Each probe runs **once per build directory**. Its raw output is cached in `VOIDED_HW_CPU_DETECTOR_OUTPUT` / `VOIDED_HW_GPU_DETECTOR_OUTPUT`, and the probe projects are built under `${CMAKE_BINARY_DIR}/_voided_hw_detection/`.

To force detection to run again, clear the cached output:

```bash
cmake -B build -UVOIDED_HW_CPU_DETECTOR_OUTPUT -UVOIDED_HW_GPU_DETECTOR_OUTPUT
```

or delete `CMakeCache.txt`.

---

## Cross-Compiling and Fallbacks

The probes have to **run** on the build machine, so detection is skipped when `CMAKE_CROSSCOMPILING` is set, and a warning is printed. Every property then uses its fallback unless you set it yourself. If a probe fails to configure, build, run, or print its `<KIND>_SUCCESS=1` marker, you get a warning with the full log and the fallbacks are used. Your configure step never fails because of detection.

The probes are built with the same generator, platform, toolset and C++ compiler as the parent project.

---

## Platform Support

| | x86-64 | AArch64 |
|---|---|---|
| **Windows** | CPUID + XGETBV; caches via `GetLogicalProcessorInformation` | NEON assumed |
| **Linux** | CPUID + XGETBV; caches via `/sys/devices/system/cpu/cpu0/cache` | `getauxval` for NEON / PMULL / SVE2; SVE vector length via `svcntb()` |
| **macOS** | CPUID + XGETBV; caches via `sysctl` | `sysctl` for AdvSIMD / PMULL |

GPU detection supports NVIDIA CUDA devices only.

---

## Repository Layout

```
CMakeLists.txt                  top-level project; just includes the module
cmake/voided_hw_detection.cmake the CMake API (voided_hw_detect_cpu / voided_hw_detect_gpu)
detector/CMakeLists.txt         probe project, built at configure time
detector/cpu_detector.cpp       CPU probe
detector/gpu_detector.cpp       CUDA GPU probe
example/                        a consumer project using FetchContent
```

The probes print `KEY=value` lines to stdout and the CMake module parses them. You can run a probe by itself to see what it reports for your machine.

---

## License

MIT. See [License](License.md).
