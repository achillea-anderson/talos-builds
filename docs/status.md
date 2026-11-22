# Status

The present only; rewritten when it changes.

## rpi_cm-radxa_taco

- **Images:** build b1 for Talos v1.14.6 (`cm4-taco13`, `cm5-taco13`; kernel 6.18.63,
  siderolabs/pkgs `e6ad19d`) is built and pushed, with its digests in
  `images/rpi_cm-radxa_taco/building.md`. It is not yet published: the packages are still
  private. Both kernel patches are still needed in 6.18.63 and apply to it unchanged. Both
  config fragment options are still present, unset, in Talos's `config-arm64`. Build b8 for
  v1.14.2 is superseded and will not be built.
- **Registry:** `ghcr.io/achillea-anderson/rpi_cm-radxa_taco/`: kernel, installer-base,
  imager, `installer-cm4-taco13:v1.14.6-b1`, `installer-cm5-taco13:v1.14.6-b1` (private).
- **Reproducibility:** not yet verified by comparing two independent builds.
- **Next:**
  1. Test b1 on a CM4 TACO.
  2. Publish it.
  3. Verify reproducibility.
  4. Test a CM5 on a TACO v1.61 when one is available.
