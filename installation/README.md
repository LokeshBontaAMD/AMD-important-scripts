# installation/

Scripts for downloading, installing, and verifying TheRock nightly builds on AMD GPU systems.

---

## Scripts

### `therock.sh` — Full workflow (install + verify)

Runs `install_therock.sh` followed by `verify_therock.sh` in one step.

```bash
bash therock.sh

# Skip GPU auto-detection by providing the target explicitly:
GFX_TARGET=gfx90a bash therock.sh
```

Use this when you want to download, extract, and immediately verify a fresh TheRock build.

---

### `install_therock.sh` — Download and extract

Detects the AMD GPU architecture, queries the TheRock S3 nightly index for the latest matching tarball, downloads it (reusing a cached copy if one exists), and extracts it to a timestamped directory.

```bash
bash install_therock.sh

# Override GPU auto-detection:
GFX_TARGET=gfx90a bash install_therock.sh

# Custom scratch root (default: /scratch/users/lbonta):
SCRATCH_ROOT=/path/to/scratch bash install_therock.sh
```

**GPU detection order:**
1. `rocm-smi --showproductname` (preferred — works for datacenter cards)
2. `lspci` product-name / device-ID matching (fallback)

**Supported targets:**

| Target | GPUs |
|--------|------|
| `gfx94X-dcgpu` | MI300X, MI300A, MI325 |
| `gfx90a` | MI210, MI250 |
| `gfx908` | MI100 |
| `gfx906` | MI50, MI60 |
| `gfx900` | Vega10 / Instinct MI25 |
| `gfx110X-all` | RX 7000 series (Navi 3x) |
| `gfx103X-all` | RX 6000 series (Navi 2x) |
| `gfx803` | RX 580/570/560 (Polaris) |

**Output layout:**

```
therock-tarball-<gpu>-<timestamp>/
└── install/
    ├── bin/
    │   ├── rocminfo
    │   ├── hipcc
    │   └── test_hip_api
    ├── lib/
    └── include/
```

On success, writes install state to `$SCRATCH_ROOT/.therock_last_install` so `verify_therock.sh` can pick it up automatically.

---

### `verify_therock.sh` — Verify an installation

Runs `rocminfo` and `test_hip_api` from an installed TheRock tree and prints a pass/fail summary.

```bash
# Reads the last install path from the state file written by install_therock.sh:
bash verify_therock.sh

# Explicit install directory:
bash verify_therock.sh /path/to/therock-tarball-gfx94X-dcgpu-YYYYMMDD-HHMMSS/install

# Via environment variable:
INSTALL_DIR=/path/to/install bash verify_therock.sh
```

The script resolves the install directory in this priority order:
1. Positional argument `$1`
2. `$INSTALL_DIR` environment variable
3. State file at `$SCRATCH_ROOT/.therock_last_install`

---

## Requirements

- Linux system with an AMD GPU
- `curl`, `wget`, `python3`, `tar` — for download and extraction
- `lspci` or `rocm-smi` — for GPU auto-detection

## License

MIT
