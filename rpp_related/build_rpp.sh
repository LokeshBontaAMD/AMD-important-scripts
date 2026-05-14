#!/usr/bin/env bash
# =============================================================================
#  build_rpp.sh  --  RPP build helper
#
#  Usage:
#    build_rpp -r              release incremental build
#    build_rpp -r -i           release incremental build + install
#    build_rpp -c -r           clean release build
#    build_rpp -c -r -i        clean release build + install
#    build_rpp -d              debug incremental build
#    build_rpp -d -i           debug incremental build + install
#    build_rpp -c -d           clean debug build
#    build_rpp -c -d -i        clean debug build + install
#
#  Backend (optional, default = HIP):
#    -hip   HIP backend
#    -cpu   CPU backend
#    -ocl   OpenCL backend  (requires -legacy flag)
#
#  Extra options:
#    -j <N>      parallel jobs  (default = nproc)
#    -prefix     custom install prefix  (default = rpp-install/)
#    -legacy     enable RPP_LEGACY_SUPPORT
#    -noaudio    disable RPP_AUDIO_SUPPORT
#    -h / --help show this help
#
#  Standalone modes:
#    --config        Print full configuration + run pre-flight checks, then exit
#
#  Notes:
#    -r and -d cannot be used together.
# =============================================================================

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GRN=$'\033[0;32m'
YLW=$'\033[0;33m'
BLU=$'\033[1;34m'
CYN=$'\033[0;36m'
MAG=$'\033[0;35m'
RST=$'\033[0m'

info()    { echo -e "${BLU}[build_rpp]${RST} $*"; }
success() { echo -e "${GRN}[build_rpp]${RST} $*"; }
warn()    { echo -e "${YLW}[build_rpp]${RST} $*"; }
error()   { echo -e "${RED}[build_rpp] ERROR:${RST} $*" >&2; }
step()    { echo -e "\n${MAG}══════════════════════════════════════════════════${RST}"; \
            echo -e "${CYN}  ▶  $*${RST}"; \
            echo -e "${MAG}══════════════════════════════════════════════════${RST}"; }

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ─── Source ROCm environment ──────────────────────────────────────────────────
SET_ROCM_ENV="${SCRIPT_DIR}/../set_rocm_env/set_rocm_env.sh"
if [[ -f "${SET_ROCM_ENV}" ]]; then
    # set_rocm_env.sh uses $1 as the therock install path.
    # We must clear positional params before sourcing so our CLI args
    # (e.g. --config, -r) are not picked up as the therock path.
    _saved_args=("$@")
    set --
    # shellcheck source=/dev/null
    if ! source "${SET_ROCM_ENV}"; then
        set -- "${_saved_args[@]}"
        error "ROCm environment setup failed — the therock install path does not exist."
        error "Edit set_rocm_env.sh and set a valid path, or run:"
        error "  source ${SET_ROCM_ENV} /path/to/therock/install"
        exit 1
    fi
    set -- "${_saved_args[@]}"
    unset _saved_args
else
    warn "set_rocm_env.sh not found at ${SET_ROCM_ENV}"
    warn "Using existing ROCM_PATH or default /opt/rocm"
    ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
fi

# ─── RPP source resolution ────────────────────────────────────────────────────
# Priority: RPP_SOURCE env var  >  AMD-stack/rpp  >  interactive prompt
AMD_STACK_DIR="$(readlink -f "${SCRIPT_DIR}/../../AMD-stack")"
if [[ -n "${RPP_SOURCE:-}" ]]; then
    RPP_SRC="$(readlink -f "${RPP_SOURCE}")"
    info "RPP source (RPP_SOURCE) : ${RPP_SRC}"
elif [[ -d "${AMD_STACK_DIR}/rpp" ]]; then
    RPP_SRC="${AMD_STACK_DIR}/rpp"
    info "RPP source (AMD-stack)  : ${RPP_SRC}"
else
    warn "RPP not found in AMD-stack (${AMD_STACK_DIR}/rpp)."
    read -r -p "  Enter path to RPP source directory: " _RPP_INPUT
    if [[ -z "${_RPP_INPUT}" ]]; then
        error "No path provided. Aborting."
        exit 1
    fi
    RPP_SRC="$(readlink -f "${_RPP_INPUT}")"
    if [[ ! -d "${RPP_SRC}" ]]; then
        error "Directory does not exist: ${RPP_SRC}"
        exit 1
    fi
    info "RPP source (user)       : ${RPP_SRC}"
fi

RPP_BUILD="${RPP_SRC}/build"

# ─── Defaults ─────────────────────────────────────────────────────────────────
BUILD_TYPE=""
FLAG_R=false
FLAG_D=false
DO_CLEAN=false
DO_INSTALL=false
DO_CONFIG_ONLY=false
BACKEND="HIP"
JOBS="$(nproc 2>/dev/null || echo 8)"
# Default install prefix = ROCM_PATH set by set_rocm_env.sh
INSTALL_PREFIX="${ROCM_PATH}"
LEGACY_SUPPORT="OFF"
AUDIO_SUPPORT="ON"

# ─── Help ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

  ${BLU}build_rpp${RST} - RPP build helper script

  ${CYN}Build type (default: -r):${RST}
    -r              Release build  (default when no args given)
    -d              Debug build
    (-r and -d cannot be used together)

  ${CYN}Build mode:${RST}
    -c              Clean build (remove build directory first)
    -i              Install after building

  ${CYN}Backend (optional, default=HIP):${RST}
    -hip            HIP backend  (default)
    -cpu            CPU/HOST backend
    -ocl            OpenCL backend  (auto-enables legacy support)

  ${CYN}Extra options:${RST}
    -j <N>          Parallel jobs (default: $(nproc))
    -prefix <path>  Custom install prefix  (default: rpp-install/)
    -legacy         Enable RPP_LEGACY_SUPPORT
    -noaudio        Disable RPP_AUDIO_SUPPORT
    -h / --help     Show this help

  ${CYN}Standalone:${RST}
    --config        Print build config + run pre-flight checks, then exit
                    (combine with backend/prefix flags to inspect a config)

  ${CYN}Examples:${RST}
    $0 -r                  # release incremental build
    $0 -r -i               # release incremental build + install
    $0 -c -r               # clean release build
    $0 -c -r -i            # clean release build + install
    $0 -d                  # debug incremental build
    $0 -c -d -i -cpu       # clean debug build, CPU backend, install
    $0 -r -ocl             # release with OpenCL backend
    $0 -r -j 16 -prefix /opt/rocm    # 16 jobs, custom prefix

EOF
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    BUILD_TYPE="Release"
    FLAG_R=true
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r)       BUILD_TYPE="Release"; FLAG_R=true ;;
        -d)       BUILD_TYPE="Debug";   FLAG_D=true ;;
        -c)       DO_CLEAN=true ;;
        -i)       DO_INSTALL=true ;;
        -hip)     BACKEND="HIP" ;;
        -cpu)     BACKEND="CPU" ;;
        -ocl)     BACKEND="OCL"; LEGACY_SUPPORT="ON" ;;
        -legacy)  LEGACY_SUPPORT="ON" ;;
        -noaudio) AUDIO_SUPPORT="OFF" ;;
        -j)
            shift
            if [[ -z "${1:-}" || ! "${1}" =~ ^[0-9]+$ ]]; then
                error "-j requires a numeric argument."
                exit 1
            fi
            JOBS="$1"
            ;;
        -prefix)
            shift
            if [[ -z "${1:-}" ]]; then
                error "-prefix requires a path argument."
                exit 1
            fi
            INSTALL_PREFIX="$1"
            ;;
        --config)   DO_CONFIG_ONLY=true ;;
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

# ─── Validate ─────────────────────────────────────────────────────────────────
if [[ -z "${BUILD_TYPE}" ]] && ! ${DO_CONFIG_ONLY}; then
    error "You must specify a build type: -r (Release) or -d (Debug)."
    usage
    exit 1
fi

if ${FLAG_R} && ${FLAG_D}; then
    error "-r (Release) and -d (Debug) cannot be used together."
    exit 1
fi

if [[ ! -d "${RPP_SRC}" ]]; then
    error "RPP source directory not found: ${RPP_SRC}"
    error "Set: export RPP_SOURCE=/path/to/rpp"
    exit 1
fi

if [[ ! -f "${RPP_SRC}/CMakeLists.txt" ]]; then
    error "CMakeLists.txt not found in ${RPP_SRC}"
    error "Is ${RPP_SRC} the correct RPP source tree?"
    exit 1
fi

# ─── Pre-flight Checks ────────────────────────────────────────────────────────
preflight_checks() {
    local HAVE_ERROR=false

    step "Pre-flight environment checks"

    # ── 1. Architecture ──────────────────────────────────────────────────────
    info "[1/10] Architecture ..."
    local ARCH
    ARCH="$(uname -m)"
    if [[ "${ARCH}" == "x86_64" ]]; then
        success "  Architecture : ${ARCH}  (AMD64 ✓)"
    else
        warn "  Architecture : ${ARCH}  (expected x86_64/AMD64 — proceeding anyway)"
    fi

    # ── 2. OS ─────────────────────────────────────────────────────────────────
    info "[2/10] Operating system ..."
    local OS_NAME OS_VER OS_ID
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_NAME="${NAME:-unknown}"
        OS_VER="${VERSION_ID:-unknown}"
    else
        OS_ID="unknown"; OS_NAME="unknown"; OS_VER="unknown"
    fi

    case "${OS_ID}" in
        ubuntu)
            case "${OS_VER}" in
                22.04|24.04)
                    success "  OS : ${OS_NAME} ${OS_VER}  ✓" ;;
                *)
                    warn "  OS : ${OS_NAME} ${OS_VER}  (supported: 22.04, 24.04)" ;;
            esac
            ;;
        rhel|centos|almalinux|rocky)
            local RHEL_MAJOR="${OS_VER%%.*}"
            if [[ "${RHEL_MAJOR}" == "8" || "${RHEL_MAJOR}" == "9" ]]; then
                success "  OS : ${OS_NAME} ${OS_VER}  ✓"
            else
                warn "  OS : ${OS_NAME} ${OS_VER}  (supported RHEL: 8, 9)"
            fi
            ;;
        sles|opensuse-leap)
            if [[ "${OS_VER}" == 15* ]]; then
                success "  OS : ${OS_NAME} ${OS_VER}  ✓"
            else
                warn "  OS : ${OS_NAME} ${OS_VER}  (supported SLES: 15 SP7)"
            fi
            ;;
        *)
            warn "  OS : ${OS_NAME} ${OS_VER}  (not in supported list: Ubuntu 22.04/24.04, RHEL 8/9, SLES 15 SP7)"
            ;;
    esac

    # ── 3. CMake ──────────────────────────────────────────────────────────────
    info "[3/10] CMake (>= 3.10) ..."
    if command -v cmake &>/dev/null; then
        local CMAKE_VER
        CMAKE_VER="$(cmake --version | head -1 | awk '{print $3}')"
        local CMAKE_MAJOR CMAKE_MINOR
        CMAKE_MAJOR="${CMAKE_VER%%.*}"
        CMAKE_MINOR="${CMAKE_VER#*.}"; CMAKE_MINOR="${CMAKE_MINOR%%.*}"
        if (( CMAKE_MAJOR > 3 )) || (( CMAKE_MAJOR == 3 && CMAKE_MINOR >= 10 )); then
            success "  CMake : ${CMAKE_VER}  ✓"
        else
            error "  CMake : ${CMAKE_VER}  (need >= 3.10)"
            HAVE_ERROR=true
        fi
    else
        error "  CMake : not found  (install: sudo apt install cmake)"
        HAVE_ERROR=true
    fi

    # ── 4. Compiler + C++17 ───────────────────────────────────────────────────
    info "[4/10] Compiler ..."
    local ROCM_PATH_LOCAL="${ROCM_PATH:-/opt/rocm}"
    local ACTIVE_CXX=""
    if [[ "${BACKEND}" == "HIP" ]]; then
        # AMD Clang++ >= 18.0.0
        local AMD_CLANGPP="${ROCM_PATH_LOCAL}/bin/amdclang++"
        if [[ -x "${AMD_CLANGPP}" ]]; then
            local AMDCLANG_VER
            AMDCLANG_VER="$("${AMD_CLANGPP}" --version 2>&1 | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)"
            local AMDCLANG_MAJOR="${AMDCLANG_VER%%.*}"
            if (( AMDCLANG_MAJOR >= 18 )); then
                success "  AMD Clang++ : ${AMDCLANG_VER}  (${AMD_CLANGPP})  ✓"
            else
                warn "  AMD Clang++ : ${AMDCLANG_VER}  (need >= 18.0.0 — HIP backend may fail)"
            fi
            ACTIVE_CXX="${AMD_CLANGPP}"
        else
            warn "  AMD Clang++ not found at ${AMD_CLANGPP}"
            warn "  Falling back to system clang++ for HIP backend (may not work)"
            if command -v clang++ &>/dev/null; then
                local CLANG_VER
                CLANG_VER="$(clang++ --version 2>&1 | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)"
                info "  System clang++ : ${CLANG_VER}"
                ACTIVE_CXX="clang++"
            fi
        fi
    else
        # CPU / OCL backend — Clang >= 5.0.1
        local CLANGPP_BIN="${ROCM_PATH_LOCAL}/bin/amdclang++"
        if [[ -x "${CLANGPP_BIN}" ]]; then
            local CLANG_VER
            CLANG_VER="$("${CLANGPP_BIN}" --version 2>&1 | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)"
            success "  AMD Clang++ : ${CLANG_VER}  (${CLANGPP_BIN})  ✓"
            ACTIVE_CXX="${CLANGPP_BIN}"
        elif command -v clang++ &>/dev/null; then
            local CLANG_VER
            CLANG_VER="$(clang++ --version 2>&1 | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1)"
            local CLANG_MAJOR="${CLANG_VER%%.*}"
            if (( CLANG_MAJOR >= 5 )); then
                success "  clang++ : ${CLANG_VER}  ✓"
            else
                warn "  clang++ : ${CLANG_VER}  (need >= 5.0.1 for CPU backend)"
            fi
            ACTIVE_CXX="clang++"
        else
            warn "  clang++ not found  (install: sudo apt install clang)"
        fi
    fi

    # ── 4b. C++17 support ─────────────────────────────────────────────────────
    info "[4b/10] C++17 support (required) ..."
    if [[ -n "${ACTIVE_CXX}" ]]; then
        local CXX17_TMPFILE
        CXX17_TMPFILE="$(mktemp /tmp/rpp_cxx17_XXXXXX.cpp)"
        cat > "${CXX17_TMPFILE}" <<'CXXEOF'
#include <optional>
#include <string_view>
#include <variant>
int main() {
    std::optional<int> x = 42;
    std::string_view sv = "ok";
    std::variant<int,float> v = 1;
    return 0;
}
CXXEOF
        if "${ACTIVE_CXX}" -std=c++17 "${CXX17_TMPFILE}" -o /dev/null 2>/dev/null; then
            success "  C++17 : supported by ${ACTIVE_CXX}  ✓"
        else
            error "  C++17 : NOT supported by ${ACTIVE_CXX}  (RPP requires C++17)"
            HAVE_ERROR=true
        fi
        rm -f "${CXX17_TMPFILE}"
    else
        warn "  C++17 : cannot check — no compiler found"
    fi

    # ── 5. ROCm + HIP dev (HIP backend only) ─────────────────────────────────
    if [[ "${BACKEND}" == "HIP" ]]; then
        info "[5/10] ROCm installation (>= 7.0.0, HIP backend) ..."
        local ROCM_VER_FILE="${ROCM_PATH_LOCAL}/.info/version"
        if [[ -f "${ROCM_VER_FILE}" ]]; then
            local ROCM_VER
            ROCM_VER="$(cat "${ROCM_VER_FILE}")"
            local ROCM_MAJOR="${ROCM_VER%%.*}"
            if (( ROCM_MAJOR >= 7 )); then
                success "  ROCm : ${ROCM_VER}  (${ROCM_PATH_LOCAL})  ✓"
            else
                warn "  ROCm : ${ROCM_VER}  (need >= 7.0.0 for HIP backend)"
            fi
        elif [[ -d "${ROCM_PATH_LOCAL}" ]]; then
            warn "  ROCm directory found at ${ROCM_PATH_LOCAL} but version file missing"
            warn "  Run: sudo amdgpu-install --usecase=rocm"
        else
            error "  ROCm not found at ${ROCM_PATH_LOCAL}  (install ROCm 7.0.0+)"
            error "  Run: sudo amdgpu-install --usecase=rocm"
            HAVE_ERROR=true
        fi

        # GPU presence + gfx908+
        # Known ROCm-supported targets (gfx908 or newer):
        #   CDNA1: gfx908   CDNA2: gfx90a   CDNA3: gfx940/941/942
        #   RDNA3: gfx1100/1101/1102   RDNA4: gfx1200/1201
        local SUPPORTED_GFX_TARGETS=(
            gfx908 gfx90a
            gfx940 gfx941 gfx942
            gfx1100 gfx1101 gfx1102
            gfx1200 gfx1201
        )
        is_supported_gfx() {
            local tgt="$1"
            for s in "${SUPPORTED_GFX_TARGETS[@]}"; do
                [[ "${tgt}" == "${s}" ]] && return 0
            done
            return 1
        }

        # hip-dev: check well-known locations for hip/hip_runtime.h
        info "  Checking hip-dev (hip/hip_runtime.h) ..."
        local HIP_RUNTIME_H=""
        for _h in \
            "${ROCM_PATH_LOCAL}/include/hip/hip_runtime.h" \
            "/usr/include/hip/hip_runtime.h" \
            "/usr/local/include/hip/hip_runtime.h"; do
            if [[ -f "${_h}" ]]; then HIP_RUNTIME_H="${_h}"; break; fi
        done
        if [[ -n "${HIP_RUNTIME_H}" ]]; then
            success "  hip-dev : ${HIP_RUNTIME_H}  ✓"
        else
            warn "  hip-dev : hip/hip_runtime.h not found  (install: sudo apt install hip-dev)"
        fi

        info "  Checking GPU (gfx908 or higher required) ..."
        local ROCMINFO_BIN
        if command -v rocminfo &>/dev/null; then
            ROCMINFO_BIN="rocminfo"
        elif [[ -x "${ROCM_PATH_LOCAL}/bin/rocminfo" ]]; then
            ROCMINFO_BIN="${ROCM_PATH_LOCAL}/bin/rocminfo"
        else
            ROCMINFO_BIN=""
        fi

        if [[ -n "${ROCMINFO_BIN}" ]]; then
            local GPU_GFX
            # capture gfx followed by hex digits and optional trailing letter (e.g. gfx90a)
            GPU_GFX="$(${ROCMINFO_BIN} 2>/dev/null | grep -oP 'gfx[0-9a-fA-F]+[a-z]?' | sort -u | tr '\n' ' ')"
            if [[ -n "${GPU_GFX}" ]]; then
                for GFX in ${GPU_GFX}; do
                    if is_supported_gfx "${GFX}"; then
                        success "  GPU : ${GFX}  ✓  (supported ROCm HIP target)"
                    else
                        warn "  GPU : ${GFX}  (not in known-supported list — gfx908/90a/940/941/942/1100/1101/1102/1200/1201)"
                    fi
                done
            else
                warn "  No AMD GPU detected via rocminfo  (HIP backend may not work)"
            fi
        else
            warn "  rocminfo not found — cannot verify GPU  (is ROCm fully installed?)"
        fi
    else
        info "[5/10] ROCm / hip-dev check : skipped (backend=${BACKEND})"
    fi

    # ── 6. half library (>= 1.12.0) ──────────────────────────────────────────
    info "[6/10] Half-precision library (half, >= 1.12.0) ..."
    # Check well-known locations first to avoid slow find over large ROCm tree
    local HALF_HEADER=""
    for _h in \
        "/usr/include/half.hpp" \
        "/usr/local/include/half.hpp" \
        "${ROCM_PATH_LOCAL}/include/half.hpp" \
        "/usr/include/half/half.hpp"; do
        if [[ -f "${_h}" ]]; then HALF_HEADER="${_h}"; break; fi
    done
    # Fallback: shallow find (maxdepth 3) if not found above
    if [[ -z "${HALF_HEADER}" ]]; then
        HALF_HEADER="$(find /usr/include /usr/local/include -maxdepth 3 -name "half.hpp" 2>/dev/null | head -1)"
    fi
    if [[ -n "${HALF_HEADER}" ]]; then
        local HALF_VER
        HALF_VER="$(grep -oP 'HALF_VERSION_\w+\s+\K[0-9]+' "${HALF_HEADER}" 2>/dev/null | head -3 | tr '\n' '.' | sed 's/\.$//')"
        if [[ -n "${HALF_VER}" ]]; then
            success "  half : ${HALF_HEADER}  (ver tokens: ${HALF_VER})  ✓"
        else
            success "  half : ${HALF_HEADER}  ✓"
        fi
    else
        warn "  half.hpp not found  (install: sudo apt install half)"
    fi

    # ── 7. OpenMP ─────────────────────────────────────────────────────────────
    info "[7/10] OpenMP ..."
    # Check well-known locations; avoid slow recursive find
    local OMP_HEADER=""
    for _h in \
        "/usr/include/omp.h" \
        "/usr/local/include/omp.h" \
        "${ROCM_PATH_LOCAL}/llvm/lib/clang/$(ls "${ROCM_PATH_LOCAL}/llvm/lib/clang/" 2>/dev/null | head -1)/include/omp.h" \
        "/usr/lib/llvm-*/include/omp.h"; do
        # shellcheck disable=SC2086
        for _expanded in ${_h}; do
            if [[ -f "${_expanded}" ]]; then OMP_HEADER="${_expanded}"; break 2; fi
        done
    done
    if [[ -n "${OMP_HEADER}" ]]; then
        success "  OpenMP : ${OMP_HEADER}  ✓"
    else
        # Compile-test with the active compiler
        local OMP_BIN="${ACTIVE_CXX:-clang++}"
        if echo '#include <omp.h>' | "${OMP_BIN}" -fopenmp -x c++ - -c -o /dev/null &>/dev/null 2>&1; then
            success "  OpenMP : available via ${OMP_BIN} -fopenmp  ✓"
        else
            warn "  OpenMP (omp.h) not found  (install: sudo apt install openmp-extras-dev)"
        fi
    fi

    # ── 8. Threads (pthreads) ─────────────────────────────────────────────────
    info "[8/10] Threads (pthreads) ..."
    local PTHREAD_HEADER=""
    for _h in "/usr/include/pthread.h" "/usr/local/include/pthread.h"; do
        if [[ -f "${_h}" ]]; then PTHREAD_HEADER="${_h}"; break; fi
    done
    if [[ -n "${PTHREAD_HEADER}" ]]; then
        success "  Threads : ${PTHREAD_HEADER}  ✓"
    else
        local THR_BIN="${ACTIVE_CXX:-clang++}"
        if echo '#include <pthread.h>' | "${THR_BIN}" -pthread -x c++ - -c -o /dev/null &>/dev/null 2>&1; then
            success "  Threads : available via ${THR_BIN} -pthread  ✓"
        else
            warn "  Threads : pthread.h not found  (install: sudo apt install build-essential)"
        fi
    fi

    # ── 9. Ubuntu 22.04: libstdc++-12-dev ────────────────────────────────────
    info "[9/10] Ubuntu 22.04 specific: libstdc++-12-dev ..."
    if [[ "${OS_ID}" == "ubuntu" && "${OS_VER}" == "22.04" ]]; then
        if dpkg -l libstdc++-12-dev &>/dev/null 2>&1; then
            success "  libstdc++-12-dev : installed  ✓"
        else
            warn "  libstdc++-12-dev : NOT installed  (required on Ubuntu 22.04)"
            warn "  Install: sudo apt install libstdc++-12-dev"
        fi
    else
        info "  libstdc++-12-dev check : not required for ${OS_NAME} ${OS_VER}"
    fi

    # ── 10. hip-dev package (HIP, debian-based) ───────────────────────────────
    info "[10/10] hip-dev package check ..."
    if [[ "${BACKEND}" == "HIP" ]]; then
        if command -v dpkg &>/dev/null; then
            if dpkg -l hip-dev &>/dev/null 2>&1; then
                local HIP_DEV_VER
                HIP_DEV_VER="$(dpkg -l hip-dev 2>/dev/null | awk '/^ii/{print $3}' | head -1)"
                success "  hip-dev : ${HIP_DEV_VER}  ✓"
            else
                warn "  hip-dev : package NOT installed  (install: sudo apt install hip-dev)"
            fi
        elif command -v rpm &>/dev/null; then
            if rpm -q hip-devel &>/dev/null 2>&1; then
                success "  hip-devel (rpm) : installed  ✓"
            else
                warn "  hip-devel : package NOT installed  (install: sudo dnf install hip-devel)"
            fi
        else
            info "  hip-dev : package manager check skipped (checked header above)"
        fi
    else
        info "  hip-dev check : skipped (backend=${BACKEND})"
    fi

    echo ""
    if ${HAVE_ERROR}; then
        error "One or more REQUIRED prerequisites are missing. Fix the errors above before building."
        exit 1
    else
        success "All required prerequisites satisfied — proceeding with build."
    fi
    echo ""
}

# ─── Print Summary ─────────────────────────────────────────────────────────────
echo ""
info "══════════════════════════════════════════════════"
info "  RPP Build Configuration"
info "══════════════════════════════════════════════════"
info "  Source dir     : ${RPP_SRC}"
info "  Build dir      : ${RPP_BUILD}"
info "  Install prefix : ${INSTALL_PREFIX}"
info "  Build type     : ${BUILD_TYPE}"
info "  Backend        : ${BACKEND}"
info "  Clean build    : ${DO_CLEAN}"
info "  Install        : ${DO_INSTALL}"
info "  Parallel jobs  : ${JOBS}"
info "  Audio support  : ${AUDIO_SUPPORT}"
info "  Legacy support : ${LEGACY_SUPPORT}"
info "══════════════════════════════════════════════════"
echo ""

# Run pre-flight checks
preflight_checks

# ─── Config-only mode: exit after checks ──────────────────────────────────────
if ${DO_CONFIG_ONLY}; then
    info "──────────────────────────────────────────────────"
    info "  --config mode: no build performed. Exiting."
    info "──────────────────────────────────────────────────"
    exit 0
fi

# ─── Clean ────────────────────────────────────────────────────────────────────
if ${DO_CLEAN}; then
    if [[ -d "${RPP_BUILD}" ]]; then
        step "Cleaning build directory: ${RPP_BUILD}"
        rm -rf "${RPP_BUILD}"
        success "Build directory removed."
    else
        warn "Build directory does not exist, nothing to clean."
    fi
fi

# ─── CMake Configure ──────────────────────────────────────────────────────────
step "Configuring RPP with CMake"
info "Backend    = ${BACKEND}"
info "Build type = ${BUILD_TYPE}"
info "Prefix     = ${INSTALL_PREFIX}"

mkdir -p "${RPP_BUILD}"

CMAKE_ARGS=(
    -S "${RPP_SRC}"
    -B "${RPP_BUILD}"
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
    -DBACKEND="${BACKEND}"
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
    -DRPP_AUDIO_SUPPORT="${AUDIO_SUPPORT}"
    -DRPP_LEGACY_SUPPORT="${LEGACY_SUPPORT}"
)

info "Running: cmake ${CMAKE_ARGS[*]}"
echo ""
cmake "${CMAKE_ARGS[@]}"
echo ""
success "CMake configuration complete."

# ─── Build ────────────────────────────────────────────────────────────────────
step "Building RPP  (-j ${JOBS})"
BUILD_START=$(date +%s)
cmake --build "${RPP_BUILD}" --parallel "${JOBS}"
BUILD_END=$(date +%s)
BUILD_ELAPSED=$(( BUILD_END - BUILD_START ))
BUILD_MM=$(( BUILD_ELAPSED / 60 ))
BUILD_SS=$(( BUILD_ELAPSED % 60 ))
echo ""
success "Build complete.  (elapsed: ${BUILD_MM}m ${BUILD_SS}s)"

# ─── Install ──────────────────────────────────────────────────────────────────
if ${DO_INSTALL}; then
    step "Installing RPP to: ${INSTALL_PREFIX}"
    cmake --install "${RPP_BUILD}"
    echo ""
    success "Install complete → ${INSTALL_PREFIX}"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
success "══════════════════════════════════════════════════"
success "  All done!  Build type=${BUILD_TYPE}  Backend=${BACKEND}"
success "  Build time : ${BUILD_MM}m ${BUILD_SS}s"
if ${DO_INSTALL}; then
    success "  Installed to: ${INSTALL_PREFIX}"
fi
success "══════════════════════════════════════════════════"
echo ""
