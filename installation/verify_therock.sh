#!/usr/bin/env bash
# =============================================================================
# verify_therock.sh
# Verifies a TheRock installation by running rocminfo and test_hip_api.
#
# Usage:
#   bash verify_therock.sh                        # reads last install from state file
#   bash verify_therock.sh /path/to/install/dir   # explicit install dir
#   INSTALL_DIR=/path/to/install/dir bash verify_therock.sh
# =============================================================================

set -euo pipefail

SCRATCH_ROOT="${SCRATCH_ROOT:-/scratch/users/lbonta}"
STATE_FILE="$SCRATCH_ROOT/.therock_last_install"

# Resolve INSTALL_DIR: arg > env var > state file
if [ -n "${1:-}" ]; then
    INSTALL_DIR="$1"
elif [ -n "${INSTALL_DIR:-}" ]; then
    : # already set in environment
elif [ -f "$STATE_FILE" ]; then
    # shellcheck source=/dev/null
    source "$STATE_FILE"
else
    echo "ERROR: No install directory specified."
    echo "  Run install_therock.sh first, or provide the path:"
    echo "    bash verify_therock.sh /path/to/install/dir"
    exit 1
fi

# GFX_TARGET and LATEST_TARBALL may have been loaded from the state file;
# fall back to defaults if running standalone.
GFX_TARGET="${GFX_TARGET:-unknown}"
LATEST_TARBALL="${LATEST_TARBALL:-unknown}"

echo ""
echo "============================================================"
echo "  TheRock Installation — Verify"
echo "  $(date)"
echo "  Host: $(hostname)"
echo "============================================================"
echo ""
echo "  Install dir : $INSTALL_DIR"
echo "  GPU target  : $GFX_TARGET"
echo ""

if [ ! -d "$INSTALL_DIR" ]; then
    echo "  ERROR: Install directory does not exist: $INSTALL_DIR"
    exit 1
fi

ERRORS=0

# --- rocminfo ---
ROCMINFO="$INSTALL_DIR/bin/rocminfo"
if [ -f "$ROCMINFO" ]; then
    echo "  ✔ Found: $ROCMINFO"
    echo ""
    echo "--- rocminfo (first 50 lines) ---"
    "$ROCMINFO" 2>&1 | head -50 || true
    echo ""
else
    echo "  ✘ rocminfo NOT found at $ROCMINFO"
    ERRORS=$((ERRORS + 1))
fi

# --- test_hip_api ---
HIP_TEST="$INSTALL_DIR/bin/test_hip_api"
if [ -f "$HIP_TEST" ]; then
    echo "  ✔ Found: $HIP_TEST"
    echo ""
    echo "--- test_hip_api ---"
    "$HIP_TEST" 2>&1 | head -50 || true
    echo ""
else
    echo "  ✘ test_hip_api NOT found at $HIP_TEST"
    echo "    (searching...)"
    FOUND=$(find "$INSTALL_DIR" -name "test_hip_api" 2>/dev/null | head -3 || true)
    if [ -n "$FOUND" ]; then
        echo "    Found at: $FOUND"
        echo ""
        echo "--- test_hip_api ---"
        "$FOUND" 2>&1 | head -50 || true
    else
        ERRORS=$((ERRORS + 1))
    fi
    echo ""
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo "============================================================"
echo "  Verification Summary"
echo "------------------------------------------------------------"
echo "  GPU target  : $GFX_TARGET"
echo "  Tarball     : $LATEST_TARBALL"
echo "  Install dir : $INSTALL_DIR"
echo "  Errors      : $ERRORS"
echo ""
echo "  Useful commands:"
echo "    $INSTALL_DIR/bin/rocminfo"
echo "    $INSTALL_DIR/bin/test_hip_api"
echo "    $INSTALL_DIR/bin/hipcc --version"
echo "============================================================"

if [ "$ERRORS" -gt 0 ]; then
    echo "  WARNING: $ERRORS verification step(s) failed."
    exit 1
fi

echo "  All verification steps passed."
echo ""
