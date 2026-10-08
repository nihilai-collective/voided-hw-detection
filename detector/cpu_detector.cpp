/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Nihilai Collective Corp
 * https://github.com/nihilai-collective/voided-hw-detection
 * detector/cpu_detector.cpp
 */

#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#if defined(_WIN32) || defined(_WIN64)
	#include <Windows.h>
#endif

#if defined(__APPLE__) && defined(__MACH__)
	#include <sys/sysctl.h>
	#include <sys/types.h>
#endif

#if defined(__aarch64__) || defined(_M_ARM64)
	#if defined(__linux__)
		#include <sys/auxv.h>
		#include <asm/hwcap.h>
	#endif
	#if defined(__ARM_FEATURE_SVE)
		#include <arm_sve.h>
	#endif
#elif defined(__x86_64__) || defined(_M_X64)
	#if defined(_MSC_VER)
		#include <intrin.h>
	#elif defined(__GNUC__) || defined(__clang__)
		#include <cpuid.h>
	#endif
#endif

enum class instruction_sets : uint32_t {
	fallback = 0x000,
	lzcnt	 = 0x001,
	popcnt	 = 0x002,
	bmi1	 = 0x004,
	clmul	 = 0x008,
	neon	 = 0x010,
	avx		 = 0x020,
	avx_2	 = 0x040,
	avx_512	 = 0x080,
	sve2	 = 0x100,
};

enum class extra_features : uint32_t {
	none		= 0x00,
	bmi2		= 0x01,
	fma			= 0x02,
	f16c		= 0x04,
	avx512f		= 0x08,
	avx512bw	= 0x10,
	avx512vbmi2 = 0x20,
};

constexpr uint32_t to_bits(instruction_sets value) {
	return static_cast<uint32_t>(value);
}

constexpr uint32_t to_bits(extra_features value) {
	return static_cast<uint32_t>(value);
}

struct detected_features {
	uint32_t instruction_mask{};
	uint32_t extra_mask{};
};

#if defined(__aarch64__) || defined(_M_ARM64)

	#if defined(__linux__) && !defined(HWCAP2_SVE2)
		#define HWCAP2_SVE2 (1 << 1)
	#endif

	#if defined(__linux__) && !defined(HWCAP_PMULL)
		#define HWCAP_PMULL (1 << 4)
	#endif

static detected_features detect_supported_architectures() {
	detected_features features{};
	#if defined(__linux__)
	if (getauxval(AT_HWCAP) & HWCAP_ASIMD) {
		features.instruction_mask |= to_bits(instruction_sets::neon);
	}
	if (getauxval(AT_HWCAP) & HWCAP_PMULL) {
		features.instruction_mask |= to_bits(instruction_sets::clmul);
	}
	if (getauxval(AT_HWCAP2) & HWCAP2_SVE2) {
		features.instruction_mask |= to_bits(instruction_sets::sve2);
	}
	#elif defined(__APPLE__)
	int32_t value{};
	size_t size = sizeof(value);
	if (sysctlbyname("hw.optional.AdvSIMD", &value, &size, nullptr, 0) != 0 || value) {
		features.instruction_mask |= to_bits(instruction_sets::neon);
	}
	value = 0;
	size  = sizeof(value);
	if (sysctlbyname("hw.optional.arm.FEAT_PMULL", &value, &size, nullptr, 0) == 0 && value) {
		features.instruction_mask |= to_bits(instruction_sets::clmul);
	}
	#else
	features.instruction_mask |= to_bits(instruction_sets::neon);
	#endif
	return features;
}

static uint32_t detect_sve2_vector_length_bits() {
	#if defined(__ARM_FEATURE_SVE)
	return static_cast<uint32_t>(svcntb()) * 8u;
	#else
	return 0u;
	#endif
}

#elif defined(__x86_64__) || defined(_M_X64)

static constexpr uint32_t cpuid_popcnt_bit		= 1u << 23;
static constexpr uint32_t cpuid_avx_bit			= 1u << 28;
static constexpr uint32_t cpuid_fma_bit			= 1u << 12;
static constexpr uint32_t cpuid_f16c_bit		= 1u << 29;
static constexpr uint32_t cpuid_osx_save		= (1u << 26) | (1u << 27);
static constexpr uint32_t cpuid_lzcnt_bit		= 1u << 5;
static constexpr uint32_t cpuid_bmi1_bit		= 1u << 3;
static constexpr uint32_t cpuid_bmi2_bit		= 1u << 8;
static constexpr uint32_t cpuid_pclmulqdq_bit	= 1u << 1;
static constexpr uint32_t cpuid_avx2_bit		= 1u << 5;
static constexpr uint32_t cpuid_avx512f_bit		= 1u << 16;
static constexpr uint32_t cpuid_avx512bw_bit	= 1u << 30;
static constexpr uint32_t cpuid_avx512vbmi2_bit = 1u << 6;
static constexpr uint64_t cpuid_avx256_saved	= 1ull << 2;
static constexpr uint64_t cpuid_avx512_saved	= 7ull << 5;

struct cpuid_result {
	uint32_t eax{};
	uint32_t ebx{};
	uint32_t ecx{};
	uint32_t edx{};
	bool valid{};
};

static cpuid_result cpuid(uint32_t leaf, uint32_t subleaf) {
	cpuid_result result{};
	#if defined(_MSC_VER)
	int32_t max_leaf[4]{};
	__cpuid(max_leaf, static_cast<int32_t>(leaf & 0x80000000u));
	if (leaf > static_cast<uint32_t>(max_leaf[0])) {
		return result;
	}
	int32_t registers[4]{};
	__cpuidex(registers, static_cast<int32_t>(leaf), static_cast<int32_t>(subleaf));
	result.eax	 = static_cast<uint32_t>(registers[0]);
	result.ebx	 = static_cast<uint32_t>(registers[1]);
	result.ecx	 = static_cast<uint32_t>(registers[2]);
	result.edx	 = static_cast<uint32_t>(registers[3]);
	result.valid = true;
	#elif defined(__GNUC__) || defined(__clang__)
	result.valid = __get_cpuid_count(leaf, subleaf, &result.eax, &result.ebx, &result.ecx, &result.edx) != 0;
	#endif
	return result;
}

static uint64_t xgetbv() {
	#if defined(_MSC_VER)
	return _xgetbv(0);
	#else
	uint32_t eax{}, edx{};
	asm volatile("xgetbv" : "=a"(eax), "=d"(edx) : "c"(0));
	return (static_cast<uint64_t>(edx) << 32) | eax;
	#endif
}

static detected_features detect_supported_architectures() {
	detected_features features{};

	const cpuid_result leaf_one = cpuid(0x1, 0x0);
	if (!leaf_one.valid) {
		return features;
	}

	if (leaf_one.ecx & cpuid_popcnt_bit) {
		features.instruction_mask |= to_bits(instruction_sets::popcnt);
	}

	if (leaf_one.ecx & cpuid_pclmulqdq_bit) {
		features.instruction_mask |= to_bits(instruction_sets::clmul);
	}

	const cpuid_result leaf_extended = cpuid(0x80000001, 0x0);
	if (leaf_extended.valid && (leaf_extended.ecx & cpuid_lzcnt_bit)) {
		features.instruction_mask |= to_bits(instruction_sets::lzcnt);
	}

	const cpuid_result leaf_seven = cpuid(0x7, 0x0);
	if (!leaf_seven.valid) {
		return features;
	}

	if (leaf_seven.ebx & cpuid_bmi1_bit) {
		features.instruction_mask |= to_bits(instruction_sets::bmi1);
	}

	if (leaf_seven.ebx & cpuid_bmi2_bit) {
		features.extra_mask |= to_bits(extra_features::bmi2);
	}

	if ((leaf_one.ecx & cpuid_osx_save) != cpuid_osx_save) {
		return features;
	}

	const uint64_t xcr0 = xgetbv();
	if ((xcr0 & cpuid_avx256_saved) == 0) {
		return features;
	}

	if (leaf_one.ecx & cpuid_avx_bit) {
		features.instruction_mask |= to_bits(instruction_sets::avx);
	}

	if (leaf_one.ecx & cpuid_fma_bit) {
		features.extra_mask |= to_bits(extra_features::fma);
	}

	if (leaf_one.ecx & cpuid_f16c_bit) {
		features.extra_mask |= to_bits(extra_features::f16c);
	}

	if (leaf_seven.ebx & cpuid_avx2_bit) {
		features.instruction_mask |= to_bits(instruction_sets::avx_2);
	}

	if ((xcr0 & cpuid_avx512_saved) != cpuid_avx512_saved) {
		return features;
	}

	if (leaf_seven.ebx & cpuid_avx512f_bit) {
		features.extra_mask |= to_bits(extra_features::avx512f);
	}

	if (leaf_seven.ebx & cpuid_avx512bw_bit) {
		features.extra_mask |= to_bits(extra_features::avx512bw);
	}

	if (leaf_seven.ecx & cpuid_avx512vbmi2_bit) {
		features.extra_mask |= to_bits(extra_features::avx512vbmi2);
	}

	const uint32_t full_avx512 = to_bits(extra_features::avx512f) | to_bits(extra_features::avx512bw) | to_bits(extra_features::avx512vbmi2);
	if ((features.extra_mask & full_avx512) == full_avx512) {
		features.instruction_mask |= to_bits(instruction_sets::avx_512);
	}

	return features;
}

static uint32_t detect_sve2_vector_length_bits() {
	return 0u;
}

#else

static detected_features detect_supported_architectures() {
	return {};
}

static uint32_t detect_sve2_vector_length_bits() {
	return 0u;
}

#endif

enum class cache_level {
	one	  = 1,
	two	  = 2,
	three = 3,
};

static uint64_t get_cache_size(cache_level level) {
#if defined(_WIN32) || defined(_WIN64)
	DWORD buffer_size = 0;
	GetLogicalProcessorInformation(nullptr, &buffer_size);
	if (buffer_size == 0) {
		return 0;
	}
	std::vector<SYSTEM_LOGICAL_PROCESSOR_INFORMATION> buffer(buffer_size / sizeof(SYSTEM_LOGICAL_PROCESSOR_INFORMATION));
	if (!GetLogicalProcessorInformation(buffer.data(), &buffer_size)) {
		return 0;
	}
	for (const auto& entry: buffer) {
		if (entry.Relationship == RelationCache && entry.Cache.Level == static_cast<BYTE>(level)) {
			if (level == cache_level::one && entry.Cache.Type == CacheData) {
				return entry.Cache.Size;
			} else if (level != cache_level::one && entry.Cache.Type == CacheUnified) {
				return entry.Cache.Size;
			}
		}
	}
	return 0;

#elif defined(__linux__) || defined(__ANDROID__)
	auto get_cache_size_from_file = [](const std::string& index) -> uint64_t {
		std::ifstream file("/sys/devices/system/cpu/cpu0/cache/index" + index + "/size");
		if (!file.is_open()) {
			return 0;
		}
		std::string size_string;
		file >> size_string;
		if (size_string.empty()) {
			return 0;
		}
		uint64_t size = std::stoull(size_string);
		if (size_string.find('K') != std::string::npos) {
			size *= 1024ull;
		} else if (size_string.find('M') != std::string::npos) {
			size *= 1024ull * 1024ull;
		}
		return size;
	};

	if (level == cache_level::one) {
		return get_cache_size_from_file("0");
	}
	return get_cache_size_from_file(level == cache_level::two ? "2" : "3");

#elif defined(__APPLE__)
	auto get_cache_size_for_mac = [](const char* cache_type) -> uint64_t {
		uint64_t cache_size = 0;
		size_t size			= sizeof(cache_size);
		std::string query	= std::string("hw.") + cache_type + "cachesize";
		if (sysctlbyname(query.c_str(), &cache_size, &size, nullptr, 0) != 0) {
			return 0;
		}
		return cache_size;
	};

	if (level == cache_level::one) {
		return get_cache_size_for_mac("l1d");
	}
	return get_cache_size_for_mac(level == cache_level::two ? "l2" : "l3");

#else
	return 0;
#endif
}

static void report(const char* name, uint64_t value) {
	std::cout << name << "=" << value << std::endl;
}

static void report(const char* name, uint32_t mask, instruction_sets value) {
	report(name, (mask & to_bits(value)) ? 1u : 0u);
}

static void report(const char* name, uint32_t mask, extra_features value) {
	report(name, (mask & to_bits(value)) ? 1u : 0u);
}

int main() {
	const detected_features features = detect_supported_architectures();
	const uint32_t isa				 = features.instruction_mask;
	const uint32_t extra			 = features.extra_mask;

	report("THREAD_COUNT", std::thread::hardware_concurrency());
	report("CPU_L1_CACHE_SIZE", get_cache_size(cache_level::one));
	report("CPU_L2_CACHE_SIZE", get_cache_size(cache_level::two));
	report("CPU_L3_CACHE_SIZE", get_cache_size(cache_level::three));

	report("HAS_LZCNT", isa, instruction_sets::lzcnt);
	report("HAS_POPCNT", isa, instruction_sets::popcnt);
	report("HAS_BMI1", isa, instruction_sets::bmi1);
	report("HAS_BMI2", extra, extra_features::bmi2);
	report("HAS_CLMUL", isa, instruction_sets::clmul);
	report("HAS_FMA", extra, extra_features::fma);
	report("HAS_F16C", extra, extra_features::f16c);
	report("HAS_AVX", isa, instruction_sets::avx);
	report("HAS_AVX2", isa, instruction_sets::avx_2);
	report("HAS_AVX512F", extra, extra_features::avx512f);
	report("HAS_AVX512BW", extra, extra_features::avx512bw);
	report("HAS_AVX512VBMI2", extra, extra_features::avx512vbmi2);
	report("HAS_AVX512", isa, instruction_sets::avx_512);
	report("HAS_NEON", isa, instruction_sets::neon);
	report("HAS_SVE2", isa, instruction_sets::sve2);

	report("SVE2_VECTOR_BITS", (isa & to_bits(instruction_sets::sve2)) ? detect_sve2_vector_length_bits() : 0u);
	report("CPU_INSTRUCTION_MASK", isa);
	report("CPU_SUCCESS", 1u);
	return 0;
}
