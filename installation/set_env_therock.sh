#!/usr/bin/env bash
# =============================================================================
# set_env_therock.sh
# Sets ROCm/HIP environment variables for a TheRock install directory.
#
# MUST be sourced (not executed) to take effect in the current shell:
#   source set_env_therock.sh /path/to/therock/.../install
#   source set_env_therock.sh          # reads last install from state file
# =============================================================================

_therock_state_file="${SCRATCH_ROOT:-/scratch/users/${USER}}/.therock_last_install"

# Resolve the install path: arg > state file
if [ -n "${1:-}" ]; then
    ROCM_PATH="$1"
elif [ -f "$_therock_state_file" ]; then
    # shellcheck source=/dev/null
    source "$_therock_state_file"
    ROCM_PATH="$INSTALL_DIR"
fi

if [ -z "${ROCM_PATH:-}" ] || [ ! -d "$ROCM_PATH" ]; then
    echo "ERROR: Could not resolve a valid TheRock install directory."
    echo "  Run install_therock first, or provide the path:"
    echo "    source set_env_therock.sh /path/to/install"
    return 1 2>/dev/null || exit 1
fi

export ROCM_PATH
export HIP_PLATFORM=amd
export HIP_PATH=$ROCM_PATH
export PATH="$ROCM_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib64:${LD_LIBRARY_PATH:-}"

echo "ROCm environment set:"
echo "  ROCM_PATH    = $ROCM_PATH"
echo "  HIP_PLATFORM = $HIP_PLATFORM"
