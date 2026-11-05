#!/bin/sh
# The same dump as pci-debug.yaml, for a board running Raspberry Pi OS instead of Talos, so
# the two can be compared section by section. Read-only. Runs as root on the board:
#
#   ssh <user>@<board> 'sudo sh -s' < tests/pci-debug-rpios.sh > pci-debug-rpios.txt
#
# It shows how Raspberry Pi OS runs the hardware: whether the NVMe is on MSI-X and with
# how many queues, and what differs from Talos in the PCIe state, the kernel
# configuration and the boot path (the firmware starts this kernel directly; Talos goes
# through U-Boot first).
echo "===== kernel"; uname -a
echo "===== cmdline"; cat /proc/cmdline
echo "===== firmware"; vcgencmd version 2>&1; vcgencmd bootloader_version 2>&1
echo "===== eeprom config"; vcgencmd bootloader_config 2>&1
echo "===== config.txt"
grep -v -E '^\s*(#|$)' /boot/firmware/config.txt 2>/dev/null || grep -v -E '^\s*(#|$)' /boot/config.txt
echo "===== kernel config (pci, msi, nvme)"
grep -E 'CONFIG_(PCIE_BRCMSTB|PCI_MSI|PCIEPORTBUS|PCIEASPM|NVME_CORE|BLK_DEV_NVME|ARM_GIC|BCM2835_MBOX)' \
  "/boot/config-$(uname -r)" 2>/dev/null || { modprobe configs 2>/dev/null; zcat /proc/config.gz 2>/dev/null |
  grep -E 'CONFIG_(PCIE_BRCMSTB|PCI_MSI|PCIEPORTBUS|PCIEASPM|NVME_CORE|BLK_DEV_NVME|ARM_GIC|BCM2835_MBOX)'; }
echo "===== tree"; lspci -tv
echo "===== devices"; lspci -vvv -nn
echo "===== iomem"; cat /proc/iomem
echo "===== host bridge device tree (ranges, dma-ranges, msi)"
for n in /proc/device-tree/scb/pcie@*; do
  [ -d "$n" ] || continue
  echo "$n"; ls "$n"
  for p in ranges dma-ranges msi-parent msi-controller interrupt-names compatible; do
    [ -e "$n/$p" ] && { echo "-- $p"; hexdump -C "$n/$p"; }
  done
done
echo "===== dmesg (pci, brcm, msi, nvme)"
dmesg 2>/dev/null | grep -i -E 'pci|brcm|msi|nvme' | head -200
echo "===== nvme irqs (per vector: affinity and effective cpu)"
for d in /sys/bus/pci/devices/*; do
  [ "$(cat "$d/class")" = "0x010802" ] || continue
  echo "$d"
  ls "$d/msi_irqs" 2>/dev/null | while read -r irq; do
    printf 'irq %s mode %s affinity %s effective %s\n' "$irq" "$(cat "$d/msi_irqs/$irq" 2>/dev/null)" \
      "$(cat "/proc/irq/$irq/smp_affinity_list" 2>/dev/null)" \
      "$(cat "/proc/irq/$irq/effective_affinity_list" 2>/dev/null)"
  done
done
echo "===== interrupts (before a read)"; cat /proc/interrupts
echo "===== a short NVMe read (5 s, then the interrupts again)"
nvme=$(ls /dev/nvme0n1 2>/dev/null)
if [ -n "$nvme" ]; then
  timeout 5 dd if="$nvme" of=/dev/null bs=1M iflag=direct status=none
  cat /proc/interrupts | grep -i -E 'CPU|nvme|msi|pcie'
else
  echo "no /dev/nvme0n1"
fi
