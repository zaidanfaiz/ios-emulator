# Device: POCO F7 Ultra (SM8750)

Port target for a second phone. **Status: scaffold only — nothing has been booted on this
device.** This file says exactly what exists, what is missing, and the order to fill it in.

| What | Value | How to confirm |
|---|---|---|
| SoC | Qualcomm Snapdragon 8 Elite (SM8750), Adreno 830 | `adb shell getprop ro.soc.model` |
| Board platform | `sun` / `pineapple` family — **unconfirmed** | `probe.sh` writes it |
| Product codename | unknown here on purpose | `adb shell getprop ro.product.device` |
| Kernel base | Android GKI + vendor modules (device tree only, no source) | `probe.sh` |
| Screen | 1440×3200 class AMOLED | `adb shell wm size` |
| Comparison | POCO X5 Pro (`../poco-x5-pro/`) is SM7325 / Adreno 642L / IPA 4.11 | — |

The upstream port (`../poco-x5-pro/`) is the template: it proves the shape of the work, not
the values. Every number in `xnu/files/bsd/dev/hakios_*.c` belongs to the X5 Pro.

## What is here

| Path | Purpose |
|---|---|
| `probe.sh` | Read-only discovery over `adb`: SoC, codename, device tree, memory map, firmware inventory → `device-info.txt` |
| `pull-soc.sh` | `tools/soc-args.py` on this phone's own device tree → `soc.args` |
| `pull-firmware.sh` | Pull the firmware the device tree names, into `fw-*/` (never committed) |
| `uefi/README.md` | The missing piece: an SM8750 UEFI port |

Nothing here is invented: the scripts ask the phone. `soc.args` and `fw-*/` appear only after
you run them with a device attached.

## Order of work

```sh
# 1. facts off the device (phone in Android, adb authorised)
devices/poco-f7-ultra/probe.sh

# 2. the SoC boot-args from its own device tree
devices/poco-f7-ultra/pull-soc.sh

# 3. firmware the device tree names
devices/poco-f7-ultra/pull-firmware.sh

# 4. UEFI: see uefi/README.md — needs a Mu-Silicium port for SM8750 first
```

Read `device-info.txt` before writing any driver constant. If a value is not in that file and
not in the device tree, it is not known yet.

## What must be rewritten for this phone

| Area | X5 Pro (works) | Needed here | Source of truth |
|---|---|---|---|
| Display | `hakios.display.c` panel timings | new panel, DSI PHY on SM8750 | `probe.sh` → `/sys/class/drm`, DT `dsi` node |
| Touch | Goodix | new controller and I²C address | DT `touchscreen` node |
| Storage | UFS 3.1, `hakios.ufs.c` | UFS 4.x, different host controller registers | DT `ufshc` node + Android driver source |
| GPU | Adreno 642L | Adreno 830, new GMU/zap firmware names (`a8xx_*`) | `/vendor/firmware` listing from `probe.sh` |
| Wi-Fi | WCN6750 | new WCN part | DT `wlan` node |
| Audio DSP | `adsp.mdt` set | same file names, new memory carveouts | DT `reserved-memory` |
| Modem | MPSS + IPA 4.11 | IPA version differs on SM8750 → `hakios.ipa.c` SRAM layout is **not** reusable | `docs/cellular.md`, DT `qcom,ipa` |

The IPA argument is the real blocker for cellular: the X5 Pro driver carries an IPA-4.11 SRAM
layout as hardcoded data. A different IPA version is a driver port, not a configuration change.

## Root vs. unlocked bootloader

Two different things, and only one of them is enough to collect data.

| | Gives you | Enough to boot a UEFI port? |
|---|---|---|
| **Root** (`adb shell id -u` = 0) | `/dev/block/by-name/*`, full `/proc/iomem`, `dmesg`, `/vendor/firmware_mnt`, `/sys/firmware/fdt` | no, but it is what every value below needs |
| **Unlocked bootloader** (`ro.boot.flash.locked` = 0) | `fastboot boot <shim>` — running an image without flashing it | yes, this is the gate |

A rooted phone with a locked bootloader can still be dumped completely; it just cannot run the
result. Check with:

```sh
adb shell getprop ro.boot.flash.locked        # 0 = unlocked
adb shell getprop ro.boot.verifiedbootstate   # orange = unlocked
```

## Collecting what a UEFI port needs

```sh
devices/poco-f7-ultra/dump-partitions.sh      # root shell; read-only, streams blocks over adb
```

| Block | Why it matters |
|---|---|
| `abl` | Qualcomm's Android Bootloader — **already an EDK2/UEFI firmware image**. Its platform init and DXE drivers are the reference an SM8750 Mu-Silicium port is derived from. Reading it is reverse engineering, and the only honest source for this SoC's numbers. |
| `dtbo`, `dtbo*` | device tree overlays for this exact board |
| `boot` | Android kernel + ramdisk: cmdline, memory layout, `console=` |
| `vendor_boot` | vendor ramdisk: module and firmware paths |
| `iomem.txt`, `dmesg.txt` | the running kernel's own map and driver probes |

Output lands in `dumps/`, which is git-ignored: it is Qualcomm's and Xiaomi's code, not ours.

## Not in this directory, on purpose

- **No prebuilt UEFI images.** `../../devices/poco-x5-pro/prebuilt/SILICIUM_UEFI.fd` is built
  for SM7325. Booting it here is not a plan.
- **No `device-tree.dtb`.** Comes from the phone (`pull-soc.sh` keeps the parsed args;
  `probe.sh` records where the DT came from).
- **No firmware.** Vendor's; pulled per device, git-ignored.

## Dual boot with Android

The X5 Pro path is RAM-only: `fastboot boot` of the loader, system image into RAM, reboot
returns to Android. No partition is written. Keep that property here too — it is what makes a
dual boot safe to attempt. See `../../xl` and `../../tools/modem-cycle.sh`; this port has no
boot script yet because it has no working UEFI image.
