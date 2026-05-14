#!/usr/bin/env bash
# =============================================================================
#  build_rocal.sh  --  rocAL build helper
#
#  Usage:
#    build_rocal              release incremental build  (default)
#    build_rocal -r           release incremental build
#    build_rocal -r -i        release incremental build + install
#    build_rocal -c -r        clean rocAL build + rebuild
#    build_rocal -c -r -i     clean rocAL build + rebuild + install
#    build_rocal -d           debug incremental build
#    build_rocal -d -i        debug incremental build + install
#    build_rocal -c -d        clean debug build
#    build_rocal --cleanall -r  wipe all AMD-stack repos, clone fresh,
#                               build all deps + rocAL  (new machine setup)
#
#  Backend (optional, default = HIP):
#    -hip   HIP backend  (default)
#    -cpu   CPU/HOST backend
#
#  Extra options:
#    -j <N>           parallel jobs  (default = nproc)
#    -prefix <path>   custom install prefix  (default = ROCM_PATH)
#    -nopypackage     disable Python package build
#    -h / --help      show this help
#
#  Standalone modes:
#    --config         print config + pre-flight checks, then exit
#
#  Notes:
#    -r and -d cannot be used together.
#    --cleanall wipes AMD-stack repos and requires sudo for system packages.
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

info()    { echo -e "${BLU}[build_rocal]${RST} $*"; }
success() { echo -e "${GRN}[build_rocal]${RST} $*"; }
warn()    { echo -e "${YLW}[build_rocal]${RST} $*"; }
error()   { echo -e "${RED}[build_rocal] ERROR:${RST} $*" >&2; }
step()    { echo -e "\n${MAG}══════════════════════════════════════════════════${RST}"; \
            echo -e "${CYN}  ▶  $*${RST}"; \
            echo -e "${MAG}══════════════════════════════════════════════════${RST}"; }

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
AMD_STACK_DIR="$(readlink -f "${SCRIPT_DIR}/../../AMD-stack")"

# ─── Source ROCm environment ──────────────────────────────────────────────────
SET_ROCM_ENV="${SCRIPT_DIR}/../set_rocm_env/set_rocm_env.sh"
if [[ -f "${SET_ROCM_ENV}" ]]; then
    _saved_args=("$@")
    set --
    # shellcheck source=/dev/null
    if ! source "${SET_ROCM_ENV}"; then
        set -- "${_saved_args[@]}"
        error "ROCm environment setup failed — the therock install path does not exist."
        error "Edit set_rocm_env.sh or run: source ${SET_ROCM_ENV} /path/to/therock/install"
        exit 1
    fi
    set -- "${_saved_args[@]}"
    unset _saved_args
else
    warn "set_rocm_env.sh not found at ${SET_ROCM_ENV}"
    warn "Using existing ROCM_PATH or default /opt/rocm"
    ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
fi

# ─── Repo locations in AMD-stack ──────────────────────────────────────────────
LIBJPEG_DIR="${AMD_STACK_DIR}/libjpeg-turbo"
PROTOBUF_DIR="${AMD_STACK_DIR}/protobuf"
RAPIDJSON_DIR="${AMD_STACK_DIR}/rapidjson"
PYBIND11_DIR="${AMD_STACK_DIR}/pybind11"
RPP_DIR="${AMD_STACK_DIR}/rpp"
MIVISIONX_DIR="${AMD_STACK_DIR}/MIVisionX"
ROCJPEG_DIR="${AMD_STACK_DIR}/rocjpeg"
ROCAL_SRC="${AMD_STACK_DIR}/rocAL"
ROCAL_BUILD="${ROCAL_SRC}/build"

# ─── Dep repo URLs ────────────────────────────────────────────────────────────
LIBJPEG_URL="https://github.com/libjpeg-turbo/libjpeg-turbo.git"
PROTOBUF_URL="https://github.com/protocolbuffers/protobuf.git"
RAPIDJSON_URL="https://github.com/Tencent/rapidjson.git"
PYBIND11_URL="https://github.com/pybind/pybind11.git"
RPP_URL="https://github.com/ROCm/rpp.git"
MIVISIONX_URL="https://github.com/ROCm/MIVisionX.git"
ROCJPEG_URL="https://github.com/ROCm/rocJPEG.git"
ROCAL_URL="https://github.com/ROCm/rocAL.git"

# ─── Defaults ─────────────────────────────────────────────────────────────────
BUILD_TYPE=""
FLAG_R=false
FLAG_D=false
DO_CLEAN=false
DO_INSTALL=false
DO_CLEANALL=false
DO_CONFIG_ONLY=false
BACKEND="HIP"
JOBS="$(nproc 2>/dev/null || echo 8)"
INSTALL_PREFIX="${ROCM_PATH}"
BUILD_PYPACKAGE="ON"

# ─── Help ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

  ${BLU}build_rocal${RST} - rocAL build helper script

  ${CYN}Build type (default: -r):${RST}
    -r              Release build  (default when no args given)
    -d              Debug build
    (-r and -d cannot be used together)

  ${CYN}Build mode:${RST}
    -c              Clean rocAL build directory first
    -i              Install after building
    --cleanall      Wipe all AMD-stack repos, clone fresh, build all deps + rocAL
                    (use on new machines; requires sudo for system packages)

  ${CYN}Backend (optional, default=HIP):${RST}
    -hip            HIP backend  (default)
    -cpu            CPU/HOST backend

  ${CYN}Extra options:${RST}
    -j <N>           Parallel jobs  (default: $(nproc))
    -prefix <path>   Custom install prefix  (default: ${ROCM_PATH})
    -nopypackage     Disable Python package build
    -h / --help      Show this help

  ${CYN}Standalone:${RST}
    --config         Print build config + pre-flight checks, then exit

  ${CYN}Examples:${RST}
    $0                     # release incremental build  (default)
    $0 -r                  # release incremental build
    $0 -r -i               # release incremental build + install
    $0 -c -r               # clean rocAL build + rebuild
    $0 -c -r -i            # clean rocAL build + rebuild + install
    $0 -d                  # debug incremental build
    $0 --cleanall -r       # full reset: clone all, build deps, build rocAL
    $0 -r -j 16 -prefix /opt/rocm

EOF
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    BUILD_TYPE="Release"
    FLAG_R=true
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r)          BUILD_TYPE="Release"; FLAG_R=true ;;
        -d)          BUILD_TYPE="Debug";   FLAG_D=true ;;
        -c)          DO_CLEAN=true ;;
        -i)          DO_INSTALL=true ;;
        --cleanall)  DO_CLEANALL=true ;;
        -hip)        BACKEND="HIP" ;;
        -cpu)        BACKEND="CPU" ;;
        -nopypackage) BUILD_PYPACKAGE="OFF" ;;
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
    error "No build type specified. Use -r (Release) or -d (Debug)."
    usage
    exit 1
fi

if ${FLAG_R} && ${FLAG_D}; then
    error "-r (Release) and -d (Debug) cannot be used together."
    exit 1
fi

GPU_SUPPORT="ON"
[[ "${BACKEND}" == "CPU" ]] && GPU_SUPPORT="OFF"

# ─── Helpers ──────────────────────────────────────────────────────────────────
clone_if_missing() {
    local dir="$1" url="$2" branch="${3:-}"
    if [[ -d "${dir}" ]]; then
        info "  Present : ${dir}"
        return 0
    fi
    local branch_args=()
    [[ -n "${branch}" ]] && branch_args=(-b "${branch}")
    info "  Cloning ${url} → ${dir}"
    git clone "${branch_args[@]}" "${url}" "${dir}"
}

is_installed() {
    local check="$1"
    if [[ "${check}" == /* ]]; then
        [[ -e "${check}" ]]
    else
        command -v "${check}" &>/dev/null
    fi
}

# ─── System packages ──────────────────────────────────────────────────────────
SYS_PKGS=(
    build-essential gcc g++ make cmake pkg-config git wget unzip ca-certificates
    autoconf automake libtool nasm yasm clang
    python3-dev python3-pip
    ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
    libgtk2.0-dev libtbbmalloc2 libtbb-dev libjpeg-dev libpng-dev libtiff-dev libdc1394-dev
    libbz2-dev libssl-dev libgflags-dev libgoogle-glog-dev liblmdb-dev libjsoncpp-dev
    libdlpack-dev libsndfile-dev
    libva-dev libva-drm2 libdrm-dev vainfo
    mesa-va-drivers
    half rocblas-dev miopen-hip-dev migraphx-dev
    hipblas hipsparse rocrand hipfft rocfft rocthrust-dev hipcub-dev
)

PY_PKGS=(matplotlib Cython opencv-python "pytest==7.3.1")

check_system_deps() {
    step "Checking system packages"
    local missing=()
    for pkg in "${SYS_PKGS[@]}"; do
        dpkg -l "${pkg}" &>/dev/null 2>&1 || missing+=("${pkg}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing packages: ${missing[*]}"
        warn "Install with: sudo apt-get install -y ${missing[*]}"
    else
        success "All system packages present."
    fi
}

install_system_deps() {
    step "Installing system packages (requires sudo)"
    sudo apt-get update
    sudo apt-get install -y "${SYS_PKGS[@]}"
    pip3 install --upgrade pip
    pip3 install "${PY_PKGS[@]}"
    success "System packages installed."
}

# ─── Clone / wipe all repos ───────────────────────────────────────────────────
clone_all_repos() {
    step "Cloning repos to ${AMD_STACK_DIR}"
    mkdir -p "${AMD_STACK_DIR}"
    clone_if_missing "${LIBJPEG_DIR}"   "${LIBJPEG_URL}"   "3.0.2"
    clone_if_missing "${PROTOBUF_DIR}"  "${PROTOBUF_URL}"  "v3.21.9"
    clone_if_missing "${RAPIDJSON_DIR}" "${RAPIDJSON_URL}"
    clone_if_missing "${PYBIND11_DIR}"  "${PYBIND11_URL}"  "v2.11.1"
    clone_if_missing "${RPP_DIR}"       "${RPP_URL}"       "develop"
    clone_if_missing "${MIVISIONX_DIR}" "${MIVISIONX_URL}"
    clone_if_missing "${ROCJPEG_DIR}"   "${ROCJPEG_URL}"
    clone_if_missing "${ROCAL_SRC}"     "${ROCAL_URL}"     "develop"
    success "All repos present."
}

wipe_all_repos() {
    step "Wiping all AMD-stack repos from ${AMD_STACK_DIR}"
    for dir in \
        "${LIBJPEG_DIR}" "${PROTOBUF_DIR}" "${RAPIDJSON_DIR}" "${PYBIND11_DIR}" \
        "${RPP_DIR}" "${MIVISIONX_DIR}" "${ROCJPEG_DIR}" "${ROCAL_SRC}"; do
        if [[ -d "${dir}" ]]; then
            info "  Removing ${dir}"
            rm -rf "${dir}"
        fi
    done
    success "Repos wiped."
}

# ─── Build helper deps ────────────────────────────────────────────────────────
build_libjpeg_turbo() {
    step "Building libjpeg-turbo"
    if is_installed "/usr/include/turbojpeg.h" && ! ${DO_CLEANALL}; then
        success "libjpeg-turbo already installed — skipping."
        return
    fi
    local bdir="${LIBJPEG_DIR}/build"
    rm -rf "${bdir}" && mkdir -p "${bdir}"
    cmake -S "${LIBJPEG_DIR}" -B "${bdir}" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=RELEASE \
        -DENABLE_STATIC=FALSE \
        -DCMAKE_INSTALL_DEFAULT_LIBDIR=lib \
        -DWITH_JPEG8=TRUE
    cmake --build "${bdir}" --parallel "${JOBS}"
    sudo cmake --install "${bdir}"
    sudo ldconfig
    success "libjpeg-turbo installed."
}

build_protobuf() {
    step "Building protobuf"
    if is_installed "protoc" && ! ${DO_CLEANALL}; then
        success "protobuf already installed ($(protoc --version)) — skipping."
        return
    fi
    cd "${PROTOBUF_DIR}"
    git submodule update --init --recursive
    ./autogen.sh
    ./configure
    make -j"${JOBS}"
    sudo make install
    sudo ldconfig
    cd - >/dev/null
    success "protobuf installed."
}

build_rapidjson() {
    step "Building rapidjson"
    if is_installed "/usr/local/include/rapidjson/rapidjson.h" && ! ${DO_CLEANALL}; then
        success "rapidjson already installed — skipping."
        return
    fi
    local bdir="${RAPIDJSON_DIR}/build"
    rm -rf "${bdir}" && mkdir -p "${bdir}"
    cmake -S "${RAPIDJSON_DIR}" -B "${bdir}" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    cmake --build "${bdir}" --parallel "${JOBS}"
    sudo cmake --install "${bdir}"
    success "rapidjson installed."
}

build_pybind11() {
    step "Building pybind11"
    if is_installed "/usr/local/include/pybind11/pybind11.h" && ! ${DO_CLEANALL}; then
        success "pybind11 already installed — skipping."
        return
    fi
    local bdir="${PYBIND11_DIR}/build"
    rm -rf "${bdir}" && mkdir -p "${bdir}"
    cmake -S "${PYBIND11_DIR}" -B "${bdir}" \
        -DDOWNLOAD_CATCH=ON \
        -DDOWNLOAD_EIGEN=ON
    cmake --build "${bdir}" --parallel "${JOBS}"
    sudo cmake --install "${bdir}"
    success "pybind11 installed."
}

build_rpp() {
    step "Building RPP"
    if is_installed "${INSTALL_PREFIX}/lib/librpp.so" && ! ${DO_CLEANALL}; then
        success "RPP already installed — skipping."
        return
    fi
    local bdir="${RPP_DIR}/build"
    rm -rf "${bdir}" && mkdir -p "${bdir}"
    cmake -S "${RPP_DIR}" -B "${bdir}" \
        -DBACKEND="${BACKEND}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
    cmake --build "${bdir}" --parallel "${JOBS}"
    sudo cmake --install "${bdir}"
    success "RPP installed."
}

build_mivisionx() {
    step "Building MIVisionX"
    if is_installed "${INSTALL_PREFIX}/lib/libopenvx.so" && ! ${DO_CLEANALL}; then
        success "MIVisionX already installed — skipping."
        return
    fi
    local bdir="${MIVISIONX_DIR}/build"
    rm -rf "${bdir}" && mkdir -p "${bdir}"
    cmake -S "${MIVISIONX_DIR}" -B "${bdir}" \
        -DBACKEND="${BACKEND}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
    cmake --build "${bdir}" --parallel "${JOBS}"
    sudo cmake --install "${bdir}"
    sudo ldconfig
    success "MIVisionX installed."
}

build_rocjpeg() {
    step "Building rocJPEG"
    if is_installed "${INSTALL_PREFIX}/lib/librocjpeg.so" && ! ${DO_CLEANALL}; then
        success "rocJPEG already installed — skipping."
        return
    fi
    local bdir="${ROCJPEG_DIR}/build"
    rm -rf "${bdir}" && mkdir -p "${bdir}"
    cmake -S "${ROCJPEG_DIR}" -B "${bdir}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
    cmake --build "${bdir}" --parallel "${JOBS}"
    sudo cmake --install "${bdir}"
    sudo ldconfig
    success "rocJPEG installed."
}

# ─── Pre-flight Checks ────────────────────────────────────────────────────────
preflight_checks() {
    step "Pre-flight checks"

    info "[1] rocAL source"
    if [[ -d "${ROCAL_SRC}" && -f "${ROCAL_SRC}/CMakeLists.txt" ]]; then
        success "  rocAL source : ${ROCAL_SRC}  ✓"
    else
        error "  rocAL source not found: ${ROCAL_SRC}"
        error "  Run: build_rocal --cleanall -r   to clone and build from scratch."
        exit 1
    fi

    info "[2] Backend"
    case "${BACKEND}" in
        HIP) success "  Backend : HIP  ✓" ;;
        CPU) info    "  Backend : CPU/HOST" ;;
        *)   warn    "  Backend : ${BACKEND}  (unknown)" ;;
    esac

    info "[3] ROCm"
    if [[ -d "${ROCM_PATH}" ]]; then
        local ROCM_VER=""
        [[ -f "${ROCM_PATH}/.info/version" ]] && ROCM_VER="$(cat "${ROCM_PATH}/.info/version")"
        success "  ROCm : ${ROCM_PATH}  ${ROCM_VER}  ✓"
    else
        error "  ROCm not found at ${ROCM_PATH}"
        exit 1
    fi

    info "[4] Helper dep headers"
    for _check in \
        "/usr/include/turbojpeg.h:libjpeg-turbo" \
        "protoc:protobuf" \
        "/usr/local/include/rapidjson/rapidjson.h:rapidjson" \
        "/usr/local/include/pybind11/pybind11.h:pybind11"; do
        local _key="${_check%%:*}" _name="${_check##*:}"
        if is_installed "${_key}"; then
            success "  ${_name} : ✓"
        else
            warn "  ${_name} : NOT found — run --cleanall to build, or install manually"
        fi
    done

    info "[5] ROCm dep libraries"
    for _lib in \
        "${INSTALL_PREFIX}/lib/librpp.so:RPP" \
        "${INSTALL_PREFIX}/lib/libopenvx.so:MIVisionX" \
        "${INSTALL_PREFIX}/lib/librocjpeg.so:rocJPEG"; do
        local _path="${_lib%%:*}" _name="${_lib##*:}"
        if [[ -f "${_path}" ]]; then
            success "  ${_name} : ✓"
        else
            warn "  ${_name} : NOT found at ${_path} — run --cleanall to build"
        fi
    done

    echo ""
}

# ─── Print Summary ─────────────────────────────────────────────────────────────
echo ""
info "══════════════════════════════════════════════════"
info "  rocAL Build Configuration"
info "══════════════════════════════════════════════════"
info "  AMD-stack dir  : ${AMD_STACK_DIR}"
info "  rocAL source   : ${ROCAL_SRC}"
info "  Build dir      : ${ROCAL_BUILD}"
info "  Install prefix : ${INSTALL_PREFIX}"
info "  Build type     : ${BUILD_TYPE:-<config-only>}"
info "  Backend        : ${BACKEND}"
info "  Clean build    : ${DO_CLEAN}"
info "  Cleanall       : ${DO_CLEANALL}"
info "  Install        : ${DO_INSTALL}"
info "  Parallel jobs  : ${JOBS}"
info "  Python package : ${BUILD_PYPACKAGE}"
info "══════════════════════════════════════════════════"
echo ""

# ─── Config-only mode: check state and exit ───────────────────────────────────
if ${DO_CONFIG_ONLY}; then
    check_system_deps
    preflight_checks
    info "──────────────────────────────────────────────────"
    info "  --config mode: no build performed. Exiting."
    info "──────────────────────────────────────────────────"
    exit 0
fi

# ─── --cleanall: wipe repos, clone fresh, build all deps ──────────────────────
if ${DO_CLEANALL}; then
    warn "══════════════════════════════════════════════════"
    warn "  --cleanall: wipes all AMD-stack repos and"
    warn "  rebuilds from scratch. Requires sudo."
    warn "══════════════════════════════════════════════════"
    read -r -p "  Continue? [y/N] " _CONFIRM
    [[ "${_CONFIRM,,}" == "y" ]] || { info "Aborted."; exit 0; }

    wipe_all_repos
    clone_all_repos
    install_system_deps
    build_libjpeg_turbo
    build_protobuf
    build_rapidjson
    build_pybind11
    build_rpp
    build_mivisionx
    build_rocjpeg
fi

# ─── Ensure rocAL is cloned (auto-clone on first run) ─────────────────────────
if [[ ! -d "${ROCAL_SRC}" ]]; then
    step "Cloning rocAL (develop)"
    mkdir -p "${AMD_STACK_DIR}"
    git clone -b develop "${ROCAL_URL}" "${ROCAL_SRC}"
fi

# ─── Validate rocAL source ────────────────────────────────────────────────────
if [[ ! -f "${ROCAL_SRC}/CMakeLists.txt" ]]; then
    error "CMakeLists.txt not found in ${ROCAL_SRC}"
    error "Is this the correct rocAL source tree?"
    exit 1
fi

# ─── Pre-flight (warn only — build may still succeed) ─────────────────────────
preflight_checks

# ─── Clean rocAL build dir ────────────────────────────────────────────────────
if ${DO_CLEAN}; then
    if [[ -d "${ROCAL_BUILD}" ]]; then
        step "Cleaning rocAL build directory: ${ROCAL_BUILD}"
        rm -rf "${ROCAL_BUILD}"
        success "Build directory removed."
    else
        warn "Build directory does not exist, nothing to clean."
    fi
fi

# ─── CMake Configure ──────────────────────────────────────────────────────────
step "Configuring rocAL with CMake"
info "Backend    = ${BACKEND}"
info "Build type = ${BUILD_TYPE}"
info "Prefix     = ${INSTALL_PREFIX}"

mkdir -p "${ROCAL_BUILD}"

CMAKE_ARGS=(
    -S "${ROCAL_SRC}"
    -B "${ROCAL_BUILD}"
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
    -DBACKEND="${BACKEND}"
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
    -DBUILD_PYPACKAGE="${BUILD_PYPACKAGE}"
    -DGPU_SUPPORT="${GPU_SUPPORT}"
)

info "Running: cmake ${CMAKE_ARGS[*]}"
echo ""
cmake "${CMAKE_ARGS[@]}"
echo ""
success "CMake configuration complete."

# ─── Build ────────────────────────────────────────────────────────────────────
step "Building rocAL  (-j ${JOBS})"
BUILD_START=$(date +%s)
cmake --build "${ROCAL_BUILD}" --parallel "${JOBS}"
BUILD_END=$(date +%s)
BUILD_ELAPSED=$(( BUILD_END - BUILD_START ))
BUILD_MM=$(( BUILD_ELAPSED / 60 ))
BUILD_SS=$(( BUILD_ELAPSED % 60 ))
echo ""
success "Build complete.  (elapsed: ${BUILD_MM}m ${BUILD_SS}s)"

# ─── Install ──────────────────────────────────────────────────────────────────
if ${DO_INSTALL}; then
    step "Installing rocAL to: ${INSTALL_PREFIX}"
    sudo cmake --install "${ROCAL_BUILD}"
    sudo ldconfig
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
