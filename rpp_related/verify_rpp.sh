#!/usr/bin/env bash
# =============================================================================
#  verify_rpp.sh  --  RPP test runner (uses installed RPP tests from ROCM_PATH)
#
#  Usage:
#    verify_rpp                   # cmake + ctest -VV in ./rpp-test/
#    verify_rpp -c                # clean build dir first, then run
#    verify_rpp -j 4              # parallel ctest jobs
#    verify_rpp --build-dir /tmp/rpp-test
#    verify_rpp --rm              # remove build dir when done
#
#  What it does:
#    1. Sources set_rocm_env.sh to resolve ROCM_PATH
#    2. Verifies ${ROCM_PATH}/share/rpp/test/ exists
#    3. mkdir rpp-test  (or --build-dir path)
#    4. cmake ${ROCM_PATH}/share/rpp/test/
#    5. ctest -VV [-j N]
# =============================================================================

set -euo pipefail

# ─── Colors / helpers ─────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GRN=$'\033[0;32m'
YLW=$'\033[0;33m'
BLU=$'\033[1;34m'
CYN=$'\033[0;36m'
MAG=$'\033[0;35m'
RST=$'\033[0m'

info()    { echo -e "${BLU}[verify_rpp]${RST} $*"; }
success() { echo -e "${GRN}[verify_rpp]${RST} $*"; }
warn()    { echo -e "${YLW}[verify_rpp]${RST} $*"; }
error()   { echo -e "${RED}[verify_rpp] ERROR:${RST} $*" >&2; }
step()    { echo -e "\n${MAG}══════════════════════════════════════════════════${RST}"; \
            echo -e "${CYN}  ▶  $*${RST}"; \
            echo -e "${MAG}══════════════════════════════════════════════════${RST}"; }

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ─── Source ROCm environment ──────────────────────────────────────────────────
SET_ROCM_ENV="${SCRIPT_DIR}/../set_rocm_env/set_rocm_env.sh"
if [[ -f "${SET_ROCM_ENV}" ]]; then
    _saved_args=("$@")
    set --
    # shellcheck source=/dev/null
    if ! source "${SET_ROCM_ENV}"; then
        set -- "${_saved_args[@]}"
        error "ROCm environment setup failed."
        error "Run: source ${SET_ROCM_ENV} /path/to/therock/install"
        exit 1
    fi
    set -- "${_saved_args[@]}"
    unset _saved_args
else
    warn "set_rocm_env.sh not found at ${SET_ROCM_ENV}"
    warn "Using existing ROCM_PATH or default /opt/rocm"
    ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
fi

# ─── Defaults ─────────────────────────────────────────────────────────────────
BUILD_DIR="${SCRIPT_DIR}/../rpp-test"
DO_CLEAN=false
DO_REMOVE=false
CTEST_JOBS=1

# ─── Help ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

  ${BLU}verify_rpp${RST} — RPP test runner

  ${CYN}Options:${RST}
    -c               Clean build directory before configuring
    -j <N>           Parallel ctest jobs  (default: 1)
    --build-dir <p>  Custom build directory  (default: ./rpp-test/)
    --rm             Remove build directory when done
    -h / --help      Show this help

  ${CYN}Examples:${RST}
    $0                     # run tests in ./rpp-test/
    $0 -c                  # clean run
    $0 -j 4                # 4 parallel test jobs
    $0 --build-dir /tmp/rpp-test --rm

EOF
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c)           DO_CLEAN=true ;;
        --rm)         DO_REMOVE=true ;;
        -j)
            shift
            if [[ -z "${1:-}" || ! "${1}" =~ ^[0-9]+$ ]]; then
                error "-j requires a numeric argument."
                exit 1
            fi
            CTEST_JOBS="$1"
            ;;
        --build-dir)
            shift
            if [[ -z "${1:-}" ]]; then
                error "--build-dir requires a path argument."
                exit 1
            fi
            BUILD_DIR="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: '$1'"
            usage
            exit 1
            ;;
    esac
    shift
done

RPP_TEST_SRC="${ROCM_PATH}/share/rpp/test"

# ─── Banner ───────────────────────────────────────────────────────────────────
echo ""
info "══════════════════════════════════════════════════"
info "  RPP Verification"
info "══════════════════════════════════════════════════"
info "  ROCM_PATH    : ${ROCM_PATH}"
info "  Test source  : ${RPP_TEST_SRC}"
info "  Build dir    : ${BUILD_DIR}"
info "  ctest jobs   : ${CTEST_JOBS}"
info "  Clean first  : ${DO_CLEAN}"
info "══════════════════════════════════════════════════"
echo ""

# ─── Validate test source ─────────────────────────────────────────────────────
if [[ ! -d "${RPP_TEST_SRC}" ]]; then
    error "RPP test directory not found: ${RPP_TEST_SRC}"
    error "Is RPP installed under ROCM_PATH? (${ROCM_PATH})"
    exit 1
fi

if [[ ! -f "${RPP_TEST_SRC}/CMakeLists.txt" ]]; then
    error "CMakeLists.txt not found in ${RPP_TEST_SRC}"
    exit 1
fi

success "RPP test source found: ${RPP_TEST_SRC}"

# ─── Clean ────────────────────────────────────────────────────────────────────
if ${DO_CLEAN} && [[ -d "${BUILD_DIR}" ]]; then
    step "Cleaning build directory: ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
    success "Build directory removed."
fi

# ─── CMake Configure ──────────────────────────────────────────────────────────
step "Configuring RPP tests with CMake"
info "Running: cmake ${RPP_TEST_SRC}"
echo ""

mkdir -p "${BUILD_DIR}"
cmake -S "${RPP_TEST_SRC}" -B "${BUILD_DIR}"

echo ""
success "CMake configuration complete."

# ─── Build ────────────────────────────────────────────────────────────────────
step "Building RPP tests"
BUILD_START=$(date +%s)
cmake --build "${BUILD_DIR}" --parallel "$(nproc 2>/dev/null || echo 8)"
BUILD_END=$(date +%s)
BUILD_ELAPSED=$(( BUILD_END - BUILD_START ))
echo ""
success "Build complete.  (elapsed: $(( BUILD_ELAPSED / 60 ))m $(( BUILD_ELAPSED % 60 ))s)"

# ─── ctest ────────────────────────────────────────────────────────────────────
step "Running ctest -VV  (jobs=${CTEST_JOBS})"
TEST_START=$(date +%s)

CTEST_EXIT=0
ctest --test-dir "${BUILD_DIR}" -VV -j "${CTEST_JOBS}" || CTEST_EXIT=$?

TEST_END=$(date +%s)
TEST_ELAPSED=$(( TEST_END - TEST_START ))

# ─── Cleanup ──────────────────────────────────────────────────────────────────
if ${DO_REMOVE}; then
    info "Removing build directory: ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [[ "${CTEST_EXIT}" -eq 0 ]]; then
    success "══════════════════════════════════════════════════"
    success "  RPP Verification PASSED"
    success "  Test time : $(( TEST_ELAPSED / 60 ))m $(( TEST_ELAPSED % 60 ))s"
    success "══════════════════════════════════════════════════"
else
    echo -e "${RED}══════════════════════════════════════════════════${RST}"
    echo -e "${RED}  RPP Verification FAILED  (ctest exit: ${CTEST_EXIT})${RST}"
    echo -e "${RED}  Build dir kept at: ${BUILD_DIR}${RST}"
    echo -e "${RED}══════════════════════════════════════════════════${RST}"
    exit "${CTEST_EXIT}"
fi
echo ""
