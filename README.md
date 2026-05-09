# AMD Important Scripts

A collection of useful scripts for AMD GPU development and setup.

## Scripts

### install_therock.sh

Auto-installs the latest TheRock nightly tarball for your AMD GPU.

**Features:**
- Auto-detects GPU architecture (MI300X, MI300A, MI325, MI210/250, MI100, consumer Navi cards, etc.)
- Downloads the matching latest nightly tarball from S3
- Extracts to a timestamped directory for easy version management
- Verifies installation by running `rocminfo` and `test_hip_api`
- Reuses existing tarballs to avoid re-downloading

**Usage:**

```bash
bash install_therock.sh
```

**Custom scratch root:**

```bash
SCRATCH_ROOT=/path/to/scratch bash install_therock.sh
```

**Manual GPU target override:**

```bash
GFX_TARGET=gfx90a bash install_therock.sh
```

**Supported GPU Targets:**
| Target | GPUs |
|--------|------|
| `gfx94X-dcgpu` | MI300X, MI300A, MI325 |
| `gfx90a` | MI210, MI250 |
| `gfx908` | MI100 |
| `gfx906` | MI50, MI60 |
| `gfx110X-all` | RX 7000 series (Navi 3x) |
| `gfx103X-all` | RX 6000 series (Navi 2x) |

**Output:**

The script creates a directory named `therock-tarball-<gpu>-<timestamp>/` containing the extracted ROCm installation. Example:

```
therock-tarball-gfx94X-dcgpu-20260509-143022/
└── install/
    └── bin/
        ├── rocminfo
        ├── hipcc
        └── test_hip_api
```

## Requirements

- Linux system with AMD GPU
- `curl`, `wget`, `python3`, `tar`
- `lspci` for GPU detection

## License

MIT
