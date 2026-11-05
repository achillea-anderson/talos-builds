# talos-builds

Custom builds for [Talos Linux](https://www.talos.dev): kernels, images and other
components that stock Talos does not provide, each with documentation of what it changes
and why. Everything is built from pinned sources and can be reproduced from this
repository.

## Contents

| Type | | |
|---|---|---|
| Kernels | [rpi_cm-radxa_taco](kernels/rpi_cm-radxa_taco/README.md) | Talos's kernel with the fixes for Raspberry Pi Compute Modules on Radxa TACO boards |
| Images | [rpi_cm-radxa_taco](images/rpi_cm-radxa_taco/README.md) | Installers and disk images for CM4 and CM5 on the Radxa TACO v1.3 |

Further types (overlays, system extensions) get their own top-level directory when the
first one is added.

- [docs/how-it-works.md](docs/how-it-works.md): how Talos builds its kernel and images,
  and where these builds change them.
- [docs/status.md](docs/status.md): what is built and published.

## Images

Published at `ghcr.io/achillea-anderson/<name>/`, one namespace per image family.

## Support

Provided as is, without warranty; test on your own hardware before relying on it. The
goal is for this repository to shrink as its fixes land upstream.

## Licence

Scripts, configuration and documentation: [Mozilla Public License 2.0](LICENSE), the
licence of Talos itself. Kernel patches (`kernels/*/patches/`) are GPL-2.0, like the
kernel they modify; each names its authors.
