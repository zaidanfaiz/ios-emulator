# UEFI for POCO F7 Ultra: not here yet

This directory is empty because the UEFI firmware for this phone **does not exist yet**. Nothing
in it would be honest to fabricate: the X5 Pro's `SILICIUM_UEFI.fd` is built for SM7325 and
will not boot an SM8750.

## What the X5 Pro has, and what a port must produce

`../../poco-x5-pro/uefi/` holds a [Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium)
port: a patch (`mu-silicium.patch`), the prebuilt `Binaries/redwood/` drivers, `apply.sh`
(clones the project at a pinned commit and applies the patch) and `export.sh` (saves the build
back out). `prebuilt/` next to it carries the finished `SILICIUM_UEFI.fd`, `BootShim.bin` and
the phone's `device-tree.dtb`; `mkbootimg.py` packs them for the vendor boot partition.

The chain that must exist before anything else in this port can be tested:

```
BootShim.bin  ->  SILICIUM_UEFI.fd  ->  XNULOADER (loader.efi)
                      |                      |
              SM8750 platform init      kernel + RAM disk
```

## What an SM8750 port needs from the phone

`../probe.sh` writes these to `../device-info.txt`:

| Need | Where it comes from |
|---|---|
| Device tree (`/sys/firmware/fdt`, or the `dtbo`/`dtb` partition) | `../pull-soc.sh` keeps a copy as `../device-tree.dtb` |
| Memory map and carveouts | `reserved-memory` nodes |
| UART / debug console base | DT `qcom,geni-debug-uart`, or the phone's Android `console=` cmdline |
| GIC / timer / PSCI values | DT `interrupt-controller`, `psci` |
| UFS controller registers | DT `ufshc` node |
| Display panel and DSI PHY | DT `dsi` / panel nodes |
| Firmware names (`a8xx_*`, `adsp`, `wpss`) | `/vendor/firmware`, `/vendor/firmware_mnt/image` |

## Steps

1. Confirm upstream Mu-Silicium has SM8750 support (board `sun`/`pineapple` family). If it does
   not, the port waits: writing a new SoC port from scratch is the actual project, not a step.
2. Clone Mu-Silicium at the commit that supports the closest board, copy
   `Platforms/<board>` into a local override, and add the DT from `../device-tree.dtb`.
3. Build, then `fastboot boot` **only** the shim — nothing flashed. Expect no display: the first
   milestone is UART output, not a screen.
4. When UEFI reaches the boot menu, run XNULOADER (see the QEMU target in the main README) before
   touching the kernel drivers. A kernel without a working loader is not a test.
5. Only then work `xnu/files/bsd/dev/hakios.*.c` for this phone, one subsystem at a time, with
   `probe.sh` values.

Until step 1 is answered, this port is blocked at the firmware layer — and the QEMU target stays
the only testable configuration.
