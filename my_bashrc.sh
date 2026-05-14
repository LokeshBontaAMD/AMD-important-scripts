#!/usr/bin/env bash
# my_bashrc.sh — Personal shell additions for AMD developer workspace
# Source this from ~/.bashrc:
#   source /scratch/users/$USER/AMD-important-scripts/my_bashrc.sh

# ──────────────────────────────────────────────────────────────────────────────
# system_info: display a summary of system hardware and storage
# ──────────────────────────────────────────────────────────────────────────────
system_info() {
    echo "=============================="
    echo " SYSTEM INFO: $(hostname)"
    echo "=============================="

    echo ""
    echo "--- CPU ---"
    lscpu | grep -E "Model name|Socket\(s\)|Core\(s\) per socket|Thread\(s\) per core|^CPU\(s\):|CPU max MHz"

    echo ""
    echo "--- RAM ---"
    free -h | grep -E "Mem|Swap"

    echo ""
    echo "--- GPU ---"
    lspci | grep -i -E "VGA|3D|Display|Radeon|NVIDIA|Instinct" | grep -v "Host bridge" | grep -v "ASPEED" || echo "No discrete GPU detected"
    if command -v rocm-smi &>/dev/null; then
        echo ""
        rocm-smi --showproductname 2>/dev/null || true
    fi

    echo ""
    echo "--- STORAGE ---"
    df -h /home /scratch 2>/dev/null | column -t

    echo ""
    echo "=============================="
}

# ──────────────────────────────────────────────────────────────────────────────
# Scratch / workspace directory
# SCRATCH_ROOT is set by setup_workspace.sh; fall back to /scratch/users/$USER
# ──────────────────────────────────────────────────────────────────────────────
export SCRATCH_ROOT="${SCRATCH_ROOT:-/scratch/users/${USER}}"
export SCRATCH_DIR="${SCRATCH_ROOT}"

# ──────────────────────────────────────────────────────────────────────────────
# AMD LLM Gateway
# ──────────────────────────────────────────────────────────────────────────────
export AMD_LLM_GATEWAY_KEY=3eba663f68be4b6b8f458f34789142f6

# ──────────────────────────────────────────────────────────────────────────────
# Claude Code / Anthropic API (routed through AMD LLM Gateway)
# ──────────────────────────────────────────────────────────────────────────────
export ANTHROPIC_API_KEY="dummy"
export ANTHROPIC_BASE_URL="https://llm-api.amd.com/Anthropic"
export ANTHROPIC_CUSTOM_HEADERS="Ocp-Apim-Subscription-Key: ${AMD_LLM_GATEWAY_KEY}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# ──────────────────────────────────────────────────────────────────────────────
# PATH additions
# ──────────────────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"
