# How Talos builds its kernel, and how we change it

Background for [building](../images/rpi_cm-radxa_taco/building.md) the images in this repository.

## Two repositories, many images

Talos is put together from container images, built with Docker BuildKit:

- **siderolabs/pkgs** builds every low-level piece Talos ships (the kernel, containerd,
  cryptsetup, …), each as its own image. Its `Pkgfile` and the `pkg.yaml` in each folder
  describe the steps; a tool called bldr turns them into a BuildKit build. A commit of
  pkgs fixes exact versions: at `6c312e4` the kernel is Linux 6.18.54 with Talos's config
  (`kernel/build/config-arm64`).
- **siderolabs/talos** builds Talos itself (machined, the API, the init system) and
  assembles it with the pkgs images. Its `Makefile` names the pkgs version it uses
  (`PKGS ?= v1.14.0-37-g6c312e4` for v1.14.2), and every piece can be swapped by name:
  `PKG_KERNEL=<image>` replaces the kernel and nothing else.

So "Talos v1.14.2 with a different kernel" means: build pkgs' kernel image at the same
commit with our patches, and build Talos v1.14.2 pointing `PKG_KERNEL` at it.

## The kernel steps in pkgs

- `kernel/prepare` downloads the kernel source from kernel.org (checked against its
  hashes) and unpacks it.
- `kernel/build` copies in Talos's config, **applies every `kernel/build/patches/*.patch`**
  in name order, and compiles the kernel, its modules and (on arm64) the device trees.
  Our patches go in that folder, and `build.sh` edits the config lines named in
  `config-arm64.fragment`; no build file changes.
- `kernel` packages the result.

Modules are signed during the build with a key made for that build. A Talos kernel only
loads modules signed with its own key, so system extensions that bring kernel modules (a
driver, ZFS) must be built against the same kernel build. Sidero's extensions carry
signatures our kernel does not accept; firmware-only and userspace extensions such as
`realtek-firmware` work.

## installer-base, imager, installer

- **installer-base**: Talos (kernel, initramfs, the installer program) for an
  architecture, but no particular board.
- **imager**: a tool image that takes installer-base and adds a board's pieces, producing
  disk images, ISOs, or an installer.
- **installer**: what a node runs to install or upgrade itself. For a Raspberry Pi it is
  installer-base plus the **overlay** (`sbc-raspberrypi`: the Pi's boot firmware,
  config.txt, U-Boot and device trees) plus any **system extensions**.

Image Factory does exactly the imager step on Sidero's servers, from a schematic (overlay,
extensions, kernel arguments), always with Sidero's installer-base. It cannot use a
different kernel, which is why we run the imager ourselves. To match the Factory,
`build.sh` takes the overlay and extension versions made for the same Talos release from
`ghcr.io/siderolabs/overlays:<release>` and `ghcr.io/siderolabs/extensions:<release>`.

## Upgrades

A Talos upgrade replaces the whole system from an installer image, so moving a node to our
build, to a newer release, or back to Image Factory are all the same command with a
different `--image`. Kubernetes upgrades are separate and unaffected.
