# Status

The present only; rewritten when it changes.

## rpi_cm-radxa_taco

- **Images:** build b1 for Talos v1.14.6 (`cm4-taco13`, `cm5-taco13`; kernel 6.18.63,
  siderolabs/pkgs `e6ad19d`) is defined but not yet built or published. Both kernel
  patches are still needed in 6.18.63 and apply to it unchanged; both config fragment
  options are still present (unset) in Talos's `config-arm64`. Build b8 for v1.14.2 is
  superseded and will not be built.
- **Registry:** `ghcr.io/achillea-anderson/rpi_cm-radxa_taco/` (not yet populated).
- **Reproducibility:** not yet verified (two independent builds compared).
- **Next:** build b1; test it on a CM4 TACO; publish; verify reproducibility and list the
  digests in `images/rpi_cm-radxa_taco/building.md`; test a CM5 on a TACO v1.61 when one
  is available.
