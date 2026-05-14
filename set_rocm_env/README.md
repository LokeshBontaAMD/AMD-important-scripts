# set_rocm_env/

Full ROCm/HIP environment setup for TheRock custom builds.

## Usage

```bash
# Auto-discover last TheRock install (from .therock_last_install state file)
source set_rocm_env/set_rocm_env.sh

# Explicit path
source set_rocm_env/set_rocm_env.sh /path/to/therock/install

# Via THEROCK_INSTALL_DIR env var
export THEROCK_INSTALL_DIR=/path/to/install
source set_rocm_env/set_rocm_env.sh
```

## Variables Set

| Variable | Value |
|---|---|
| `ROCM_PATH` | TheRock install root |
| `HIP_PLATFORM` | `amd` |
| `HIP_PATH` | Same as `ROCM_PATH` |
| `HIP_CLANG_PATH` | `$ROCM_PATH/llvm/bin` |
| `HIP_INCLUDE_PATH` | `$ROCM_PATH/include` |
| `HIP_LIB_PATH` | `$ROCM_PATH/lib` |
| `HIP_DEVICE_LIB_PATH` | `$ROCM_PATH/lib/llvm/amdgcn/bitcode` |
| `PATH` | Prepended with ROCm and LLVM bins |
| `LD_LIBRARY_PATH` | Prepended with ROCm libs |
| `LIBRARY_PATH` | Prepended with ROCm libs |
| `CPATH` | Prepended with ROCm headers |
| `PKG_CONFIG_PATH` | Prepended with ROCm pkg-config |

## Install path resolution order

1. Explicit `$1` argument
2. `$THEROCK_INSTALL_DIR` environment variable
3. `$SCRATCH_ROOT/.therock_last_install` state file (written by `install_therock`)
