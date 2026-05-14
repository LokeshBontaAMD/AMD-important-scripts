#!/bin/bash
# =============================================================================
#  set_rocm_env.sh  --  ROCm / HIP environment setup (TheRock builds)
#
#  MUST be sourced, not executed directly:
#    source set_rocm_env.sh [therock_install_path]
#    . set_rocm_env.sh [therock_install_path]
#
#  Arguments:
#    $1  (optional) Path to the TheRock install tree.
#        Defaults to the gfx94X-dcgpu tarball under /scratch/users/lbonta.
#
#  What it does:
#    Exports all environment variables required for a ROCm/HIP build and
#    runtime session pointing at a custom TheRock install instead of the
#    system /opt/rocm.  Safe to re-source; existing PATH/LD_LIBRARY_PATH
#    entries are preserved.
#
#  After sourcing, the following variables are set:
#    ROCM_PATH           Root of the ROCm/TheRock install tree
#    HIP_PLATFORM        Must be "amd" for AMD GPU targets
#    HIP_PATH            Same as ROCM_PATH (HIP lives inside ROCm)
#    HIP_CLANG_PATH      Path to amdclang / amdclang++ binaries
#    HIP_INCLUDE_PATH    HIP / ROCm public headers
#    HIP_LIB_PATH        Primary HIP shared libraries (.so)
#    HIP_DEVICE_LIB_PATH AMDGCN bitcode device libraries (used by hipcc)
#    PATH                Prepended with ROCm bin + LLVM bin
#    LD_LIBRARY_PATH     Prepended with ROCm lib directories
#    LIBRARY_PATH        Linker search path for static libs
#    CPATH               Header search path for the C/C++ preprocessor
#    PKG_CONFIG_PATH     pkg-config search path for ROCm .pc files
# =============================================================================

# ─── Guard: must be sourced ───────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "WARNING: This script must be sourced, not executed directly."
    echo "Usage: source ${BASH_SOURCE[0]} [therock_install_path]"
    echo "   or:  . ${BASH_SOURCE[0]} [therock_install_path]"
    exit 1
fi

# ─── Resolve install path ─────────────────────────────────────────────────────
# Accept an explicit path via $1; fall back to the default TheRock tarball.
_RAW_PATH="${1:-/scratch/users/lbonta/therock-tarball-gfx94X-dcgpu-20260513-145755/install}"

# Canonicalize to an absolute path so every variable is unambiguous.
if command -v realpath &>/dev/null; then
    THEROCK_INSTALL_PATH="$(realpath "$_RAW_PATH")"
else
    # Fallback for systems without realpath (older RHEL/CentOS).
    THEROCK_INSTALL_PATH="$(cd "$_RAW_PATH" 2>/dev/null && pwd)"
fi
unset _RAW_PATH

# Abort early if the directory does not exist — a bad path causes silent
# build failures that are hard to debug later.
if [[ ! -d "$THEROCK_INSTALL_PATH" ]]; then
    echo "ERROR: ROCm install directory does not exist: $THEROCK_INSTALL_PATH"
    echo "       Pass a valid TheRock install path as the first argument."
    return 1
fi

# ─── Core ROCm variables ──────────────────────────────────────────────────────
export ROCM_PATH="$THEROCK_INSTALL_PATH"

# HIP_PLATFORM=amd selects the AMD GPU path inside hipcc / CMake.
# The alternative ("nvidia") is only for CUDA cross-builds.
export HIP_PLATFORM=amd

# HIP_PATH mirrors ROCM_PATH because, in TheRock builds, HIP headers and
# libs are installed directly under the ROCm root rather than a separate prefix.
export HIP_PATH=$ROCM_PATH

# ─── Compiler and toolchain paths ────────────────────────────────────────────
# amdclang / amdclang++ / hipcc all live in $ROCM_PATH/bin.
# LLVM utilities (llvm-symbolizer, etc.) live in llvm/bin.
export HIP_CLANG_PATH=$ROCM_PATH/llvm/bin

# ─── Header and library paths ─────────────────────────────────────────────────
# Public HIP/ROCm headers (hip/hip_runtime.h, rocm_version.h, …).
export HIP_INCLUDE_PATH=$ROCM_PATH/include

# Shared libraries: libamdhip64.so, librocblas.so, etc.
export HIP_LIB_PATH=$ROCM_PATH/lib

# AMDGCN bitcode device libraries required by hipcc during device-code linking.
# These contain built-ins like __ocml_* and OCKL math routines.
export HIP_DEVICE_LIB_PATH=$ROCM_PATH/lib/llvm/amdgcn/bitcode

# ─── Search-path variables ────────────────────────────────────────────────────
# Prepend ROCm and LLVM bins so amdclang/hipcc are found before system clang.
export PATH="$ROCM_PATH/bin:$HIP_CLANG_PATH:$PATH"

# Runtime linker: include both lib and lib64 for mixed 32/64-bit installs,
# and llvm/lib for LLVM runtime libraries (libLLVM, libclang, …).
export LD_LIBRARY_PATH="$HIP_LIB_PATH:$ROCM_PATH/lib:$ROCM_PATH/lib64:$ROCM_PATH/llvm/lib:${LD_LIBRARY_PATH:-}"

# Static linker search path (used by ld / lld at link time).
export LIBRARY_PATH="$HIP_LIB_PATH:$ROCM_PATH/lib:$ROCM_PATH/lib64:${LIBRARY_PATH:-}"

# C/C++ preprocessor header search path.
export CPATH="$HIP_INCLUDE_PATH:${CPATH:-}"

# pkg-config: lets CMake's find_package(hip) and similar modules locate .pc files.
export PKG_CONFIG_PATH="$ROCM_PATH/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo "ROCm environment set:"
echo "  ROCM_PATH        = $ROCM_PATH"
echo "  HIP_PLATFORM     = $HIP_PLATFORM"
echo "  HIP_CLANG_PATH   = $HIP_CLANG_PATH"
echo "  HIP_DEVICE_LIB   = $HIP_DEVICE_LIB_PATH"
