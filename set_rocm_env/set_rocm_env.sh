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
#        If omitted, reads the last install from $SCRATCH_ROOT/.therock_last_install
#        (written automatically by install_therock.sh).
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
# Priority: explicit $1 > $THEROCK_INSTALL_DIR env > .therock_last_install state file
_SCRATCH_ROOT="${SCRATCH_ROOT:-/scratch/users/${USER}}"
_STATE_FILE="${_SCRATCH_ROOT}/.therock_last_install"

if [[ -n "${1:-}" ]]; then
    _RAW_PATH="$1"
elif [[ -n "${THEROCK_INSTALL_DIR:-}" ]]; then
    _RAW_PATH="${THEROCK_INSTALL_DIR}"
elif [[ -f "${_STATE_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${_STATE_FILE}"
    _RAW_PATH="${INSTALL_DIR:-}"
    if [[ -z "${_RAW_PATH}" ]]; then
        echo "ERROR: State file ${_STATE_FILE} exists but contains no INSTALL_DIR."
        return 1
    fi
else
    echo "ERROR: No TheRock install path found."
    echo "  Options:"
    echo "    1. Run install_therock to download and extract a build."
    echo "    2. Pass the path explicitly:"
    echo "       source set_rocm_env.sh /path/to/therock/install"
    echo "    3. Set THEROCK_INSTALL_DIR=/path/to/install and re-source."
    return 1
fi

# Canonicalize to an absolute path so every variable is unambiguous.
if command -v realpath &>/dev/null; then
    THEROCK_INSTALL_PATH="$(realpath "$_RAW_PATH")"
else
    THEROCK_INSTALL_PATH="$(cd "$_RAW_PATH" 2>/dev/null && pwd)"
fi
unset _RAW_PATH _STATE_FILE _SCRATCH_ROOT

if [[ ! -d "$THEROCK_INSTALL_PATH" ]]; then
    echo "ERROR: ROCm install directory does not exist: $THEROCK_INSTALL_PATH"
    echo "       Pass a valid TheRock install path as the first argument, or run install_therock."
    return 1
fi

# ─── Core ROCm variables ──────────────────────────────────────────────────────
export ROCM_PATH="$THEROCK_INSTALL_PATH"
export HIP_PLATFORM=amd
export HIP_PATH=$ROCM_PATH

# ─── Compiler and toolchain paths ────────────────────────────────────────────
export HIP_CLANG_PATH=$ROCM_PATH/llvm/bin

# ─── Header and library paths ─────────────────────────────────────────────────
export HIP_INCLUDE_PATH=$ROCM_PATH/include
export HIP_LIB_PATH=$ROCM_PATH/lib
export HIP_DEVICE_LIB_PATH=$ROCM_PATH/lib/llvm/amdgcn/bitcode

# ─── Search-path variables ────────────────────────────────────────────────────
export PATH="$ROCM_PATH/bin:$HIP_CLANG_PATH:$PATH"
export LD_LIBRARY_PATH="$HIP_LIB_PATH:$ROCM_PATH/lib:$ROCM_PATH/lib64:$ROCM_PATH/llvm/lib:${LD_LIBRARY_PATH:-}"
export LIBRARY_PATH="$HIP_LIB_PATH:$ROCM_PATH/lib:$ROCM_PATH/lib64:${LIBRARY_PATH:-}"
export CPATH="$HIP_INCLUDE_PATH:${CPATH:-}"
export PKG_CONFIG_PATH="$ROCM_PATH/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo "ROCm environment set:"
echo "  ROCM_PATH        = $ROCM_PATH"
echo "  HIP_PLATFORM     = $HIP_PLATFORM"
echo "  HIP_CLANG_PATH   = $HIP_CLANG_PATH"
echo "  HIP_DEVICE_LIB   = $HIP_DEVICE_LIB_PATH"
