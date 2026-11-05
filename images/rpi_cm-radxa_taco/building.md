# Building the images

`build.sh` builds Talos for the TACO boards from source: Talos's own kernel with
our patches and config changes, Talos's installer-base and imager on that kernel, and one
installer and one metal disk image per board. You can use our published images, or build
your own with this page and compare. How the pieces fit together:
[how-it-works](../../docs/how-it-works.md). What we change and why: [deviations](../../kernels/rpi_cm-radxa_taco/README.md).

## What gets built

| Image | What it is |
|---|---|
| `kernel:<pkgs version>-k<kernel ID>` | Talos's kernel with `kernels/rpi_cm-radxa_taco/patches/*.patch` and the options in `kernels/rpi_cm-radxa_taco/config-arm64.fragment` |
| `installer-base:<talos version>-k<kernel ID>` | Talos with that kernel, for no board in particular |
| `imager:<talos version>-k<kernel ID>` | The tool that turns installer-base into images for a board, with any extensions you choose |
| `installer-<board>:<talos version>-<build>` | What a node of that board installs and upgrades to: installer-base plus the board's Raspberry Pi overlay (with `boards/<board>/overlay-options.yaml`'s config.txt additions) and the Realtek NIC firmware |
| `metal-<board>-<talos version>-<build>-arm64.raw.zst` | A disk image of the same, for writing to a new board's eMMC with any image writer; a file, not pushed |

The **kernel ID** is a short hash of what goes into the kernel: the pkgs version, the
patches, and the active lines of the config fragment. When an image with that ID is
already in the registry, the kernel, installer-base and imager steps are skipped and only
the installers are built (minutes instead of hours). The **build** (`b1`, `b2`, …,
`BUILD` in `versions.env`) names the installers only, and restarts at `b1` for
each Talos release.

Talos reports the release it was built from (our build of v1.14.2 says v1.14.2); our
images are told apart by registry and tag suffix.

## Adding your own extensions

The installers carry only what the hardware needs. To add extensions of your own,
run our imager yourself with the board's overlay and your extensions, as
`build.sh` does in step 3, adding `--system-extension-image <image>@<digest>` for each.
Take the digests from `ghcr.io/siderolabs/extensions:<talos version>` (its
`image-digests` file), as `build.sh` does for `realtek-firmware`.

**Extensions with kernel modules do not work** on our kernel: Talos only loads modules
signed with its own build's key, and Sidero's extensions are signed for Sidero's kernel.
Firmware-only and userspace extensions are fine.

## What you need

- An **arm64 machine** with Docker and BuildKit (`docker buildx`), `make`, `git`,
  [`crane`](https://github.com/google/go-containerregistry), `zstd`, and Nix (for
  `mtools` in the metal image check). Building natively on arm64 avoids emulation; the
  kernel takes about 1 h 40 min on an 8-core RK3588 board.
- Free disk space for the work tree under `~/talos-build` (set `WORK=` to change) and
  Docker's build cache: several tens of GB (not measured precisely).
- A **registry** you can push to, logged in with `docker login <registry>`. `build.sh`
  pushes to `$REGISTRY/$USERNAME/rpi_cm-radxa_taco/` (defaults in `versions.env`; set both in the
  environment for your own). Pushing to GitHub's registry needs a token with
  `write:packages`.

## Building

On the arm64 machine, in `images/rpi_cm-radxa_taco/` of a clone of this repository (the
commands and paths on this page are relative to it), inside `tmux` or `screen` (it takes a
while, and a dropped SSH session would stop it). First check that the checkout is the
commit you mean to build:

```
git log --oneline -1
grep -n '^BUILD=' versions.env
ls ../../kernels/rpi_cm-radxa_taco/patches/
```

Then:

```
REGISTRY=ghcr.io USERNAME=<your account> ./build.sh 2>&1 | tee ~/talos-build/build.log
```

Its first line prints the kernel ID; a change to a patch or the fragment must give a new
one. Each step checks the registry first and skips what is already pushed, so after a
failure (network, disk space) fix the cause and run it again. At the end it prints the
installer images and the metal images it wrote.

## Checking our images against your build

Everything that goes in is pinned: the Talos release and pkgs commit
(`versions.env`), the patches and config lines (in this repository), and the
overlay and extensions (by digest, from Sidero's release manifests). To compare:

```
crane digest ghcr.io/achillea-anderson/rpi_cm-radxa_taco/kernel:<pkgs version>-k<kernel ID>
crane digest $REGISTRY/$USERNAME/rpi_cm-radxa_taco/kernel:<pkgs version>-k<kernel ID>
```

**Reproducibility is not yet verified by us.** Talos is built to be reproducible, but we
have not yet compared two independent builds of our images. Until we have, and say so
here with the matching digests, treat a mismatch as unexplained rather than as tampering,
and prefer your own build.

## A new Talos release

1. In `versions.env`: `TALOS_VERSION` to the new release, `PKGS_VERSION` to the
   `PKGS ?=` line of siderolabs/talos's `Makefile` at that tag, and `BUILD` back to `b1`.
2. Check each patch is still needed in the kernel that pkgs commit uses. For `0001`: does
   the JMB585 get 64-bit DMA on a BCM2711/2712? For `0002`: does
   `BRCM_MSI_FLAGS_SUPPORTED` in `drivers/pci/controller/pcie-brcmstb.c` include
   `MSI_FLAG_PCI_MSIX`? Drop the ones the kernel has. Likewise the fragment: does the new
   `config-arm64` already set the options? If nothing is left, the boards can go back to
   Image Factory images (`boards/<board>/schematic.yaml`).
3. Run `build.sh`. A patch that no longer applies stops the kernel step ("Failed to apply
   patch"): the code around it changed, so look again before forcing it. A fragment option
   gone from Talos's config stops with "… is not in Talos's config-arm64".
4. Upgrade nodes one at a time.

A change within the same release (patches, fragment, overlay options): bump `BUILD`
(`b2`, `b3`, …), build, upgrade.

## A new board

A board ID is module + carrier + revision ([boards](boards.md)). Add
`boards/<board>/overlay-options.yaml` (its config.txt additions; `configTxtAppend: ""` if none),
optionally `boards/<board>/kernel-args.txt` (extra kernel arguments, one per line), add
the ID to `BOARDS` in `versions.env`, and check that `build.sh` knows the module's
overlay (`cm5-*` → `rpi_5`, `cm4-*` → `rpi_generic`). Only the new installer is built.

## A test installer

On Talos 1.14 a kernel argument can only change through the installer image. To try one
without touching a board's real installer: write
`boards/<board>/kernel-args-<name>.txt`, then `TEST=<name> ./build.sh`. It builds
only `installer-<board>:<release>-<build>-<name>` for the boards with such a file, reusing
the pushed kernel.

## Upgrading a node and going back

A Talos upgrade replaces the whole system from an installer image:

```
talosctl -n <node> upgrade --image <registry>/<owner>/installer-<board>:<release>-<build>
```

The previous system stays on the node's disk; `talosctl rollback` returns to it. To leave
our build entirely, upgrade to the Image Factory installer for the board's schematic
(`boards/<board>/schematic.yaml`, `factory.talos.dev/metal-installer/<id>:<release>`); SATA
then fails again on the TACO until Talos carries the fix.

## Registry space

Published images are kept: a node pinned to an older build can still pull it. For a
registry with a storage quota, `CLEANUP=1 ./build.sh` first deletes the images this
build does not use (older kernels and builds, other tests, `RETIRED_IMAGES`), keeping
anything a kept tag points to. A deleted older kernel must be built again to go back to
it.
