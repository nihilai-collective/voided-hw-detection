/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Nihilai Collective Corp
 * https://github.com/nihilai-collective/voided-hw-detection
 * detector/gpu_detector.cpp
 */

#include <cuda_runtime.h>
#include <algorithm>
#include <cstdint>
#include <iostream>

static int32_t get_cores_per_sm(int32_t major) {
	if (major == 7) {
		return 64;
	}
	return 128;
}

static uint32_t get_gpu_arch_index(int32_t major) {
	switch (major) {
		case 9:
			return 1;
		case 10:
			return 2;
		case 11:
			return 3;
		case 12:
			return 4;
		default:
			return 0;
	}
}

static int32_t get_attribute(cudaDeviceAttr attribute) {
	int32_t value{};
	if (cudaDeviceGetAttribute(&value, attribute, 0) != cudaSuccess) {
		return 0;
	}
	return value;
}

template<typename value_type> static void report(const char* name, value_type value) {
	std::cout << name << "=" << value << std::endl;
}

int main() {
	cudaDeviceProp device_prop{};
	if (cudaGetDeviceProperties(&device_prop, 0) != cudaSuccess) {
		report("CUDA_ERROR", 1);
		return 1;
	}

	const int32_t memory_clock_khz = get_attribute(cudaDevAttrMemoryClockRate);
	const int32_t core_clock_khz   = get_attribute(cudaDevAttrClockRate);

	const double bus_width_bytes		 = static_cast<double>(device_prop.memoryBusWidth) / 8.0;
	const int64_t memory_bandwidth_bytes = static_cast<int64_t>(static_cast<double>(memory_clock_khz) * 1000.0 * bus_width_bytes * 2.0);
	const double total_flops = static_cast<double>(device_prop.multiProcessorCount) * get_cores_per_sm(device_prop.major) * static_cast<double>(core_clock_khz) * 1000.0 * 2.0;
	const int64_t fp32_throughput_bytes = static_cast<int64_t>(total_flops * 4.0);

	report("MEMORY_BANDWIDTH_BYTES", memory_bandwidth_bytes);
	report("FP32_THROUGHPUT_BYTES", fp32_throughput_bytes);
	report("MEMORY_BUS_WIDTH", device_prop.memoryBusWidth);
	report("MEMORY_CLOCK_RATE", memory_clock_khz);
	report("CORE_CLOCK_RATE", core_clock_khz);
	report("SM_COUNT", device_prop.multiProcessorCount);
	report("TOTAL_THREADS", device_prop.maxThreadsPerMultiProcessor * device_prop.multiProcessorCount);
	report("GPU_ALIGNMENT", std::max({ static_cast<size_t>(device_prop.textureAlignment), static_cast<size_t>(device_prop.surfaceAlignment), static_cast<size_t>(256) }));
	report("MAX_THREADS_PER_SM", device_prop.maxThreadsPerMultiProcessor);
	report("MAX_THREADS_PER_BLOCK", device_prop.maxThreadsPerBlock);
	report("MAX_REGS_PER_THREAD", 255);
	report("MAX_REGS_PER_BLOCK", device_prop.regsPerBlock);
	report("MAX_REGS_PER_SM", device_prop.regsPerMultiprocessor);
	report("WARP_SIZE", device_prop.warpSize);
	report("CACHE_LINE_SIZE", 128);
	report("GPU_L2_CACHE_SIZE", device_prop.l2CacheSize);
	report("MAX_PERSISTING_L2_BYTES", device_prop.persistingL2CacheMaxSize);
	report("SHARED_MEM_PER_BLOCK", device_prop.sharedMemPerBlock);
	report("MAX_GRID_SIZE_X", device_prop.maxGridSize[0]);
	report("MAX_GRID_SIZE_Y", device_prop.maxGridSize[1]);
	report("MAX_GRID_SIZE_Z", device_prop.maxGridSize[2]);
	report("MAJOR_COMPUTE_CAPABILITY", device_prop.major);
	report("MINOR_COMPUTE_CAPABILITY", device_prop.minor);
	report("GPU_ARCH_INDEX", get_gpu_arch_index(device_prop.major));
	report("HAS_CUDA_9", device_prop.major == 9 ? 1 : 0);
	report("HAS_CUDA_10", device_prop.major == 10 ? 1 : 0);
	report("HAS_CUDA_11", device_prop.major == 11 ? 1 : 0);
	report("HAS_CUDA_12", device_prop.major == 12 ? 1 : 0);
	report("GPU_SUCCESS", 1);
	return 0;
}
