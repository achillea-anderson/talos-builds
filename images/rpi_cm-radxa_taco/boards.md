# Boards

## Board IDs

A board is a module on a carrier at a revision: `<module>-taco<revision>`, e.g.
`cm5-taco13` is a Compute Module 5 on a TACO v1.3. Revisions differ in what matters here
(PCIe switch, which modules fit, maybe the clock chip), and what works on one says little
about another, so the ID names everything per board: its build options
(`boards/<board>/overlay-options.yaml`, `boards/<board>/kernel-args.txt`), its installer
(`installer-<board>`) and its reference schematic (`boards/<board>/schematic.yaml`).

| Board ID | Module on carrier | Status |
|---|---|---|
| `cm4-taco13` | CM4 (8 GB, eMMC) on TACO v1.3 | Works: SATA, NVMe on MSI-X, 2.5 GbE, clock; load tests passed |
| `cm5-taco13` | CM5 on TACO v1.3 | Works: SATA, NVMe, 2.5 GbE, clock; load test passed |
| `cm5-taco161` | CM5 on TACO v1.61 | Not tested yet; would get its own ID and installer |

## Radxa TACO v1.3

A NAS carrier board for a Raspberry Pi Compute Module.

- **Modules:** designed for the CM4 (Radxa lists the Radxa CM3 and the CM4); a CM5 fits
  and works.
- **PCIe:** the module's one lane goes to an ASMedia **ASM1806**, a PCIe Gen 2 switch, so
  about 445 MB/s per direction for everything behind it.
- **Storage:** 5× SATA through a JMicron **JMB585**; 1× M.2 M-key 2280 for NVMe; 1× M.2
  E-key.
- **Network:** 1 GbE from the Compute Module itself (fixed MAC), and **2.5 GbE** from a
  Realtek **RTL8125B** behind the switch, with **no fixed MAC**: a new locally
  administered one on every boot (`permanentAddr` is empty under Talos). Configure it by
  driver and bus path, with a static address.
- **Clock:** a **PCF8563-compatible** chip at 0x51 on GPIO 2 (SDA) / 3 (SCL), with
  pull-ups on the board, kept running by a **CR1220** cell (which powers this chip, not a
  CM5's own clock).
- **Power:** 12 V (barrel jack or header).
- **USB:** the USB-A port reaches the module's boot ROM for `rpiboot` (hold RPI BOOT while
  powering on), but writing a CM4's eMMC through it was unreliable for us, and a CM5's
  eMMC never appeared through it; a Raspberry Pi CM IO Board worked. The USB-C port does
  not reach the boot ROM.
- **Console:** HDMI from the module. A USB keyboard does nothing at Talos's GRUB menu on
  the CM4 TACO (untested on the CM5); `talosctl rollback` switches boot slots remotely.

## Radxa TACO v1.61

CM5 only, with a "PCIe 3.0 switch" and USB 3.2. Its chips (switch, SATA, Ethernet, clock)
are not published. If its SATA controller is still a JMB585 it needs our kernel too; Gen 3
may need `dtparam=pciex1_gen=3` in config.txt. To check on a first board: Talos boot,
`lspci` chips and link speed (8 GT/s), SATA and NVMe together.
