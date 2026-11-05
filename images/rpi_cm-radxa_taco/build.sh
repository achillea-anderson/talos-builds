#!/usr/bin/env bash
# Builds Talos for Raspberry Pi Compute Modules on Radxa TACO boards: Talos's own kernel
# plus the patches and config in kernels/$NAME/, the Talos installer and imager on top of
# it, and one installer per board in BOARDS (versions.env; board IDs as in boards.md).
# Pushes each to the registry in versions.env, under $USERNAME/$NAME/.
#
# Run on an arm64 machine with Docker, logged in to the registry:
#   images/rpi_cm-radxa_taco/build.sh
# Prints the installer images to upgrade the nodes to at the end. Each finished step is
# skipped when run again, so after a failure just run it again. Why and how:
# building.md.
#
# A test installer: TEST=<name> build.sh builds, for each board in BOARDS that
# has a boards/<board>/kernel-args-<name>.txt, installer-<board>:<release>-<BUILD>-<name> with the
# kernel arguments of that file instead of boards/<board>/kernel-args.txt, and nothing else. Its
# cleanup keeps the real installers and this test's; the next build of any other kind
# deletes the test images.
#
# CLEANUP=1 makes a run start by deleting the registry images this build does not use (step
# 0), for a registry with a storage quota. Off by default: published images stay, so a node
# or a user pinned to an older build can still pull it.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=versions.env
source "$here/versions.env"

work=${WORK:-$HOME/talos-build}
# The kernel this image family is built on (versions.env, NAME).
kernel_dir=$(cd "$here/../../kernels/$NAME" && pwd)
repo=$REGISTRY/$USERNAME/$NAME
# The kernel is named after what goes into it: the pkgs version, the patches, and the active
# lines of the config fragment (not its comments). installer-base and imager are built on it,
# so they carry the same ID. A change that does not touch the kernel (the overlay options)
# therefore finds these already pushed and only rebuilds the installer, in minutes instead of
# the kernel's 1 h 40 min. BUILD (versions.env) names the installer only.
kernel_id=$(
  {
    echo "$PKGS_VERSION"
    cat "$kernel_dir"/patches/*.patch
    grep -E '^CONFIG_[A-Z0-9_]+=' "$kernel_dir/config-arm64.fragment"
  } | sha256sum | cut -c1-8
)
kernel=$repo/kernel:$PKGS_VERSION-k$kernel_id
base_tag=$TALOS_VERSION-k$kernel_id
test=${TEST:-}
tag=$TALOS_VERSION-$BUILD${test:+-$test}
# The file of extra kernel arguments for a board: boards/<board>/kernel-args.txt, or for a test
# boards/<board>/kernel-args-<test>.txt (a board without one is not built in that test).
args_file() { echo "$here/boards/$1/kernel-args${test:+-$test}.txt"; }
# Every board's real installer, kept by the cleanup even in a test build.
all_boards=$BOARDS
if [ -n "$test" ]; then
  boards=""
  for board in $BOARDS; do [ -f "$(args_file "$board")" ] && boards="$boards $board"; done
  [ -n "$boards" ] || { echo "TEST=$test: no boards/<board>/kernel-args-$test.txt." >&2; exit 1; }
  BOARDS=$boards
fi
echo "kernel ID $kernel_id: $kernel"
for board in $BOARDS; do echo "installer: $repo/installer-$board:$tag"; done

log() { printf '\n==> %s\n' "$*"; }
# True if the image is already in the registry (a finished step).
pushed() { crane manifest "$1" >/dev/null 2>&1; }

[ "$(uname -m)" = aarch64 ] || { echo "Run this on an arm64 machine." >&2; exit 1; }
docker info >/dev/null || { echo "Docker is not running, or you are not in the docker group." >&2; exit 1; }

# A BuildKit builder in its own container: the pkgs and Talos builds need one (the default
# Docker builder cannot push multi-stage results this way).
if ! docker buildx inspect talos >/dev/null 2>&1; then
  docker buildx create --name talos --driver docker-container --driver-opt network=host \
    --buildkitd-flags '--allow-insecure-entitlement security.insecure'
fi
export BUILDX_BUILDER=talos

mkdir -p "$work"

# 0. Cleanup (CLEANUP=1 only), before anything is pushed, for a registry that limits how
#    much an account may store (a push over the limit fails with 413). Keeps what this
#    build uses: kernel, installer-base and imager at this kernel ID, every board's
#    installer-<board>:<release>-<BUILD>, and in a test build its own test installers.
#    Deletes every other tag of those packages (older kernels, older builds, other tests),
#    and every tag of the packages in RETIRED_IMAGES. Never deletes an image a kept tag
#    points to (two tags can name the same image). A node does not need its installer in
#    the registry (its previous system stays on its disk for rollback), but once an older
#    kernel is deleted, going back to it means building it again.
keep="kernel:$PKGS_VERSION-k$kernel_id
installer-base:$base_tag
imager:$base_tag"
packages="kernel installer-base imager"
for board in $all_boards; do
  keep="$keep
installer-$board:$TALOS_VERSION-$BUILD"
  packages="$packages installer-$board"
done
for board in $BOARDS; do keep="$keep
installer-$board:$tag"; done
if [ "${CLEANUP:-0}" = 1 ]; then
  log "cleanup: deleting images this build does not use"
  # The digests the kept tags point to.
  kept_digests=$(
    echo "$keep" | while IFS=: read -r package ktag; do
      crane digest "$repo/$package:$ktag" 2>/dev/null || true
    done
  )
  refused=""
  for package in $packages ${RETIRED_IMAGES:-}; do
    for old in $(crane ls "$repo/$package" 2>/dev/null || true); do
      if grep -qx "$package:$old" <<<"$keep"; then
        echo "cleanup: keeping $package:$old"
        continue
      fi
      digest=$(crane digest "$repo/$package:$old")
      if grep -qx "$digest" <<<"$kept_digests"; then
        echo "cleanup: keeping $package:$old (same image as a kept tag)"
      elif crane delete "$repo/$package@$digest"; then
        echo "cleanup: deleted $package:$old"
      else
        refused="$refused $package:$old"
      fi
    done
  done
  # Not fatal: the build may still fit. If a push then fails with 413, delete these in the
  # registry's web interface and run again.
  [ -z "$refused" ] || echo "cleanup: the registry refused deleting:$refused" >&2
fi

# 1. The kernel: siderolabs/pkgs at the commit Talos was built from, plus our patches and
#    our config changes (config-arm64.fragment).
if pushed "$kernel"; then
  log "kernel: $kernel is already pushed"
else
  log "kernel: building $kernel"
  [ -d "$work/pkgs" ] || git clone https://github.com/siderolabs/pkgs.git "$work/pkgs"
  git -C "$work/pkgs" fetch --tags origin
  git -C "$work/pkgs" checkout --force --detach "${PKGS_VERSION##*-g}"
  git -C "$work/pkgs" clean -fdx kernel/build/patches
  mkdir -p "$work/pkgs/kernel/build/patches"
  cp "$kernel_dir"/patches/*.patch "$work/pkgs/kernel/build/patches/"
  # Each CONFIG_NAME=value line replaces that option's existing line, set or "is not set".
  # An option that is not there at all stops the build: renamed or removed upstream.
  config="$work/pkgs/kernel/build/config-arm64"
  grep -E '^CONFIG_[A-Z0-9_]+=' "$kernel_dir/config-arm64.fragment" | while IFS= read -r line; do
    name=${line%%=*}
    grep -q -E "^($name=|# $name is not set$)" "$config" ||
      { echo "config-arm64.fragment: $name is not in Talos's config-arm64." >&2; exit 1; }
    sed -i -E "s~^($name=.*|# $name is not set)$~$line~" "$config"
    echo "kernel config: $line"
  done
  make -C "$work/pkgs" kernel PLATFORM=linux/arm64 \
    REGISTRY="$REGISTRY" USERNAME="$USERNAME/$NAME" TAG="$PKGS_VERSION-k$kernel_id" PUSH=true
fi

# 2. Talos's installer-base and imager with that kernel. TAG stays the release's own
#    (it is the version Talos reports); only the image tags get our suffix.
if pushed "$repo/installer-base:$base_tag" && pushed "$repo/imager:$base_tag"; then
  log "talos: installer-base and imager $base_tag are already pushed"
else
  log "talos: building installer-base and imager $base_tag"
  [ -d "$work/talos" ] || git clone https://github.com/siderolabs/talos.git "$work/talos"
  git -C "$work/talos" fetch --tags origin
  git -C "$work/talos" checkout --force --detach "$TALOS_VERSION"
  # Talos copies the modules named in hack/modules-arm64.txt from the kernel image. A module
  # our config made built-in (CONFIG_I2C_GPIO=y pulls i2c-algo-bit into the kernel) has no
  # .ko any more, and the copy fails ("xargs … exit code 123"). So keep only the listed
  # modules our kernel image really has, and print each one dropped.
  list="$work/talos/hack/modules-arm64.txt"
  crane export --platform linux/arm64 "$kernel" - | tar -t |
    sed -n -E 's|^(\./)?usr/lib/modules/[^/]+/(kernel/.*\.ko)$|\2|p' | sort -u >"$work/kernel-modules.txt"
  [ -s "$work/kernel-modules.txt" ] || { echo "No modules found in $kernel." >&2; exit 1; }
  # Only .ko lines are filtered; the list's other files (modules.order, modules.builtin…)
  # stay. Dropped lines go to stderr, the kept list to the file.
  awk 'NR==FNR { have[$0] = 1; next }
       /\.ko$/ && !($0 in have) { print "modules: dropped (built in): " $0 > "/dev/stderr"; next }
       { print }' "$work/kernel-modules.txt" "$list" >"$list.ours"
  mv "$list.ours" "$list"
  make -C "$work/talos" installer-base imager PLATFORM=linux/arm64 INSTALLER_ARCH=targetarch \
    PKG_KERNEL="$kernel" REGISTRY="$REGISTRY" USERNAME="$USERNAME/$NAME" \
    TAG="$TALOS_VERSION" TAG_SUFFIX_OUT="-k$kernel_id" PUSH=true
fi

# 3. One installer per board: the imager puts the board's Raspberry Pi overlay (boot
#    firmware, device trees, config.txt with boards/<board>/overlay-options.yaml's additions) and the
#    Realtek NIC firmware into it, at the versions made for this Talos release (as an Image
#    Factory schematic would, boards/<board>/schematic.yaml). Only what the hardware needs: add
#    your own extensions with this imager (building.md). No extension with kernel
#    modules: our kernel would refuse them.
#
# image-digests lists one extension per line, as image:tag@sha256:digest.
digests=$(crane export --platform linux/arm64 "ghcr.io/siderolabs/extensions:$TALOS_VERSION" - | tar -xO image-digests)
realtek=$(grep -o 'ghcr.io/siderolabs/realtek-firmware:[^ "@]*@sha256:[0-9a-f]*' <<<"$digests" | head -1)
[ -n "$realtek" ] || { echo "Could not find realtek-firmware for $TALOS_VERSION." >&2; exit 1; }
built=""
metals=""
for board in $BOARDS; do
  installer=$repo/installer-$board:$tag
  built="$built $installer"
  # The Raspberry Pi overlay follows from the module: a CM5 is Pi 5 class, a CM4 Pi 4 class.
  case "$board" in
    cm5-*) overlay_name=rpi_5 ;;
    cm4-*) overlay_name=rpi_generic ;;
    *) echo "$board: no overlay known for this module (build.sh)." >&2; exit 1 ;;
  esac
  [ -f "$here/boards/$board/overlay-options.yaml" ] ||
    { echo "$board: boards/$board/overlay-options.yaml is missing." >&2; exit 1; }
  # Optional extra kernel arguments for this board, one per line (args_file).
  kernel_args=()
  extra_args=()
  if [ -f "$(args_file "$board")" ]; then
    while IFS= read -r arg; do
      case "$arg" in '' | '#'*) continue ;; esac
      kernel_args+=(--extra-kernel-arg "$arg")
      extra_args+=("$arg")
    done <"$(args_file "$board")"
  fi
  # A metal disk image of the same build, for writing straight to a new board's eMMC
  # (with dd or any image writer), so the board boots our kernel from the start
  # instead of a stock image that must be upgraded first (and that hangs on the CM4 with the
  # NVMe fitted). A file on this machine, not pushed: copy it to the machine that writes it.
  metal=$work/images/metal-$board-$tag-arm64.raw.zst
  metals="$metals $metal"
  if pushed "$installer" && [ -f "$metal" ]; then
    log "installer: $installer is already pushed, and $metal exists"
    continue
  fi
  # overlays.yaml lists each overlay as "- name: rpi_5" followed by its image and digest lines.
  overlay=$(crane export --platform linux/arm64 "ghcr.io/siderolabs/overlays:$TALOS_VERSION" - | tar -xO overlays.yaml |
    awk -v name="$overlay_name" '$3==name{f=1;next} f&&$1=="image:"{img=$2} f&&$1=="digest:"{print img"@"$2; exit}')
  [ -n "$overlay" ] || { echo "Could not find overlay $overlay_name for $TALOS_VERSION." >&2; exit 1; }
  echo "overlay:   $overlay ($overlay_name)"
  echo "extensions: $realtek"
  echo "kernel arguments: ${kernel_args[*]:-none}"
  # The same imager run for both outputs, differing only in the profile (installer, metal).
  # The imager pulls installer-base itself, so it gets the registry login too (read-only;
  # go-containerregistry reads Docker's credentials from $DOCKER_CONFIG). Without it a
  # private package fails with 401.
  imager() {
    docker run --rm -t --network=host --user "$(id -u):$(id -g)" -v "$2:/out" \
      -v "$HOME/.docker:/docker-config:ro" -e DOCKER_CONFIG=/docker-config \
      -v "$here:/taco:ro" \
      "$repo/imager:$base_tag" "$1" --arch arm64 \
      --base-installer-image "$repo/installer-base:$base_tag" \
      --overlay-image "$overlay" --overlay-name "$overlay_name" \
      --overlay-option "@/taco/boards/$board/overlay-options.yaml" \
      "${kernel_args[@]}" \
      --system-extension-image "$realtek"
  }
  if pushed "$installer"; then
    log "installer: $installer is already pushed"
  else
    log "installer: building $installer"
    out="$work/out-$board-$tag"
    rm -rf "$out" && mkdir -p "$out"
    imager installer "$out"
    crane push "$out/installer-arm64.tar" "$installer"
  fi
  # The metal image needs GRUB, not the imager's default for arm64 (systemd-boot since Talos
  # 1.10, pkg/imager/profile/output.go): only with GRUB does the disk image get the overlay's
  # Raspberry Pi boot chain (firmware, config.txt, U-Boot), as Image Factory's Pi images
  # have; with systemd-boot the board stops at "Firmware not found". The imager has no flag
  # for the bootloader, so the whole profile goes in on stdin (`imager -`): the same inputs
  # as the flags above, plus output.imageOptions.bootloader.
  metal_profile() {
    cat <<EOF
arch: arm64
platform: metal
secureboot: false
version: $TALOS_VERSION
customization:
  extraKernelArgs: [$( ((${#extra_args[@]})) && printf '"%s",' "${extra_args[@]}" | sed 's/,$//')]
input:
  kernel:
    path: /usr/install/arm64/vmlinuz
  initramfs:
    path: /usr/install/arm64/initramfs.xz
  baseInstaller:
    imageRef: $repo/installer-base:$base_tag
  overlayInstaller:
    imageRef: $overlay
  systemExtensions:
    - imageRef: $realtek
overlay:
  name: $overlay_name
  image:
    imageRef: $overlay
  options:
$(sed 's/^/    /' "$here/boards/$board/overlay-options.yaml")
output:
  kind: image
  outFormat: .zst
  imageOptions:
    diskSize: 1306525696
    diskFormat: raw
    bootloader: grub
EOF
  }
  # A metal image without the Pi boot chain must fail the build, not reach a board: look
  # inside its first (FAT) partition, at 1 MiB, for U-Boot, config.txt and the module's
  # device tree, plus the GPU firmware on a Pi 4-class module (a Pi 5-class one keeps its
  # firmware in its EEPROM, so its boot partition has no start*.elf).
  case "$overlay_name" in
    rpi_generic) boot_files=(::/start4.elf ::/fixup4.dat ::/bcm2711-rpi-cm4.dtb) ;;
    rpi_5) boot_files=(::/bcm2712-rpi-cm5-cm4io.dtb) ;;
  esac
  check_metal() {
    local raw="$work/check-$board.raw"
    zstd -dc "$1" >"$raw"
    if nix shell nixpkgs#mtools -c env MTOOLS_SKIP_CHECK=1 mdir -b -i "$raw@@1048576" \
      ::/u-boot.bin ::/config.txt "${boot_files[@]}" >/dev/null &&
      nix shell nixpkgs#mtools -c env MTOOLS_SKIP_CHECK=1 mtype -i "$raw@@1048576" ::/config.txt |
      grep -q '^kernel=u-boot.bin'; then
      rm -f "$raw"
      echo "metal image check: U-Boot, config.txt and ${boot_files[*]#::/} present"
    else
      rm -f "$raw"
      echo "metal image check FAILED: $1 has no Raspberry Pi boot chain." >&2
      return 1
    fi
  }
  if [ -f "$metal" ]; then
    log "metal image: $metal exists"
    check_metal "$metal"
  else
    log "metal image: building $metal"
    out="$work/out-metal-$board-$tag"
    rm -rf "$out" && mkdir -p "$out" "$work/images"
    metal_profile | docker run --rm -i --network=host --user "$(id -u):$(id -g)" -v "$out:/out" \
      -v "$HOME/.docker:/docker-config:ro" -e DOCKER_CONFIG=/docker-config \
      "$repo/imager:$base_tag" -
    check_metal "$out/metal-arm64.raw.zst"
    mv "$out/metal-arm64.raw.zst" "$metal"
  fi
done

log "done. Upgrade a node to its board's installer with:"
for installer in $built; do echo "  talosctl -n <node> upgrade --image $installer"; done
echo "Or write a new board's eMMC with its metal image (copy it to the laptop first):"
for metal in $metals; do echo "  $metal"; done
