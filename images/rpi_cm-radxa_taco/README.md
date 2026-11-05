# rpi_cm-radxa_taco

Talos Linux for **Radxa TACO** NAS carrier boards with a Raspberry Pi **Compute Module 4
or 5**: installer and disk images built on the
[rpi_cm-radxa_taco kernel](../../kernels/rpi_cm-radxa_taco/README.md).

Stock Talos does not fully support these boards: the TACO's JMB585 SATA controller fails
to probe (error -12), the CM4's NVMe receives no interrupts without MSI-X, and the
board's real-time clock has no driver. These images are stock Talos plus only the fixes
for those issues, taken from Raspberry Pi's kernel and Talos's own config options. The
only extension included is the NIC firmware; add your own on top.

| Board | Status |
|---|---|
| CM4 on TACO v1.3 (`cm4-taco13`) | Works: SATA, NVMe, 2.5 GbE, clock |
| CM5 on TACO v1.3 (`cm5-taco13`) | Works: SATA, NVMe, 2.5 GbE, clock |

Known limitation: a USB keyboard has no effect at the GRUB boot menu on the CM4 (not yet
tested on the CM5); `talosctl rollback` switches boot slots remotely.

## Images

Published at `ghcr.io/achillea-anderson/rpi_cm-radxa_taco/` as
`installer-<board>:<release>-<build>`, alongside the kernel, installer-base and imager
they are built from. All inputs are pinned in this repository; [building](building.md)
describes how to reproduce them.

## Contents

| | |
|---|---|
| [building.md](building.md) | Building the images, and comparing them with the published ones |
| [boards.md](boards.md) | The boards and their quirks |
| [boards/](boards/) | Per board: overlay options, kernel arguments, reference schematic |
| [tests/](tests/) | Load tests and diagnostics |
| [Kernel changes](../../kernels/rpi_cm-radxa_taco/README.md) | Every change from stock Talos: what, why, evidence, when it goes |

Tested on Talos v1.14.2 with the hardware listed in the kernel changes.
