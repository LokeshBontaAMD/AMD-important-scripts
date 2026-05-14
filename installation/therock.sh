#!/usr/bin/env bash
# =============================================================================
# therock.sh
# Full TheRock workflow: install (download + extract) then verify.
#
# Usage:
#   therock
#   GFX_TARGET=gfx90a therock   # skip GPU auto-detection
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/install_therock.sh"
bash "$SCRIPT_DIR/verify_therock.sh"
