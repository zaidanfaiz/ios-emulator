# ios-emulator

Research environment for booting the **iOS 16.5 (20F66) user space** on **QEMU ARM64**
(`-M virt`, aarch64) running inside **WSL2 on Windows**.

This repository is an independent project. Its kernel patch, boot loader, userland and
QEMU glue started from the open-source [HakiOS](https://github.com/oosexgang/hakios-os)
research bench (see [Credits](#credits)); this tree carries no upstream git history and is
not a fork. Development, build configuration and the QEMU-first target are maintained here.

> Status is evidence-based, not aspirational. Anything not reproduced on this machine is
> listed as unverified in [Development status](#development-status).

---

## What this is, and what it is not

**Is**
- A reproducible build of the open-source XNU kernel (`xnu-8796.121.2`) with Apple's iOS 16.5
  user space on top: `launchd`, `backboardd`, `SpringBoard`, stock apps.
- A QEMU-only research target. Apple's system components are pulled from Apple's own CDN at
  build time; nothing of iOS is stored in this repository.
- A bench for kernel, driver, filesystem, graphics and input work with real serial logs.

**Is not**
- A jailbreak, an unlock, an activation bypass, or anything that talks to Apple services.
  There is no Secure Enclave, no signing, no Apple ID.
- A distribution of iOS. No Apple binary, image, font or screenshot is committed here.
- A phone ROM. Physical-device support (`devices/`) is inherited from upstream and is out of
  scope for this project's QEMU work.

---

## Requirements

| Component | Requirement |
|---|---|
| Host | Windows 10/11, 16 GB RAM minimum (build + QEMU do not fit under 12 GB comfortably) |
| WSL2 | Ubuntu 24.04+ (tested: 26.04 LTS), WSL 2.4+ (`wsl --version`) |
| Disk | ~25 GB free for the source images, the APFS images and one QEMU session |
| Guest RAM | 6 GB for the open-kernel smoke test (payload is mapped at `0xF0000000`) |
| Network | Downloads ~7.4 GB from `updates.cdn-apple.com` (range requests, no IPSW needed) |

Build dependencies inside WSL:

```sh
sudo apt install qemu-system-arm qemu-efi-aarch64 7zip lz4 clang lld \
                 build-essential python3 curl xz-utils
```

`7z` must be **7-Zip 23 or newer** — the APFS images in the iOS firmware cannot be read by
`p7zip`. Ubuntu's `7zip` package (26.00) provides it.

---

## Quick start

```sh
git clone https://github.com/zaidanfaiz/ios-emulator.git
cd ios-emulator

sysimage/fetch.sh            # iOS 16.5 (20F66) components from Apple's CDN
REST=1 userland/build.sh     # -> userland/root.apfs and userland/system.apfs

mkdir -p logs
qemu/run-ios.sh 1200 -display gtk > logs/qemu.log
```

First, and faster to validate the toolchain:

```sh
# Apple-free path: open kernel + placeholder loader + raw-syscall init, no IPSW involved
make qemu-open
```

UEFI firmware paths differ per distro. On Ubuntu/Debian:

```sh
export QEMU_EFI=/usr/share/AAVMF/AAVMF_CODE.fd
export QEMU_VARS=/usr/share/AAVMF/AAVMF_VARS.fd
```

---

## Architecture

```
                    qemu-system-aarch64 -M virt,gic-version=3
                                   |
        EDK2 (AAVMF_CODE.fd)  ->  XNULOADER (a UEFI application, loader.efi)
                                   |  parses the XNUP payload at 0xF0000000
                                   |  claims physical memory, builds the device tree
                                   v
                XNU (mach.development.bcm2837)  -- patched, open source
                                   |
                  BSD init  ->  md0 (APFS root, resident RAM disk)
                                   |
                       /sbin/launchd  ->  backboardd  ->  SpringBoard
```

- **Loader** (`xnuloader/`): EFI app, no EDK2 build needed. Reports `CurrentEL`, builds boot
  args, loads the kernel and RAM disk, jumps at EL1.
- **Kernel** (`xnu/hakios.patch` + `xnu/files/`): Apple's XNU with drivers for display, touch,
  UFS, GPU, audio, modem. Under QEMU only the virt platform drivers are used.
- **Userland** (`userland/`): small programs and libraries, an `rc` job set, and the APFS
  image builder (`tools/apfs/mkapfs.py`) that packs the chosen iOS files into `system.apfs`.
- **Images**: `system.apfs` is the root volume (2.5 GB), `root.apfs` holds init and jobs.

---

## Resource notes (measured)

Host used for these numbers: 16 GB RAM, 16 threads, WSL2 with `~/.wslconfig`:

```ini
[wsl2]
memory=10GB
processors=12
swap=4GB
```

| Measurement | Value |
|---|---|
| WSL idle after clean boot | ~700 MB used |
| QEMU open-kernel smoke test (6 GB guest) | boots to user space in <10 s of guest time |
| Full iOS boot (`QEMU_RAM_GB=7`) | ~2.5–3 GB **host** RSS per instance |
| WSL vhdx after cleanup | 8.5 GB file, 1.9 GB used inside |

`qemu/run-ios.sh` refuses to start when `/proc/meminfo` reports less than 3 GB available.
Guest RAM is configurable: `QEMU_RAM_GB=n qemu/run-ios.sh 600`.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| WSL fails to start, `WSL_E_CUSTOM_KERNEL_NOT_FOUND` | `~/.wslconfig` points at a missing custom kernel | Remove the `kernel=` line |
| `bash: $'\r': command not found`, `syntax error near unexpected token` | scripts checked out with CRLF on Windows | Clone with `core.autocrlf=false`; repo has LF blobs |
| `UEFI EXCEPTION ... far=f0000000` | guest RAM smaller than the payload address | `QEMU_MEM=6G` or more |
| `run-ios.sh: no UEFI firmware at ...` | firmware not where the script expects | set `QEMU_EFI` / `QEMU_VARS` |
| `fetch.sh: 7z is not installed` / APFS read errors | `p7zip` 16.x | install `7zip` ≥ 23 |
| QEMU killed by the OS | guest RAM + host overcommit | lower `QEMU_RAM_GB`, raise WSL `memory=` |

Logs land in `logs/`. `qemu/sym.py` and `qemu/symstack.py` turn kernel addresses into symbols
from the built kernel; `qemu/screendump.sh` saves a PNG of the guest display through the
monitor socket.

---

## Repository layout

| Path | Contents |
|---|---|
| `xnu/` | XNU patch + custom driver files, `apply.sh`, `export.sh` |
| `xnuloader/` | the UEFI boot loader |
| `userland/` | init programs, libraries, `rc.*` job sets, APFS image build |
| `sysimage/` | scripts that fetch and unpack the iOS 16.5 files (no Apple files kept) |
| `qemu/` | QEMU run scripts, touch injection, screendump, symbolization |
| `tools/` | APFS builder/checker, firmware and QMI utilities |
| `prebuilt/` | kernel, loader and libraries built from this tree |
| `devices/` | upstream's physical-device ports; unused by the QEMU target |
| `docs/` | detailed notes (upstream, mostly Russian) |

---

## Development status

Verified on this machine (logs under `logs/`, not committed):

| Step | Result | Evidence |
|---|---|---|
| Build environment in WSL2 (qemu 10.2.1, 7z 26.00, lld) | working | `qemu-system-aarch64 --version` |
| Open-kernel QEMU boot (no Apple software) | **boots to user space** | `logs/qemu-open.log`: `Hello from user space on Darwin!`, pid 1 on `md0`; panic `initproc failed to start` is expected — the test init exits 0 |
| iOS 16.5 (20F66) component fetch | in progress | `logs/fetch.log` |
| APFS image build (`REST=1 userland/build.sh`) | not yet run | — |
| Full graphical iOS boot (Lock Screen, SpringBoard) | **unverified** | — |

Do not read this table as a promise: an entry says "working" only when a log or screenshot on
this machine shows it.

---

## Credits

This project would not exist without [HakiOS](https://github.com/oosexgang/hakios-os) by
`@oodze` and the HakiOS contributors, who wrote the XNU patch, the loader, the driver set, the
APFS tooling and the QEMU bring-up that this tree started from. Their names and license
notices are kept in `NOTICE`, `LEGAL.md`, `COMPLIANCE.md` and `THIRD_PARTY_LICENSES.md`.

- XNU and the kernel patch: Apple Public Source License 2.0 — `LICENSE.APSL`
- Everything else: see `LICENSE` and the file headers
- `sysimage/` scripts read Apple's public firmware archives without decrypting or bypassing
  anything; the files themselves are never redistributed here

"IOS", "iPhone", "XNU" and "Apple" are used only to describe what the code works with. This
project is not affiliated with, sponsored by or endorsed by Apple Inc., Xiaomi or Qualcomm.
