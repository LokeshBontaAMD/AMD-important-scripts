# rpp_related/

RPP (ROCm Performance Primitives) build helper.

## Usage (after running `setup_workspace.sh`)

```bash
# RPP source must be in $AMD_STACK/rpp  or set RPP_SOURCE=/path/to/rpp

build_rpp -r              # release incremental build
build_rpp -r -i           # release build + install
build_rpp -c -r           # clean release build
build_rpp -c -r -i        # clean release build + install
build_rpp -d              # debug build
build_rpp -c -d -i -cpu   # clean debug build, CPU backend, install
build_rpp --config        # print config + run pre-flight checks
build_rpp --help
```

## Options

| Flag | Description |
|---|---|
| `-r` | Release build |
| `-d` | Debug build |
| `-c` | Clean (remove build dir first) |
| `-i` | Install after building |
| `-hip` | HIP backend (default) |
| `-cpu` | CPU/HOST backend |
| `-ocl` | OpenCL backend (enables legacy support) |
| `-j N` | Parallel jobs (default: nproc) |
| `-prefix <path>` | Custom install prefix |
| `--config` | Print config + pre-flight checks only |

## RPP Source Location

`build_rpp` resolves the source directory in this order:

1. `$RPP_SOURCE` environment variable
2. `$(pwd)/rpp` — place RPP source in `$AMD_STACK/rpp` and run from `$AMD_STACK`
