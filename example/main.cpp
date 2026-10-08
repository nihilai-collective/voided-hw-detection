#include <example/cpu_properties.hpp>
#include <iostream>

#if EXAMPLE_WITH_GPU
	#include <example/gpu_properties.hpp>
#endif

static_assert(example::cpu_properties::thread_count == EXAMPLE_THREAD_COUNT);

int main() {
	std::cout << "threads: " << example::cpu_properties::thread_count << '\n';
	std::cout << "l1: " << example::cpu_properties::cpu_l1_cache_size << '\n';
#if EXAMPLE_HAS_AVX512
	std::cout << "path: avx512\n";
#elif EXAMPLE_HAS_AVX2
	std::cout << "path: avx2\n";
#elif EXAMPLE_HAS_NEON
	std::cout << "path: neon\n";
#else
	std::cout << "path: fallback\n";
#endif
	if constexpr (EXAMPLE_CHECK_FOR_INSTRUCTION(EXAMPLE_ISA_BMI1)) {
		std::cout << "bmi1: yes\n";
	}
#if EXAMPLE_WITH_GPU
	std::cout << "sms: " << example::hw::gpu_properties::sm_count << ", cc " << example::hw::gpu_properties::major_compute_capability << '.'
			  << example::hw::gpu_properties::minor_compute_capability << '\n';
#endif
	return 0;
}
