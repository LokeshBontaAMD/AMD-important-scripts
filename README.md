# AMD Important Scripts

Personal AMD developer toolkit — workspace bootstrap, TheRock nightly management, ROCm environment setup, and RPP build helpers.

## Quick Start (fresh machine)

```bash
# 1. Clone this repo anywhere
git clone https://github.com/LokeshBontaAMD/AMD-important-scripts.git

# 2. Run the workspace setup (sets up dirs, symlinks, and patches ~/.bashrc)
bash AMD-important-scripts/setup_workspace.sh

# 3. Reload your shell
source ~/.bashrc

# 4. All commands are now on PATH — no ./ needed
install_therock          # download + extract latest TheRock nightly
verify_therock           # verify the install
build_rpp -r             # build RPP (release)
build_rpp -c -r -i       # clean release build + install
```

## Workspace Layout

After running `setup_workspace.sh`, your workspace (`/scratch/users/$USER`) looks like:

```
/scratch/users/$USER/
├── AMD-important-scripts/   ← this repo (cloned by setup_workspace.sh)
├── AMD-stack/               ← RPP and other AMD project sources
├── therock-tarballs/        ← TheRock nightly installs (managed by install_therock)
└── bin/                     ← command symlinks (auto-added to PATH)
    ├── build_rpp
    ├── install_therock
    ├── verify_therock
    └── therock
```

## Scripts

| Script | Description |
|---|---|
| [`setup_workspace.sh`](setup_workspace.sh) | Bootstrap the full workspace (clone, dirs, symlinks, bashrc) |
| [`my_bashrc.sh`](my_bashrc.sh) | Shell additions: `system_info`, env vars, PATH setup |
| [`installation/install_therock.sh`](installation/install_therock.sh) | Download + extract latest TheRock nightly tarball |
| [`installation/verify_therock.sh`](installation/verify_therock.sh) | Verify a TheRock install (rocminfo, test_hip_api) |
| [`installation/therock.sh`](installation/therock.sh) | Combined: install + verify |
| [`installation/set_env_therock.sh`](installation/set_env_therock.sh) | Source to set ROCm env vars for a TheRock install |
| [`set_rocm_env/set_rocm_env.sh`](set_rocm_env/set_rocm_env.sh) | Full ROCm/HIP environment setup with all search paths |
| [`rpp_related/build_rpp.sh`](rpp_related/build_rpp.sh) | Build RPP from source (CMake, HIP/CPU/OCL backends) |

## Directories

- **[`installation/`](installation/)** — TheRock download, extraction, verification
- **[`set_rocm_env/`](set_rocm_env/)** — ROCm environment sourcing
- **[`rpp_related/`](rpp_related/)** — RPP build helpers
