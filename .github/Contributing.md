# Contributing to voided-hw-detection

Thanks for your interest in improving voided-hw-detection. This guide covers how to report problems, propose changes, and get a pull request merged.

## Reporting Bugs

Open an issue and include:

- The `voided_hw_detect_cpu` / `voided_hw_detect_gpu` call and options you used.
- CMake version, compiler and version, operating system, and target architecture.
- CPU model, plus GPU model and CUDA toolkit version for GPU detection.
- The detected values versus the values you expected, and the configure output.

## Proposing Changes

For anything larger than a small fix, open an issue first so the approach can be discussed before you invest time in it.

1. Fork the repository and create a branch from `main`.
2. Make your change.
3. Configure and build the `example` project on the hardware you have (see below).
4. Open a pull request against `main` describing what changed and why.

## Building and Testing

voided-hw-detection runs at CMake configure time. The `example` directory is the test bed: configure it, check the detected cache variables and the generated header, then build it.

There is no CI for this repository yet, so please state in your pull request which operating systems, compilers, CPUs, and GPUs you tested on. A change to a probe in `detector` should be checked on every architecture it affects, and must keep the fallback defaults working when detection is impossible (cross-compiling, no CUDA toolkit, or no GPU).

## Code Style

- Format C++ changes with the repository `.clang-format`.
- Do not add explanatory comments to code. Write self-documenting code instead. Comments that attribute algorithms, techniques, or implementations to their original authors or sources are explicitly permitted. If current-us cannot write self-documenting code, then future-us does not deserve to understand it.
- Keep the probes lean. Only include what the file actually uses.
- Keep changes focused. Unrelated refactors belong in their own pull request.

## Pull Request Checklist

- [ ] `example` configures and builds on the platforms you tested
- [ ] Fallback defaults still apply when detection fails
- [ ] Formatted with clang-format
- [ ] No added explanatory code comments (source attributions are permitted)
- [ ] Linked to the issue it addresses, if any

## Licensing

By contributing, you agree that your contributions are licensed under the project's MIT license (see `License.md`).
