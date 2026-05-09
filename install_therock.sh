#!/usr/bin/env bash
# =============================================================================
# install_therock.sh
# Auto-detects GPU architecture, downloads the matching latest TheRock nightly
# tarball into $SCRATCH_ROOT/therock-tarball/, extracts it, and verifies.
# =============================================================================

set -euo pipefail

SCRATCH_ROOT="${SCRATCH_ROOT:-/scratch/users/lbonta}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
# THEROCK_DIR will be set after GPU detection: therock-tarball-$GFX_TARGET-$TIMESTAMP
BASE_URL="https://therock-nightly-tarball.s3.amazonaws.com"

echo ""
echo "============================================================"
echo "  TheRock Nightly Tarball — Auto Install"
echo "  $(date)"
echo "  Host: $(hostname)"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------------
# STEP 1 — Detect GPU architecture
# -----------------------------------------------------------------------------
echo "[1/5] Detecting GPU architecture from lspci..."

PCI_INFO=$(lspci 2>/dev/null \
    | grep -i -E "VGA|3D|Display|Radeon|NVIDIA|Instinct" \
    | grep -v "Host bridge" \
    | grep -v "ASPEED" || true)

echo "  PCI GPU devices found:"
echo "$PCI_INFO" | sed 's/^/      /'
echo ""

detect_gfx() {
    # Priority: dcgpu / datacenter cards first, then consumer
    if echo "$PCI_INFO" | grep -qi "MI300X\|Device 74a0\|0x74a0"; then
        echo "gfx94X-dcgpu"
    elif echo "$PCI_INFO" | grep -qi "MI300A\|Device 74a1\|0x74a1"; then
        echo "gfx94X-dcgpu"
    elif echo "$PCI_INFO" | grep -qi "MI325\|Device 74b5\|0x74b5"; then
        echo "gfx94X-dcgpu"
    elif echo "$PCI_INFO" | grep -qi "MI210\|MI250\|Aldebaran\|MI200\|gfx90a\|Device 740c\|0x740c"; then
        echo "gfx90a"
    elif echo "$PCI_INFO" | grep -qi "MI100\|Arcturus\|gfx908\|Device 738c\|0x738c"; then
        echo "gfx908"
    elif echo "$PCI_INFO" | grep -qi "MI60\|MI50\|Vega20\|gfx906"; then
        echo "gfx906"
    elif echo "$PCI_INFO" | grep -qi "Vega10\|gfx900\|Instinct MI25\|Device 6860"; then
        echo "gfx900"
    elif echo "$PCI_INFO" | grep -qi "RX 79\|RX 78\|RX 77\|RX 76\|Navi3\|gfx1100\|gfx1101\|gfx1102\|gfx110"; then
        echo "gfx110X-all"
    elif echo "$PCI_INFO" | grep -qi "RX 69\|RX 68\|RX 67\|RX 66\|Navi2\|gfx1030\|gfx1031\|gfx1032\|gfx103"; then
        echo "gfx103X-all"
    elif echo "$PCI_INFO" | grep -qi "RX 580\|RX 570\|RX 560\|Polaris\|gfx803"; then
        echo "gfx803"
    else
        echo "UNKNOWN"
    fi
}

GFX_TARGET=$(detect_gfx)

if [ "$GFX_TARGET" = "UNKNOWN" ]; then
    echo "  ERROR: Could not auto-detect GPU architecture."
    echo "  Please set GFX_TARGET manually and re-run:"
    echo "    GFX_TARGET=gfx90a bash install_therock.sh"
    exit 1
fi

echo "  Detected GPU architecture: $GFX_TARGET"
echo ""

# Set THEROCK_DIR now that we know the GPU target
THEROCK_DIR="$SCRATCH_ROOT/therock-tarball-$GFX_TARGET-$TIMESTAMP"
INSTALL_DIR="$THEROCK_DIR/install"

echo "  Installation directory: $THEROCK_DIR"
echo ""

# -----------------------------------------------------------------------------
# STEP 2 — Find latest tarball for this target
# -----------------------------------------------------------------------------
echo "[2/5] Querying S3 index for latest linux tarball matching '$GFX_TARGET'..."

# Parse the embedded JSON from the index page, extract name+mtime, pick latest
LATEST_TARBALL=$(curl -s "$BASE_URL/index.html" | \
    python3 -c "
import sys, json, re

html = sys.stdin.read()
m = re.search(r'const files = (\[.*?\]);', html, re.DOTALL)
if not m:
    print('PARSE_ERROR')
    sys.exit(1)

files = json.loads(m.group(1))
target = 'therock-dist-linux-${GFX_TARGET}-'
matches = [f for f in files if f['name'].startswith(target) and f['name'].endswith('.tar.gz')]

if not matches:
    print('NOT_FOUND')
    sys.exit(1)

# Sort by mtime descending, pick the newest
latest = sorted(matches, key=lambda f: f['mtime'], reverse=True)[0]
print(latest['name'])
")

if [ "$LATEST_TARBALL" = "PARSE_ERROR" ]; then
    echo "  ERROR: Could not parse S3 index page."
    exit 1
fi

if [ "$LATEST_TARBALL" = "NOT_FOUND" ]; then
    echo "  ERROR: No tarball found for target '$GFX_TARGET'."
    exit 1
fi

TARBALL_URL="$BASE_URL/$LATEST_TARBALL"
echo "  Latest tarball: $LATEST_TARBALL"
echo "  URL: $TARBALL_URL"
echo ""

# -----------------------------------------------------------------------------
# STEP 3 — Download (skip if already present in SCRATCH_ROOT or prior install)
# -----------------------------------------------------------------------------
echo "[3/5] Preparing installation directory at $THEROCK_DIR ..."
mkdir -p "$THEROCK_DIR"

DEST="$THEROCK_DIR/$LATEST_TARBALL"

# Check if tarball exists in SCRATCH_ROOT or any prior therock-tarball-* directory
EXISTING_TARBALL=""
if [ -f "$SCRATCH_ROOT/$LATEST_TARBALL" ]; then
    EXISTING_TARBALL="$SCRATCH_ROOT/$LATEST_TARBALL"
else
    # Search in prior therock-tarball-* directories
    EXISTING_TARBALL=$(find "$SCRATCH_ROOT" -maxdepth 2 -name "$LATEST_TARBALL" -type f 2>/dev/null | head -1 || true)
fi

if [ -n "$EXISTING_TARBALL" ] && [ -f "$EXISTING_TARBALL" ]; then
    FILESIZE=$(du -sh "$EXISTING_TARBALL" | cut -f1)
    echo "  Found existing tarball at $EXISTING_TARBALL ($FILESIZE)"
    echo "  Copying to $DEST ..."
    cp "$EXISTING_TARBALL" "$DEST"
elif [ -f "$DEST" ]; then
    FILESIZE=$(du -sh "$DEST" | cut -f1)
    echo "  Tarball already present ($FILESIZE) — skipping download."
else
    echo "  Downloading (~$(curl -sI "$TARBALL_URL" | grep -i content-length | awk '{printf "%.1f GB", $2/1073741824}' || echo 'unknown size'))..."
    echo "  Please wait..."
    wget -c "$TARBALL_URL" -O "$DEST" --progress=dot:giga 2>&1
    echo "  Download complete."
fi
echo ""

# -----------------------------------------------------------------------------
# STEP 4 — Extract
# -----------------------------------------------------------------------------
echo "[4/5] Extracting tarball to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

echo "  Running: tar -xf $DEST -C $INSTALL_DIR"
tar -xf "$DEST" -C "$INSTALL_DIR"

echo "  Extraction complete. Top-level contents:"
ls "$INSTALL_DIR" | sed 's/^/    /'
echo ""

# -----------------------------------------------------------------------------
# STEP 5 — Verify installation
# -----------------------------------------------------------------------------
echo "[5/5] Verifying installation..."
echo ""

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
    echo "    (may be in a different path — searching...)"
    FOUND=$(find "$INSTALL_DIR" -name "test_hip_api" 2>/dev/null | head -3)
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
echo "  Installation Summary"
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
