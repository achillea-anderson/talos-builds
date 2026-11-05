# Tests and diagnostics

The load tests and dumps used to bring the TACO boards up under Talos. Each file's header
says what it does and how to run it. Talos has no shell, so most run as a privileged pod
on the node (`kubectl apply -f`), or as a machine-config patch.

| File | What |
|---|---|
| `disk-load.yaml` | Sustained disk load: every HDD written and verified with fio, the NVMe read at the same time. **Destroys the data on the HDDs it names** |
| `net-load.yaml` | An iperf3 server on the node, to run with `disk-load.yaml` |
| `bench-rpios.sh` | The same tests on Raspberry Pi OS, as a reference for the hardware's limits |
| `rps-enp4s0.yaml` | Machine-config patch: Receive Packet Steering on the 2.5 GbE (recommended on the CM4) |
| `napi-threaded-enp4s0.yaml` | Machine-config patch: threaded NAPI (did not help on Talos) |
| `pci-debug.yaml`, `pci-debug-rpios.sh` | The PCIe tree, windows and MSI state, on Talos and on Raspberry Pi OS, for comparison |
| `i2c-scan.yaml`, `pinctrl-debug.yaml` | I2C buses and GPIO pin functions, for the clock |

**Before running a destructive test**, change the disk names and the model check in it to
your own disks: they name ours (three ST4000LM024 HDDs as `sda`–`sdc`).
