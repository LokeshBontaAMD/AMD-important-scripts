#!/usr/bin/env bash
# =============================================================================
# install_therock.sh
# Detects GPU architecture, downloads the matching latest TheRock nightly
# tarball, and extracts it.  Stops before verification.
#
# Usage:
#   bash install_therock.sh
#   GFX_TARGET=gfx90a bash install_therock.sh   # skip auto-detection
#
# Installs into:
#   $SCRATCH_ROOT/therock-tarballs/therock-tarball-$GFX-$TIMESTAMP/
#
# On success writes install state to $SCRATCH_ROOT/.therock_last_install
# so that verify_therock.sh / set_rocm_env.sh can pick it up automatically.
# =============================================================================

set -euo pipefail

SCRATCH_ROOT="${SCRATCH_ROOT:-/scratch/users/${USER}}"
TARBALLS_DIR="${SCRATCH_ROOT}/therock-tarballs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BASE_URL="https://therock-nightly-tarball.s3.amazonaws.com"
STATE_FILE="${SCRATCH_ROOT}/.therock_last_install"

echo ""
echo "============================================================"
echo "  TheRock Nightly Tarball — Install"
echo "  $(date)"
echo "  Host: $(hostname)"
echo "  Tarballs dir: ${TARBALLS_DIR}"
echo "============================================================"
echo ""

mkdir -p "${TARBALLS_DIR}"

# -----------------------------------------------------------------------------
# STEP 1 — Detect GPU architecture
# -----------------------------------------------------------------------------
if [ -n "${GFX_TARGET:-}" ]; then
    echo "[1/4] GFX_TARGET already set — skipping detection."
    echo "  Using: $GFX_TARGET"
else
    echo "[1/4] Detecting GPU architecture..."

    detect_gfx_rocmsmi() {
        command -v rocm-smi &>/dev/null || return 1
        local gfx
        gfx=$(rocm-smi --showproductname 2>/dev/null \
              | grep -i "GFX Version" | head -1 | awk '{print $NF}')
        [ -z "$gfx" ] && return 1
        case "$gfx" in
            gfx94*)  echo "gfx94X-dcgpu" ;;
            gfx90a)  echo "gfx90a"       ;;
            gfx908)  echo "gfx908"       ;;
            gfx906)  echo "gfx906"       ;;
            gfx900)  echo "gfx900"       ;;
            gfx120*) echo "gfx120X-all"  ;;
            gfx110*) echo "gfx110X-all"  ;;
            gfx103*) echo "gfx103X-all"  ;;
            gfx803)  echo "gfx803"       ;;
            *)       echo "UNKNOWN"      ;;
        esac
    }

    PCI_INFO=$(lspci 2>/dev/null \
        | grep -i -E "VGA|3D|Display|Radeon|NVIDIA|Instinct|AMD|Advanced Micro" \
        | grep -v "Host bridge" \
        | grep -v "ASPEED" || true)

    echo "  PCI GPU devices found:"
    echo "$PCI_INFO" | sed 's/^/      /'
    echo ""

    detect_gfx_lspci() {
        if echo "$PCI_INFO" | grep -qi "MI300X\|Device 74a0\|0x74a0"; then
            echo "gfx94X-dcgpu"
        elif echo "$PCI_INFO" | grep -qi "MI300A\|Device 74a1\|0x74a1"; then
            echo "gfx94X-dcgpu"
        elif echo "$PCI_INFO" | grep -qi "MI325\|Device 74a5\|0x74a5\|Device 74b5\|0x74b5"; then
            echo "gfx94X-dcgpu"
        elif echo "$PCI_INFO" | grep -qi "MI210\|MI250\|Aldebaran\|MI200\|gfx90a\|Device 740c\|0x740c\|Device 740f\|0x740f"; then
            echo "gfx90a"
        elif echo "$PCI_INFO" | grep -qi "MI100\|Arcturus\|gfx908\|Device 738c\|0x738c"; then
            echo "gfx908"
        elif echo "$PCI_INFO" | grep -qi "MI60\|MI50\|Vega20\|gfx906"; then
            echo "gfx906"
        elif echo "$PCI_INFO" | grep -qi "Vega10\|gfx900\|Instinct MI25\|Device 6860"; then
            echo "gfx900"
        elif echo "$PCI_INFO" | grep -qi "RX 90\|RX 91\|Navi 4\|gfx1200\|gfx1201\|gfx120\|Device 7550\|Device 754\|Device 755"; then
            echo "gfx120X-all"
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

    GFX_TARGET=$(detect_gfx_rocmsmi 2>/dev/null || true)
    if [ -z "$GFX_TARGET" ] || [ "$GFX_TARGET" = "UNKNOWN" ]; then
        echo "  rocm-smi detection failed or unavailable; falling back to lspci..."
        GFX_TARGET=$(detect_gfx_lspci)
    else
        echo "  rocm-smi detected: $GFX_TARGET"
    fi

    if [ "$GFX_TARGET" = "UNKNOWN" ]; then
        echo "  ERROR: Could not auto-detect GPU architecture."
        echo "  Please set GFX_TARGET manually and re-run:"
        echo "    GFX_TARGET=gfx90a bash install_therock.sh"
        exit 1
    fi
fi

echo "  GPU architecture: $GFX_TARGET"
echo ""

THEROCK_DIR="${TARBALLS_DIR}/therock-tarball-${GFX_TARGET}-${TIMESTAMP}"
INSTALL_DIR="${THEROCK_DIR}/install"

echo "  Installation directory: $THEROCK_DIR"
echo ""

# -----------------------------------------------------------------------------
# STEP 2 — Find latest tarball for this target
# -----------------------------------------------------------------------------
echo "[2/4] Querying S3 index for latest tarball matching '$GFX_TARGET'..."

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
# STEP 3 — Download
# -----------------------------------------------------------------------------
echo "[3/4] Preparing installation directory at $THEROCK_DIR ..."
mkdir -p "$THEROCK_DIR"

DEST="$THEROCK_DIR/$LATEST_TARBALL"

tarball_ok() {
    gzip -t "$1" 2>/dev/null
}

# Reuse an existing valid tarball from a prior install to avoid re-downloading
EXISTING_TARBALL=""
EXISTING_TARBALL=$(find "${TARBALLS_DIR}" -maxdepth 2 -name "$LATEST_TARBALL" -type f 2>/dev/null | head -1 || true)

if [ -n "$EXISTING_TARBALL" ] && [ -f "$EXISTING_TARBALL" ]; then
    FILESIZE=$(du -sh "$EXISTING_TARBALL" | cut -f1)
    echo "  Found existing tarball at $EXISTING_TARBALL ($FILESIZE)"
    echo "  Verifying integrity..."
    if tarball_ok "$EXISTING_TARBALL"; then
        echo "  OK — copying to $DEST ..."
        cp "$EXISTING_TARBALL" "$DEST"
    else
        echo "  WARNING: existing tarball is corrupted — downloading fresh copy."
        EXISTING_TARBALL=""
    fi
fi

if [ -z "$EXISTING_TARBALL" ]; then
    if [ -f "$DEST" ]; then
        FILESIZE=$(du -sh "$DEST" | cut -f1)
        echo "  Tarball already at destination ($FILESIZE) — verifying integrity..."
        if tarball_ok "$DEST"; then
            echo "  OK — skipping download."
        else
            echo "  WARNING: destination tarball is corrupted — re-downloading."
            rm -f "$DEST"
        fi
    fi

    if [ ! -f "$DEST" ]; then
        echo "  Downloading (~$(curl -sI "$TARBALL_URL" | grep -i content-length | awk '{printf "%.1f GB", $2/1073741824}' || echo 'unknown size'))..."
        echo "  Please wait..."
        wget -c "$TARBALL_URL" -O "$DEST" --progress=dot:giga 2>&1
        echo "  Download complete."
    fi
fi
echo ""

# -----------------------------------------------------------------------------
# STEP 4 — Extract
# -----------------------------------------------------------------------------
echo "[4/4] Extracting tarball to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

echo "  Running: tar -xf $DEST -C $INSTALL_DIR"
tar -xf "$DEST" -C "$INSTALL_DIR"

echo "  Extraction complete. Top-level contents:"
ls "$INSTALL_DIR" | sed 's/^/    /'
echo ""

# -----------------------------------------------------------------------------
# Save state for verify_therock.sh / set_rocm_env.sh
# -----------------------------------------------------------------------------
cat > "$STATE_FILE" <<EOF
INSTALL_DIR=$INSTALL_DIR
GFX_TARGET=$GFX_TARGET
LATEST_TARBALL=$LATEST_TARBALL
EOF

echo "============================================================"
echo "  Install Complete"
echo "------------------------------------------------------------"
echo "  GPU target  : $GFX_TARGET"
echo "  Tarball     : $LATEST_TARBALL"
echo "  Install dir : $INSTALL_DIR"
echo ""
echo "  Run verification:"
echo "    verify_therock"
echo "  Or run both together:"
echo "    therock"
echo "============================================================"
echo ""
