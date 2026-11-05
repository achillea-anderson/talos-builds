#!/bin/sh
# The Talos load tests (disk-load.yaml, net-load.yaml), for a TACO running Raspberry Pi OS
# instead, so both systems run the same benchmark on the same board. Raspberry Pi OS on
# its own kernel is the reference: what the hardware does under the vendor's system
#. Runs as root on the board, one step per call. Copy it there
# once, then run each step with a terminal (-t), so sudo can ask for the password:
#
#   command scp tests/bench-rpios.sh <user>@<board>:
#   command ssh -t <user>@<board> 'sudo sh bench-rpios.sh <step>'
#
# (Piping it in with `sudo sh -s` works only where sudo needs no password: the script
# takes stdin, so sudo has no terminal to ask on.)
#
# Steps:
#   setup     install fio and iperf3, start the iperf3 server (port 5201, all addresses)
#   info      kernel, the RTL8125's interface, link speed, RPS and threaded NAPI state
#   tune      RPS onto CPUs 1 to 3 and threaded NAPI on the RTL8125 (as rps-enp4s0.yaml
#             and napi-threaded-enp4s0.yaml do on Talos); lost at reboot
#   untune    both back to the kernel's defaults (rps_cpus 0, threaded 0)
#   disks     start the fio job in the background (about 45 minutes), log in
#             /var/tmp/fio.log. DESTROYS THE DATA ON sda, sdb AND sdc (refuses unless
#             all three are ST4000LM024 HDDs); the NVMe is only read.
#   disks-log print the fio log (complete when it ends with "Disk stats")
#   hdd-write 3 minutes of only the HDD writes (same options, no verify), in the
#             foreground; DESTROYS THE DATA ON sda, sdb AND sdc like disks
#   nvme-read 3 minutes of only the NVMe reads, in the foreground
#             These two split the PCIe link's directions (receive
#             collapses under disk load with idle cores): run iperf3 receive-only from
#             the peer during each. HDD writes load host-to-device, NVMe reads
#             device-to-host.
#   stat      one /proc/stat sample (cpu lines) and the interrupt counts; take two, 30 s
#             apart, and compare
#
# The fio options must stay identical to disk-load.yaml's, or the numbers do not compare.
set -eu

# The RTL8125 is the interface whose driver is r8169 (Raspberry Pi OS names it eth1 or
# similar; Talos calls it enp4s0).
nic() {
  for n in /sys/class/net/*; do
    [ "$(basename "$(readlink -f "$n/device/driver" 2>/dev/null)")" = r8169 ] && { basename "$n"; return; }
  done
  echo "no r8169 interface found" >&2
  exit 1
}

# Writing destroys the disks' data: only the three test HDDs, never anything else.
hdds_or_stop() {
  for d in sda sdb sdc; do
    grep -q ST4000LM024 "/sys/block/$d/device/model" || { echo "$d is not an ST4000LM024: not writing" >&2; exit 1; }
  done
}

case "${1:-}" in
setup)
  apt-get update
  apt-get install -y fio iperf3
  pgrep -x iperf3 >/dev/null || iperf3 -s -D
  echo "iperf3 server running"
  ;;
info)
  n=$(nic)
  uname -a
  echo "interface $n, speed $(cat "/sys/class/net/$n/speed") Mbit/s"
  ip -br addr show "$n"
  echo "rps_cpus $(cat "/sys/class/net/$n/queues/rx-0/rps_cpus"), threaded $(cat "/sys/class/net/$n/threaded")"
  echo "rx_missed_errors $(cat "/sys/class/net/$n/statistics/rx_missed_errors")"
  # Interrupt moderation and NAPI deferral: how often the NIC interrupts and how long
  # the kernel keeps polling instead (compare with Talos's values).
  echo "gro_flush_timeout $(cat "/sys/class/net/$n/gro_flush_timeout"), napi_defer_hard_irqs $(cat "/sys/class/net/$n/napi_defer_hard_irqs")"
  sysctl net.core.busy_poll net.core.busy_read net.core.netdev_budget net.core.netdev_budget_usecs
  # ethtool fails on drivers without coalescing settings (r8169 on the RTL8125 under
  # Raspberry Pi OS: "Operation not supported"); under set -e that would end the step.
  command -v ethtool >/dev/null && { ethtool -c "$n" || true; }
  # The hardening Talos turns on at boot (Raspberry Pi OS gets the
  # same where it can): the kernel arguments, and whether kernel page-table isolation
  # (KPTI) and address randomisation (KASLR) are active, which cost every system call.
  echo "cmdline: $(cat /proc/cmdline)"
  grep . /sys/devices/system/cpu/vulnerabilities/meltdown /sys/devices/system/cpu/vulnerabilities/spectre_v2 2>/dev/null || true
  dmesg | grep -i -E 'kpti|kernel page table isolation|kaslr' || echo "dmesg: no KPTI/KASLR lines"
  modprobe configs 2>/dev/null || true
  zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_(IRQ_TIME_ACCOUNTING|HZ|PREEMPT|NO_HZ_IDLE|NO_HZ_FULL)=' ||
    grep -E 'CONFIG_(IRQ_TIME_ACCOUNTING|HZ|PREEMPT|NO_HZ_IDLE|NO_HZ_FULL)=' "/boot/config-$(uname -r)" || echo "kernel config not found"
  ;;
tune)
  n=$(nic)
  echo e >"/sys/class/net/$n/queues/rx-0/rps_cpus"
  echo 1 >"/sys/class/net/$n/threaded"
  echo "rps_cpus $(cat "/sys/class/net/$n/queues/rx-0/rps_cpus"), threaded $(cat "/sys/class/net/$n/threaded")"
  ;;
untune)
  n=$(nic)
  echo 0 >"/sys/class/net/$n/queues/rx-0/rps_cpus"
  echo 0 >"/sys/class/net/$n/threaded"
  echo "rps_cpus $(cat "/sys/class/net/$n/queues/rx-0/rps_cpus"), threaded $(cat "/sys/class/net/$n/threaded")"
  ;;
hdd-write)
  hdds_or_stop
  fio --direct=1 --ioengine=libaio --iodepth=16 --bs=1M --group_reporting=0 \
    --time_based --runtime=180 \
    --name=sda --filename=/dev/sda --rw=write \
    --name=sdb --filename=/dev/sdb --rw=write \
    --name=sdc --filename=/dev/sdc --rw=write
  ;;
nvme-read)
  fio --direct=1 --ioengine=libaio --iodepth=16 --bs=1M --group_reporting=0 \
    --time_based --runtime=180 \
    --name=nvme --filename=/dev/nvme0n1 --rw=read
  ;;
disks)
  hdds_or_stop
  pgrep -x fio >/dev/null && { echo "fio is already running" >&2; exit 1; }
  # Global options first; each --name starts a job with its own options. HDDs: write
  # 100 GiB with a checksum per block, then read back and check (stops at the first bad
  # block). NVMe: reads only, 4 x 100 GiB, to load the shared link.
  # setsid: its own session, so closing the ssh terminal (-t) cannot hang it up.
  setsid nohup fio --direct=1 --ioengine=libaio --iodepth=16 --bs=1M --group_reporting=0 \
    --name=sda --filename=/dev/sda --rw=write --size=100G --verify=crc32c --verify_fatal=1 \
    --name=sdb --filename=/dev/sdb --rw=write --size=100G --verify=crc32c --verify_fatal=1 \
    --name=sdc --filename=/dev/sdc --rw=write --size=100G --verify=crc32c --verify_fatal=1 \
    --name=nvme --filename=/dev/nvme0n1 --rw=read --size=100G --loops=4 \
    >/var/tmp/fio.log 2>&1 &
  echo "fio started, log /var/tmp/fio.log"
  ;;
disks-log)
  cat /var/tmp/fio.log
  ;;
stat)
  date
  grep -E '^cpu[0-3]? ' /proc/stat
  grep -E 'CPU0|nvme|eth|enp|ahci|IPI1' /proc/interrupts
  ;;
*)
  echo "usage: sh -s -- setup|info|tune|untune|disks|disks-log|hdd-write|nvme-read|stat" >&2
  exit 2
  ;;
esac
