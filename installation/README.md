# installation/

TheRock nightly tarball management — download, extract, verify.

## Commands (after running `setup_workspace.sh`)

```bash
install_therock          # detect GPU, download latest nightly, extract
verify_therock           # verify the last install
therock                  # install + verify in one shot

# Source ROCm env for the last install
source ~/AMD-important-scripts/installation/set_env_therock.sh
```

## Scripts

| Script | Purpose |
|---|---|
| `install_therock.sh` | Auto-detect GPU, fetch latest tarball from S3, extract to `$SCRATCH_ROOT/therock-tarballs/` |
| `verify_therock.sh` | Run `rocminfo` and `test_hip_api` against the last install |
| `therock.sh` | Runs install then verify |
| `set_env_therock.sh` | Source to export `ROCM_PATH`, `HIP_*`, `PATH`, `LD_LIBRARY_PATH` |

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SCRATCH_ROOT` | `/scratch/users/$USER` | Workspace root; set by `setup_workspace.sh` |
| `GFX_TARGET` | auto-detected | Override GPU target (e.g. `gfx90a`, `gfx94X-dcgpu`) |

## State File

`install_therock.sh` writes `$SCRATCH_ROOT/.therock_last_install` so `verify_therock.sh` and `set_rocm_env.sh` can find the install directory automatically.
