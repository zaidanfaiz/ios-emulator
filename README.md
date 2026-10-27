# ios-emulator

Run the **iOS 16.5 (20F66) user space** — launchd, backboardd, SpringBoard, the stock apps —
on an open-source XNU kernel inside **QEMU ARM64**, from Windows through WSL2.

This is a research bench, not a product and not a jailbreak. Nothing is flashed, nothing is
installed on a phone, nothing talks to Apple's services. The whole system lives in RAM for the
length of one QEMU session.

| | |
|---|---|
| **Target** | QEMU `-M virt`, aarch64, TCG (no KVM, no GPU passthrough) |
| **Host** | Windows 10/11 + WSL2 (Ubuntu), or any Linux x86-64 |
| **iOS line** | 16.5, build 20F66, iPhone10,3 (`D22AP`) — the only version this tree supports |
| **Kernel** | xnu-8796.121.2 (APSL 2.0) with the project patch |
| **Status** | kernel + loader boot verified in QEMU; full iOS graphical boot under test — see [Status](#status) |

## What this repository is

`ios-emulator` is an independent fork of [HakiOS](https://github.com/oosexgang/hackios-os)
(see [Credits](#credits)). Upstream targets Qualcomm Android phones first and QEMU second;
this fork keeps only the QEMU path and drops the phone path from active development.

The system stack, bottom-up:

```
QEMU virt (aarch64)                          edk2/AAVMF firmware
  └── xnuloader/loader.efi      UEFI application — claims RAM, parses the payload,
      │                          builds the device tree + boot_args, jumps to the kernel
      └── payload.bin (XNUP)    kernel + ramdisk + cmdline, mapped at 0xF0000000
          ├── mach.development.bcm2837   patched XNU, DEVELOPMENT_ARM64_BCM2837
          ├── hello                      raw-syscall test binary (open path only)
          └── system.apfs                via qemu/ram.img at the resident address → /dev/md0
              └── launchd → backboardd → SpringBoard → apps
```

`root.apfs` (small, our init and launchd jobs) travels inside the payload as `/dev/md1`;
`system.apfs` (2.5 GB, the selected iOS root filesystem) is preloaded through a sparse,
reflinked `qemu/ram.img`.

## Requirements

Host: **16 GB RAM recommended** (guest uses 6–7 GB), ~25 GB free disk, 8+ cores.

WSL2 / Linux packages:

```sh
sudo apt install qemu-system-arm qemu-efi-aarch64 7zip lz4 clang lld \
                 python3 build-essential bison flex autoconf automake libtool \
                 libfuse3-dev pkg-config libssl-dev uuid-dev
```

`sysimage/fetch.sh` needs **7-Zip 23 or newer** (it reads APFS). Ubuntu's `7zip` 26.x is fine;
`p7zip-full` 16.x is **not**.

Building the kernel from source additionally needs [theos](https://theos.dev) with its Linux
toolchain and `iPhoneOS16.5.sdk`; `make qemu-open` and the prebuilt images work without it.

## Quick start (WSL2)

```sh
git clone https://github.com/zaidanfaiz/ios-emulator.git
cd ios-emulator

# 1. iOS 16.5 (20F66) components, straight from Apple's CDN — no manual IPSW download.
#    Fetches only the members needed (4.7 GB + 2.7 GB), ~7.4 GB on disk.
sysimage/fetch.sh

# 2. APFS images: userland/root.apfs and userland/system.apfs
REST=1 userland/build.sh

# 3. Boot it
mkdir -p logs
qemu/run-ios.sh 1200 -display gtk > logs/qemu.log 2>&1
```

The lock screen appears after a few minutes on TCG (upstream's measurement; not yet reproduced
on this machine — see [Development status](#development-status)). In the window: mouse with the
left button held is a finger, `H` is Home, `L` is the power button, `↑`/`↓` are volume.

### Where to build

Build inside the WSL filesystem (`~/ios-emulator`), not on `/mnt/c` or `/mnt/d`. The iOS root
filesystem is 43,230 small files: on ext4 the extraction takes a minute, over the 9p mount it
takes hours, and `rm -rf` on a deep 9p tree fails with `Directory not empty`, which makes the
next `7z` abort with `File exists`. Keep the git clone wherever you like; keep the artifacts on
ext4.


Nothing of Apple's is in this repository. `fetch.sh` pulls the disk images out of the public
IPSW on Apple's CDN with HTTP range requests; no decryption, no circumvention.

## QEMU usage

`qemu/run-ios.sh [seconds] [extra qemu args]` — the real boot. Environment:

| Variable | Default | Meaning |
|---|---|---|
| `QEMU_RAM_GB` | `7` | guest RAM; the kernel gets the phone's 4.2 GB window |
| `QEMU_EFI` / `QEMU_VARS` | `/usr/share/edk2/aarch64/QEMU_EFI.fd` | aarch64 UEFI firmware; on Ubuntu use `/usr/share/AAVMF/AAVMF_CODE.fd` and `AAVMF_VARS.fd` |
| `QEMU_NET` | unset | `1` adds a virtio NIC behind QEMU's user network |
| `AUDIO` | unset | back end (`pa`, `pipewire`, `sdl`, `alsa`) or `FILE.wav` |
| `QEMU_INSTANCE` | `0` | index for parallel instances (monitor `4444+10n`, QMP `4445+10n`) |

`qemu/run.sh` is the open-kernel path (no Apple software): UEFI + loader + `hello` ramdisk.
It defaults to `QEMU_MEM=6G` — the payload is mapped at `0xF0000000`, so a 2 GB guest aborts
with `UEFI EXCEPTION ... far=f0000000`.

Helpers: `qemu/screendump.sh` (picture through the monitor), `qemu/touch.py` (touches through
QMP), `qemu/stop.sh` (clean shutdown — do not kill WSL).

## Building from source

```sh
xnu/apply.sh             # XNU sources from Apple's GitHub + the patch -> xnu-src/
xnu-deps/setup.sh        # dependencies, crosstools, SDK
./xnu-build.sh -j8 -k    # -> xnu-src/.../BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837

xnuloader/build.sh       # the loader (clang + lld-link, no EDK2 needed)
REST=1 userland/build.sh # the APFS images
xnuloader/mkpayload.py -o qemu/payload.bin \
    kernel=prebuilt/mach.development.bcm2837 ramdisk=userland/hello --cmdline "cpus=1"
```

`make qemu-open` runs the Apple-free smoke test: kernel + placeholder loader + a static
raw-syscall binary. Reaching `Hello from user space on Darwin!` means the loader, the MMU, BSD
init, the RAM disk and the syscall path all work.

## Layout

| Path | Contents |
|---|---|
| `xnu/` | kernel patch (`hakios.patch`, APSL 2.0), driver files, `apply.sh` |
| `xnuloader/` | the UEFI boot loader, `mkpayload.py`, `mkidentity.sh` |
| `userland/` | our programs, launchd jobs (`rc.jobs.*`), `build.sh` (APFS images) |
| `sysimage/` | scripts that fetch and lay out the iOS files from the IPSW |
| `qemu/` | run scripts, monitor/QMP helpers, `payload.bin` |
| `tools/` | APFS tooling, firmware helpers, test utilities |
| `prebuilt/` | kernel and loader built from this tree |
| `devices/` | upstream phone ports — **not used here**, kept for attribution |
| `docs/` | upstream notes (Russian), cellular, GPU |

## Resource use

Measured on the reference host (16 GB RAM, 16 threads, Windows 11 + WSL2):

| Thing | Value |
|---|---|
| WSL2 ceiling | `memory=10GB`, `processors=12`, `swap=4GB` (in `%USERPROFILE%\.wslconfig`) |
| Guest RAM, real boot | 6–7 GB (`QEMU_RAM_GB`) |
| QEMU host RSS, real boot | ~2.5–3 GB per instance |
| QEMU TCG code cache | `tb-size=384` MB by default; QEMU's 1 GB default only costs host memory |
| `qemu/ram.img` | 12 GB sparse, reflinked — not read into host RAM |

WSL2 does not return freed page cache to Windows on its own; a stale 8 GB ceiling on a 16 GB
host is the usual cause of "WSL eats my RAM". Cap it explicitly and keep `vmIdleTimeout` in
mind if you start several instances.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `WSL_E_CUSTOM_KERNEL_NOT_FOUND` | `.wslconfig` points at a kernel that no longer exists | remove the `kernel=` line |
| `run.sh: syntax error near unexpected token` / `$'\r'` | CRLF checkout of `*.sh` | `git config core.autocrlf false` and re-checkout |
| `UEFI EXCEPTION ... far=f0000000` | guest RAM below 4 GB | `QEMU_MEM=6G` |
| `run-ios.sh: ... file is missing` | images not built | `REST=1 userland/build.sh` |
| `7z: Unsupported Method` on cryptex | LZBITMAP members | expected; `unzbm` finishes them, `fetch.sh` verifies |
| `netboot`/`initproc failed to start` on the open path | `hello` exits 0 by design | not a failure — user space was reached |
| SpringBoard never appears | no framebuffer | do not use `-display none` for the GUI boot; the loader needs a display |

## Status

| Area | State |
|---|---|
| Open-kernel QEMU boot (loader → BSD → `md0` → pid 1) | **verified**, `logs/qemu-open.log` |
| iOS components fetch from Apple CDN (`sysimage/fetch.sh`) | **verified**, `FETCH_EXIT=0` — 2.9 GB rootfs, 26 MB OS cryptex, 11 MB App cryptex, 2.6 GB dyld shared cache |
| APFS images (`REST=1 userland/build.sh`) | **verified**, `system.apfs` 2.47 GB + `root.apfs` 4 MB, `BUILD_EXIT=0` |
| iOS boot to userland (`launchd`, `backboardd`, `SpringBoard`) | **verified**, `logs/qemu.log`: `SpringBoard [7] job state = running`, `backboardd[13] SystemShell connected ... com.apple.springboard`, `BootUI addOverlay` |
| Display (ramfb, loader-set 1125×2436) | **verified rendering** — BootUI overlay drawn white-on-black, `logs/screen-02.png` |
| Lock Screen reached / Home Screen | **not yet shown** — BootUI overlay was on screen when the session ended; needs a longer run and input |
| Input (touch, Home, power, volume) | untested here — `qemu/touch.py`, `virtio-tablet` are wired but unexercised |
| Audio, network | untested here |
| Kernel rebuild from source in WSL2 | not yet run here (prebuilt kernel used so far; needs theos + `iPhoneOS16.5.sdk`) |

Notes on the boot above: a 300 s session on TCG, guest RAM 7 GB, ended by `timeout` (`qemu:
terminating on signal 15`), no panic. Kernel and userland logs repeat (the console replays a
block of lines a few thousand lines later), so count distinct events, not lines.

Anything not in the table above has not been tested on this machine. An Apple logo is not a boot.

## Limitations

- TCG only. No KVM on ARM guests under x86-64 WSL2, so expect minutes, not seconds, to the lock screen.
- No Metal, no Secure Enclave, no Apple ID, no activation — by design.
- Only iOS 16.5 / 20F66. Other versions have different kernel, loader and userland expectations.
- Physical devices are out of scope for this fork (`devices/` is upstream material, unmaintained here).

## Contributing

Read `AGENTS.md` for the operating rules (evidence over claims, LF line endings, incremental
builds, bounded logs). Upstream's `CONTRIBUTING.md` still applies to shared code.

## Credits and licenses

- Upstream: **HakiOS** — <https://github.com/oosexgang/hackios-os> (kernel patch, loader,
  userland jobs, APFS tooling, QEMU scripts). This fork keeps its code and attribution intact;
  see `NOTICE`, `LEGAL.md`, `COMPLIANCE.md`, `THIRD_PARTY_LICENSES.md`.
- XNU: Apple, Apache Public Source License 2.0 (`LICENSE.APSL`), changes published as source.
- `ios-emulator` fork packaging and documentation: see `LICENSE`.

No file of iOS is distributed here. iOS, iPhone, XNU and Apple are named only to describe what
the code works with; this project is not affiliated with or endorsed by Apple.
