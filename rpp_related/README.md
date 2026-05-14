# rpp_related/

Build helper script for [RPP (ROCm Performance Primitives)](https://github.com/ROCm/rpp) — AMD's GPU-accelerated image-processing library.

---

## `build_rpp.sh`

A wrapper around CMake that handles configuring, building, and optionally installing RPP with a single command. Includes pre-flight environment checks that validate all required dependencies before the build starts.

### Prerequisites

- ROCm/TheRock install with `amdclang++` >= 18.0.0 (HIP backend) or `clang++` >= 5.0.1 (CPU/OCL)
- CMake >= 3.10
- `half.hpp` (half-precision library)
- OpenMP headers (`omp.h`)
- `hip-dev` package or equivalent headers (HIP backend only)
- RPP source tree at `$PWD/rpp` or `$RPP_SOURCE`

Source `../set_rocm_env/set_rocm_env.sh` (done automatically by the script) or ensure `ROCM_PATH` is set before running.

### Usage

```bash
# Release incremental build:
bash build_rpp.sh -r

# Release build + install:
bash build_rpp.sh -r -i

# Clean release build:
bash build_rpp.sh -c -r

# Clean release build + install:
bash build_rpp.sh -c -r -i

# Debug incremental build:
bash build_rpp.sh -d

# Debug build + install:
bash build_rpp.sh -d -i

# Clean debug build, CPU backend:
bash build_rpp.sh -c -d -cpu

# 16 parallel jobs, custom install prefix:
bash build_rpp.sh -r -j 16 -prefix /opt/rocm

# Check config and run pre-flight checks only (no build):
bash build_rpp.sh --config -r -hip
```

### Options

| Flag | Description |
|------|-------------|
| `-r` | Release build |
| `-d` | Debug build (`-r` and `-d` are mutually exclusive) |
| `-c` | Clean build — removes the build directory first |
| `-i` | Install after building |
| `-hip` | HIP backend *(default)* |
| `-cpu` | CPU/HOST backend |
| `-ocl` | OpenCL backend (auto-enables legacy support) |
| `-j <N>` | Parallel jobs (default: `nproc`) |
| `-prefix <path>` | Custom install prefix (default: `$ROCM_PATH`) |
| `-legacy` | Enable `RPP_LEGACY_SUPPORT` |
| `-noaudio` | Disable `RPP_AUDIO_SUPPORT` |
| `--config` | Print full configuration + run pre-flight checks, then exit |
| `-h` / `--help` | Show usage |

### RPP source resolution

The script locates the RPP source tree in this priority order:

1. `$RPP_SOURCE` environment variable
2. `$PWD/rpp` directory

```bash
# If RPP is not in $PWD/rpp:
export RPP_SOURCE=/path/to/rpp
bash build_rpp.sh -r
```

### Pre-flight checks

Before every build the script validates:

1. CPU architecture (expects x86_64)
2. OS and version (Ubuntu 22.04/24.04, RHEL 8/9, SLES 15)
3. CMake >= 3.10
4. Compiler (`amdclang++` >= 18 for HIP, `clang++` >= 5 for CPU/OCL)
5. C++17 support (compile-tested against `std::optional`, `std::variant`, `std::string_view`)
6. ROCm >= 7.0.0 and GPU gfx target (HIP backend only)
7. `half.hpp` header (half-precision library)
8. OpenMP headers
9. pthreads
10. `libstdc++-12-dev` (Ubuntu 22.04 only)
11. `hip-dev` / `hip-devel` package (HIP backend only)

Any **required** check failure aborts with a clear error before wasting build time.

### ROCm environment

The script sources `../set_rocm_env/set_rocm_env.sh` automatically. If that file is not found it falls back to `$ROCM_PATH` or `/opt/rocm`.

To point at a specific TheRock tree:

```bash
# Either source it manually first:
source ../set_rocm_env/set_rocm_env.sh /path/to/install
bash build_rpp.sh -r

# Or rely on the automatic sourcing (uses the default path in set_rocm_env.sh).
```

### Example: full clean build and install

```bash
cd /scratch/users/lbonta
source set_rocm_env/set_rocm_env.sh \
    therock-tarball-gfx94X-dcgpu-20260513-145755/install

export RPP_SOURCE=$PWD/rpp
bash rpp_related/build_rpp.sh -c -r -i -j 32
```

After a successful install, RPP libraries and headers are placed under `$ROCM_PATH` (or the `-prefix` you specified).
