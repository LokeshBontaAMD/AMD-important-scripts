# set_rocm_env/

Environment setup script for ROCm/HIP sessions using a custom TheRock install tree instead of the system `/opt/rocm`.

---

## `set_rocm_env.sh`

Sets all environment variables required to build and run ROCm/HIP applications against a specific TheRock installation.

### Usage

**Must be sourced — not executed directly:**

```bash
# Use the default TheRock install path (hardcoded in the script):
source set_rocm_env.sh

# Point at a specific TheRock install tree:
source set_rocm_env.sh /path/to/therock-tarball-gfx94X-dcgpu-<timestamp>/install

# Short form:
. set_rocm_env.sh /path/to/install
```

### Variables set

| Variable | Value | Purpose |
|----------|-------|---------|
| `ROCM_PATH` | `<install>` | Root of the ROCm/TheRock tree |
| `HIP_PLATFORM` | `amd` | Selects AMD GPU path in hipcc/CMake |
| `HIP_PATH` | `$ROCM_PATH` | HIP root (mirrors ROCM_PATH in TheRock layouts) |
| `HIP_CLANG_PATH` | `$ROCM_PATH/llvm/bin` | Directory containing `amdclang`, `amdclang++` |
| `HIP_INCLUDE_PATH` | `$ROCM_PATH/include` | Public HIP/ROCm headers |
| `HIP_LIB_PATH` | `$ROCM_PATH/lib` | HIP shared libraries (`libamdhip64.so`, etc.) |
| `HIP_DEVICE_LIB_PATH` | `$ROCM_PATH/lib/llvm/amdgcn/bitcode` | AMDGCN bitcode device libraries for hipcc |
| `PATH` | prepended | Adds `$ROCM_PATH/bin` and `$HIP_CLANG_PATH` |
| `LD_LIBRARY_PATH` | prepended | Adds ROCm lib, lib64, and LLVM runtime libs |
| `LIBRARY_PATH` | prepended | Static linker search path |
| `CPATH` | prepended | C/C++ preprocessor header search path |
| `PKG_CONFIG_PATH` | prepended | Adds `$ROCM_PATH/lib/pkgconfig` for CMake `find_package` |

### Integration with `build_rpp.sh`

`build_rpp.sh` (in `../rpp_related/`) sources this script automatically at startup. If you are sourcing `set_rocm_env.sh` manually in your shell before running the build script, the sourced values will be used as-is.

### Default install path

The default path in the script points to the gfx94X-dcgpu TheRock tarball under `/scratch/users/lbonta`. Edit the default at the top of the script if your install lives elsewhere, or always pass the path explicitly as `$1`.

### Example

```bash
# One-time setup in your shell session before building:
source /path/to/set_rocm_env/set_rocm_env.sh \
    /scratch/users/lbonta/therock-tarball-gfx94X-dcgpu-20260513-145755/install

# Confirm:
echo $ROCM_PATH
which amdclang++
rocminfo | head -10
```
