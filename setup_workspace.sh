#!/usr/bin/env bash
# =============================================================================
# setup_workspace.sh — AMD Developer Workspace Bootstrap
#
# Clones AMD-important-scripts, creates the workspace directory structure,
# wires command symlinks into bin/, and patches ~/.bashrc.
#
# Usage:
#   bash setup_workspace.sh                      # workspace = /scratch/users/$USER
#   bash setup_workspace.sh /my/custom/path      # custom workspace root
#
# What it creates:
#   $WORKSPACE/
#   ├── AMD-important-scripts/   ← git clone of this repo
#   ├── AMD-stack/               ← RPP and other AMD project sources
#   ├── therock-tarballs/        ← TheRock nightly installs
#   └── bin/                     ← symlinks (build_rpp, install_therock, …)
#
# ~/.bashrc additions:
#   export SCRATCH_ROOT="$WORKSPACE"
#   export PATH="$WORKSPACE/bin:$PATH"
#   source  "$WORKSPACE/AMD-important-scripts/my_bashrc.sh"
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

info()    { echo -e "${BLU}[setup]${RST} $*"; }
success() { echo -e "${GRN}[setup]${RST} $*"; }
warn()    { echo -e "${YLW}[setup]${RST} $*"; }
error()   { echo -e "${RED}[setup] ERROR:${RST} $*" >&2; }
step()    { echo -e "\n${MAG}══════════════════════════════════════════════════${RST}"; \
            echo -e "${CYN}  ▶  $*${RST}"; \
            echo -e "${MAG}══════════════════════════════════════════════════${RST}"; }

# ─── Config ───────────────────────────────────────────────────────────────────
WORKSPACE="${1:-/scratch/users/${USER}}"
SCRIPTS_REPO="https://github.com/LokeshBontaAMD/AMD-important-scripts"
SCRIPTS_DIR="${WORKSPACE}/AMD-important-scripts"
AMD_STACK="${WORKSPACE}/AMD-stack"
BIN_DIR="${WORKSPACE}/bin"
THEROCK_TARBALLS="${WORKSPACE}/therock-tarballs"

echo ""
info "══════════════════════════════════════════════════"
info "  AMD Developer Workspace Setup"
info "══════════════════════════════════════════════════"
info "  Workspace : ${WORKSPACE}"
info "  Scripts   : ${SCRIPTS_DIR}"
info "  AMD-stack : ${AMD_STACK}"
info "  bin/      : ${BIN_DIR}"
info "══════════════════════════════════════════════════"
echo ""

# ─── Step 1: Clone AMD-important-scripts ─────────────────────────────────────
step "Cloning AMD-important-scripts"

if [[ -d "${SCRIPTS_DIR}/.git" ]]; then
    info "Already cloned — pulling latest..."
    git -C "${SCRIPTS_DIR}" pull --ff-only 2>&1 | sed 's/^/  /'
    success "Up to date: ${SCRIPTS_DIR}"
else
    git clone "${SCRIPTS_REPO}" "${SCRIPTS_DIR}"
    success "Cloned to: ${SCRIPTS_DIR}"
fi

# ─── Step 2: Create workspace directories ────────────────────────────────────
step "Creating workspace directories"

for dir in "${AMD_STACK}" "${BIN_DIR}" "${THEROCK_TARBALLS}"; do
    mkdir -p "${dir}"
    success "  ${dir}"
done

# ─── Step 3: Wire command symlinks into bin/ ──────────────────────────────────
step "Creating command symlinks in ${BIN_DIR}"

link_script() {
    local cmd_name="$1"
    local rel_path="$2"
    local target="${SCRIPTS_DIR}/${rel_path}"
    local link="${BIN_DIR}/${cmd_name}"

    if [[ ! -f "${target}" ]]; then
        warn "  SKIP ${cmd_name} — script not found: ${target}"
        return
    fi

    chmod +x "${target}"
    ln -sf "${target}" "${link}"
    success "  ${cmd_name}  →  ${target}"
}

link_script "build_rpp"       "rpp_related/build_rpp.sh"
link_script "install_therock" "installation/install_therock.sh"
link_script "verify_therock"  "installation/verify_therock.sh"
link_script "therock"         "installation/therock.sh"

# ─── Step 4: Patch ~/.bashrc ──────────────────────────────────────────────────
step "Patching ~/.bashrc"

add_to_bashrc() {
    local line="$1"
    local label="$2"
    if grep -qF "${line}" "${HOME}/.bashrc" 2>/dev/null; then
        info "  Already present: ${label}"
    else
        printf '\n%s\n' "${line}" >> "${HOME}/.bashrc"
        success "  Added: ${label}"
    fi
}

add_to_bashrc "export SCRATCH_ROOT=\"${WORKSPACE}\""              "SCRATCH_ROOT"
add_to_bashrc "export PATH=\"${BIN_DIR}:\$PATH\""                 "bin/ in PATH"
add_to_bashrc "source \"${SCRIPTS_DIR}/my_bashrc.sh\""            "my_bashrc.sh"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
info "══════════════════════════════════════════════════"
success "  Workspace ready!"
info "──────────────────────────────────────────────────"
info "  Workspace       : ${WORKSPACE}"
info "  AMD-stack       : ${AMD_STACK}"
info "  TheRock tarballs: ${THEROCK_TARBALLS}"
info "  Scripts         : ${SCRIPTS_DIR}"
info "  Commands in bin : build_rpp  install_therock  verify_therock  therock"
info "──────────────────────────────────────────────────"
info "  Reload your shell to apply PATH and env changes:"
info ""
info "    source ~/.bashrc"
info ""
info "  Then run any command directly, e.g.:"
info "    build_rpp -r -i"
info "    install_therock"
info "══════════════════════════════════════════════════"
echo ""
