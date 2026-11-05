# rpi_cm-radxa_taco: deviations from stock Talos

Our images are stock Talos as Image Factory would make it for the board (the
`sbc-raspberrypi` overlay, `rpi_generic` for a CM4 or `rpi_5` for a CM5, and the
`realtek-firmware` extension), plus **only what the TACO's hardware needs** to boot with
every device working: the fewest changes we could find. Everything we change is listed
here with why, the evidence, and when it can go. Nothing else is added: tuning (interrupt
steering and the like) is machine configuration, recommended under "Node settings".

Tested on Talos v1.14.2 (kernel 6.18.54, siderolabs/pkgs `6c312e4`), on a CM4 (8 GB,
eMMC) and a CM5 on Radxa TACO v1.3 boards, each with three SATA HDDs on the JMB585 and an
NVMe (SK hynix Gold P31) in the M.2 slot. See [boards](../../images/rpi_cm-radxa_taco/boards.md).

## Summary

| Change | Where | Needed for | Goes when |
|---|---|---|---|
| Patch 0001: the JMB585 may use 64-bit DMA | `patches/0001-…` | SATA | Talos's kernel carries the revert |
| Patch 0002: MSI-X for the brcmstb PCIe controller | `patches/0002-…` | NVMe interrupts (and the RTL8125) without `pci=nomsi` | mainline pcie-brcmstb gains MSI-X and Talos ships it |
| `CONFIG_RTC_DRV_PCF8563=y`, `CONFIG_I2C_GPIO=y` | `config-arm64.fragment` | the TACO's real-time clock | Talos enables both |
| Module list filtered | `images/rpi_cm-radxa_taco/build.sh`, step 2 | a side effect of `I2C_GPIO=y` | with the line above |
| `dtoverlay=i2c-rtc-gpio,pcf8563,…` | `images/rpi_cm-radxa_taco/boards/<board>/overlay-options.yaml` | the real-time clock | never: it describes the board's wiring |
| Our own installer-base and imager | `images/rpi_cm-radxa_taco/build.sh`, step 2 | they carry the patched kernel | with the patches |

Not deviations: the overlays and `realtek-firmware` are Sidero's own, at the versions made
for the same Talos release. The metal images use GRUB, as Sidero's own Raspberry Pi
images do (Pi firmware, then the overlay's U-Boot, then GRUB); the imager's default for
arm64 disk images, systemd-boot, has no Pi firmware and cannot boot a Pi. No extra kernel
arguments. The PCIe switch (ASM1806) needs nothing.

## Patch 0001: JMB585 64-bit DMA

**What.** Raspberry Pi's partial revert of upstream commit 105c42566a55 ("ata: ahci:
force 32-bit DMA for JMicron JMB582/JMB585"), as carried in raspberrypi/linux
`rpi-6.18.y` (commit 40116166e8e7, pull request #7393, by Phil Elwell).

**Why.** The upstream commit forces a 32-bit DMA mask on the JMB585. On a BCM2712 (CM5)
the PCIe controller has no usable inbound window below 4 GB, and on the CM4 the RAM sits
above 4 GB on the PCIe bus as well, so the forced mask makes the controller fail to probe
(`ahci … error -12`) and no SATA disk appears.

**Evidence.**
- Stock Talos v1.14.2 on a CM5 TACO: the JMB585 fails with error -12; no SATA disks.
- The `pcie-32bit-dma-pi5` overlay makes SATA work but breaks the NVMe behind the same
  PCIe switch, also with a larger swiotlb.
- Raspberry Pi OS (kernel 6.18.50+rpt, which carries this revert) on the same board: SATA
  and NVMe together, a parallel read of all disks, and a 500 GiB fio write-verify that
  passed.
- Our build with the patch: SATA and NVMe together under a sustained fio load
  ([disk-load.yaml](../../images/rpi_cm-radxa_taco/tests/disk-load.yaml)) with a clean kernel log, on both
  boards.

**Check.** `talosctl dmesg | grep -i ahci` shows the JMB585 with `flags: 64bit ncq …`, no
"forcing 32bit", no error -12.

## Patch 0002: MSI-X for pcie-brcmstb

**What.** Raspberry Pi's MSI-X support for the BCM2711/BCM2712 PCIe controller's
internal MSI target, as carried in raspberrypi/linux since 2025-04-02 (commit
831b46008fa4, in `rpi-6.18.y`, by Jonathan Bell).

**Why.** Mainline's `pcie-brcmstb` offers only MSI and multi-MSI, so every device falls
back from MSI-X to MSI. The NVMe on the CM4 TACO does not work on plain MSI: its admin
commands complete but no interrupt arrives (`QID 0 timeout, completion polled`) and the
boot stalls. The usual workaround, `pci=nomsi`, puts the NVMe and the 2.5 GbE NIC on one
shared legacy interrupt handled by CPU0; under disk load the node then received only
about 0.4 Gbit/s, with CPU0 saturated in softirq.

**Evidence.**
- Under mainline Talos the CM4 TACO's NVMe gets no interrupts; with `pci=nomsi` it works
  at the cost above.
- Raspberry Pi OS (6.18.50+rpt, which carries this patch) on the same board: the NVMe on
  MSI-X with four queues, at full speed, both when the firmware starts the kernel
  directly and through Talos's U-Boot.
- Our build with the patch and without `pci=nomsi`: the NVMe on MSI-X with four queues;
  disk and network load tests clean.

**Check.** `talosctl read /proc/interrupts | grep nvme` shows several queues on MSI-X.

## The real-time clock

**What.** The TACO has a PCF8563-compatible clock at I2C address 0x51 on GPIO 2 (SDA) and
3 (SCL), with pull-ups on the board and a CR1220 cell. Talos's kernel lacks the PCF8563
driver, and under Talos the CM5's RP1 hardware I2C on those pins gets no acknowledgement
from any device (pins, function, clock and pull-ups all checked out). Software I2C over
plain GPIO works, as it does under Raspberry Pi OS. So: `CONFIG_RTC_DRV_PCF8563=y` and
`CONFIG_I2C_GPIO=y` in the kernel, and in each board's config.txt
`dtoverlay=i2c-rtc-gpio,pcf8563,i2c_gpio_sda=2,i2c_gpio_scl=3`. The CM4 uses the same
recipe, so it depends on neither chip's I2C controller.

**Why.** Without a clock the nodes boot at 1970 and depend on NTP before any certificate
is valid.

**Side effect.** `I2C_GPIO=y` makes `i2c-algo-bit` built in, so it has no `.ko` any more,
and Talos's module copy (`hack/modules-arm64.txt`) fails. `build.sh` drops the listed
modules the kernel image does not have, and prints each one.

**Fallback.** If Talos ever ships the JMB585 fix but not this driver, our kernel can go
and a device-tree overlay can describe the clock instead: an `rtc@51` node with
`compatible = "haoyu,hym8563"` on an `i2c-gpio` bus (Talos has `RTC_DRV_HYM8563`; same
register layout), shipped in an overlay image derived from `sbc-raspberrypi`.

**Check.** `talosctl dmesg | grep -i rtc` shows `rtc-pcf8563 … registered as rtc0` and
the system clock set from it, not 1970. A clock reading nonsense or "voltage low" has lost
its time: check the CR1220 cell.

## Node settings (machine config, not the image)

Recommended on a CM4 TACO, measured with iperf3 and fio on the board:

- **Receive Packet Steering** on the 2.5 GbE (`enp4s0`) onto CPUs 1 to 3
  ([rps-enp4s0.yaml](../../images/rpi_cm-radxa_taco/tests/rps-enp4s0.yaml)): every MSI on the CM4 lands on
  CPU0, and RPS moves the receive work off it (2.03 to 2.13 Gbit/s receiving; about 15 %
  more under full disk load).
- **Not threaded NAPI** ([napi-threaded-enp4s0.yaml](../../images/rpi_cm-radxa_taco/tests/napi-threaded-enp4s0.yaml)):
  on Talos it never helped.
- With two NICs on one VLAN: a static address on the 2.5 GbE only (no DHCP; it has no
  fixed MAC), selected by driver and bus path rather than MAC, and the ARP sysctls
  `arp_ignore=1`, `arp_announce=2`.

For reference, the CM4 TACO's network on our build: 2.13 Gbit/s receiving, 2.32 sending,
1.03 / 2.31 both ways at once; Raspberry Pi OS hardened like Talos reaches 2.31 / 2.32 /
1.18 on the same board ([bench-rpios.sh](../../images/rpi_cm-radxa_taco/tests/bench-rpios.sh)). The gap is in
line with Talos's compiled-in hardening and Kubernetes' overhead.

## Upstreaming

The aim is for this repository to shrink: the JMB585 revert and the brcmstb MSI-X support
belong in the kernel Talos ships, and the RTC options in Talos's arm64 config. Reports to
siderolabs/pkgs are planned once the changes have a longer track record, so the reports
can include reliability data.
