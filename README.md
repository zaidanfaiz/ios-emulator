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

The home screen arrives after about half an hour on TCG here, not the "few minutes" upstream
measures on a phone: 1763 s of guest time at four cores, of which LaunchServices spends 25
minutes re-registering every application because `/private/var` is a fresh memory filesystem at
each boot (`userland/src/init.c` mounts it). Expect 6–9 frames a second once it is up. In the
window: mouse with the left button held is a finger, `H` is Home, `L` is the power button,
`↑`/`↓` are volume. `autounlock=0` in `CMDLINE` keeps the lock screen until it is swiped away;
without it the port dismisses it 10 s in and lands on the home screen
(`userland/src/inject_sb.c`).

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
| `QEMU_SMP` | `1` | guest cores; the kernel uses `cpus=N` of them (`CMDLINE="cpus=4"` below) |
| `VARSTORE` | unset | `1` (or a path) keeps `/private/var` between runs in a sparse 12 GB disk image (`qemu/var.img`); `qemu/var.img` holds slot 0 and slot 1 at 8 GiB and 10 GiB, two of the two-slot store `userland/src/var_store.c` writes |
| `CMDLINE` | unset | extra boot arguments, appended to `virtio_input=1` — see the table below |

Boot arguments worth knowing under QEMU:

| Argument | Meaning |
|---|---|
| `cpus=N` | cores the kernel runs on |
| `autounlock=0` | the Lock Screen stays until it is swiped up; without it SpringBoard dismisses it 10 s in |
| `fbscale=2` | 375×812 points drawn at 2 px a point instead of 3, then scaled up to the panel. Upstream notes a red bar at the top of SpringBoard as the price. Measured once here it is not the lever it looks like — the scale-up still writes all 2.74 Mpx: `logs/qemu-run7.log` reports `3 frames in 5497 ms, 54727 us each in the driver` where run 5 reports `8076 us each` at the default |
| `touch_lat=1` | print a `tl: i` line per touch sample: when the kernel posted it, when the injector read it, when it reached IOHID (all in microseconds) |
| `var_save_ms=N` | how long the kernel waits for the saver's answer on the way back to the loader (default 20 000) |
| `applog=1 applog_name=SpringBoard` | send SpringBoard's own log to the console |

A run's `VARSTORE` block also sets `virtio_blk=1 virtio_blk_rw=1 var_store=1
var_store_dev=/dev/rvblk0`: the store arrives as a writable virtio-blk device (`/dev/rvblk0`,
12 289 MB, logged `slot 28`), and `userland/src/var_store.c` reads and writes it through
`kern.hakios.var_save`.

`qemu/run.sh` is the open-kernel path (no Apple software): UEFI + loader + `hello` ramdisk.
It defaults to `QEMU_MEM=6G` — the payload is mapped at `0xF0000000`, so a 2 GB guest aborts
with `UEFI EXCEPTION ... far=f0000000`.

Helpers: `qemu/screendump.sh` (picture through the monitor), `qemu/touch.py` (touches through
QMP), `qemu/stop.sh` (clean shutdown — do not kill WSL).

Do not poll `qemu/screendump.sh` while a run is in flight: the monitor is serialised with the
guest, and a poller ended run 5 with a ticket spinlock timeout (`logs/qemu-long5.log`). Take the
picture once, at a known guest time, or drive input over QMP (`qemu/touch.py`), which does not
disturb the guest's own progress.

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
| `qemu/var.img` (with `VARSTORE=1`) | 12 GB sparse; 28 896 KB after a 1600 s run (blocks 57 792) — the store's payload is 16 MB, the rest is what the two-slot layout pads |

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
| Apple logo for 25 minutes | SpringBoard waits for LaunchServices, which registers every application afresh (`/private/var` is a new memory filesystem each boot) | not a hang: watch `lsd` in `python3 qemu/touch.py stacks top`, and the first `tl: a` line in the log when the run loop turns. `VARSTORE=1` gives the run a `/private/var` that outlives it — that is the only thing that removes the registration work, and the second run measures whether it does |
| `var_store: the saver did not answer in 45000 ms` at the end of a run | the kernel asks the saver for the volume on the way back to the loader and waits `var_save_ms` for the answer (`bsd/dev/hakios.ufs.c`, `hakios_var_save_on_return`); a whole volume takes longer than that | expected, and harmless: each slot is written in turn and the header goes last, so the newest complete slot is what the next boot loads. The periodic save (`com.hakios.varstore.plist`, every 300 s) is what actually carries the store. Raise `var_save_ms` on the guest command line to give the last save more room |
| `var_store: no store yet: /private/var stays as init made it` | nothing has been written to `qemu/var.img` yet — the first `VARSTORE=1` run writes it | not a failure. Watch for `var_store: saving into slot 0` and, on the host, `du qemu/var.img` leaving zero |
| SpringBoard goes quiet a couple of minutes in and never draws; `touch.py stacks SpringBoard` says `3 threads` and `top` still shows it using 20 % of a processor | not explained, and not the store: it happens with `VARSTORE` on (runs 7, 8) and off (run 9, guest ~740 s, right after `BKDeviceTouchID::deviceAvailableWithFailure`). In run 8 the stacks say where it waits (`CoreServices` under `libsystem_kernel`, `logs/qemu-run8.log`) — LaunchServices, as on every boot, only it never ends while `lsd` is still busy | see the boot-time table below: the run window is the first thing to rule out. Run 5, the one that reached the overlay (guest 1088.9 s), had a fast boot and 3600 s; run 9's boot was five times slower and its window 1500 s |
| Overlay comes off, but the screen is black and taps do nothing | the display's backlight is turned off: `backboardd [Backlight] Setting CoreBrightness backlight factor:0.000000` comes a few seconds after `checkInAndWaitForDataMigration` (run 15: 03:04:25, 7 s after it; run 14: 02:27:08), and while it is off backboardd says `[TouchEvents] … ignoring touch event ((backlight dim/off))` — run 14 logged 119 of those. A backlight factor back to 1 does not by itself put anything on the glass: run 14 had `factor:1.000000` at 02:30:26 and still handed over 0 swaps, two screendumps all black | touch the screen or press power, then look again. Run 15 went `factor:0` → `Main will unblank` → `factor:1.000000` → overlay → two black screendumps → one power press → one tap, and the Lock Screen was in the framebuffer 30 s later (`logs/run15-c.png`). Run 14 got the same backlight sequence and the same two taps 51 s and 91 s after the overlay and stayed black, so what actually makes SpringBoard draw its first frame is not established |

## Status

| Area | State |
|---|---|
| Open-kernel QEMU boot (loader → BSD → `md0` → pid 1) | **verified**, `logs/qemu-open.log` |
| iOS components fetch from Apple CDN (`sysimage/fetch.sh`) | **verified**, `FETCH_EXIT=0` — 2.9 GB rootfs, 26 MB OS cryptex, 11 MB App cryptex, 2.6 GB dyld shared cache |
| APFS images (`REST=1 userland/build.sh`) | **verified**, `system.apfs` 2.47 GB + `root.apfs` 4 MB, `BUILD_EXIT=0` |
| iOS boot to userland (`launchd`, `backboardd`, `SpringBoard`) | **verified**, `logs/qemu.log`: `SpringBoard [7] job state = running`, `backboardd[13] SystemShell connected ... com.apple.springboard`, `BootUI addOverlay` |
| Display (ramfb, loader-set 1125×2436) | **verified rendering** — BootUI overlay drawn white-on-black, `logs/screen-02.png` |
| Lock Screen | **verified with a picture, read back pixel by pixel** — run 15: `BootUI removeOverlayWithAnimationSettings: Removing the overlay` at 03:09:04 (1352 s after QEMU started, `logs/qemu-run15.log`), then a touch, and 30 s later `logs/run15-c.png` — 1125×2436, **88 583 lit pixels** — reads `Wednesday, October 28`, the clock `3:10`, the battery, the cellular indicator, the camera button and the home bar. `autounlock=0` keeps it there (`hakios: the lock screen stays until it is swiped away`); a swipe from the bottom turns it into a transition with the camera button and the home bar and no clock (`logs/run15-d.png`, 23 878 lit pixels) |
| `/private/var` kept between runs (`VARSTORE=1`) | **writes and restores; not shown to save the wait, so not enabled by default** — the save path is proven (`logs/qemu-storeprobe.log`: `slot 0: generation 1, 209 entries, 19344 bytes`, `5 blocks into the flash`, `qemu/var.img` from zero blocks to 64) and the restore is too (`logs/qemu-run7.log`: `slot 0: generation 5 … 6717 entries, 16332312 bytes`, then `2944 directories, 628 files (15347820 bytes)`; `logs/qemu-run8.log`: generation 9, `3091 directories, 654 files (18232867 bytes)`). No run that restored it has reached `checkInAndWaitForDataMigration`, let alone the overlay: runs 7 and 8 were cut at 1600 and 1400 s, and run 12 (generation 9, 7037 entries, 19 MB) never got a full window either — `backboardd` was up 203 s after QEMU started, and QEMU itself exited at ~440 s with nothing printed, so run 12 says nothing about the store in either direction. Run 5 needed 831 s for that call on a 121 s boot. Run 8's two stack samples at 704 s and 1124 s are the same stack (`libsystem_kernel` → `CoreServices` → `ControlCenterServices` → `BaseBoard` → `libdispatch` on one thread, `libxpc` → `Foundation` → `CoreServices` on another, `ustacks` reporting `3 threads`). Run 8's periodic save also never finished: `saving into slot 1` and nothing after, `qemu/var.img` untouched since run 7. The ask on the way out goes unanswered (`the saver did not answer in 45000 ms`) |
| Home Screen (widgets, icon grid, dock) | **verified**, `logs/l2-1800.ppm`: SpringBoard's own page, 6–9 fps (`MiniIOMobileFramebuffer: 46 frames in 5003 ms`), `BootUI removeOverlayWithAnimationSettings: Removing the overlay` at guest 1707 s |
| Boot to a drawn screen, QEMU / TCG, 4 vCPU (this host) | **measured, twice** — run 5: overlay at guest 1088.9 s (`tl: a 1088898620`), screen already drawn (`logs/l5-ui-now.ppm`); run 15: `backboardd` at 84 s, `checkInAndWaitForDataMigration` at 1066 s, overlay at 1352 s, and the Lock Screen on the glass at 1442 s = **24 m 02 s** after QEMU started, once a touch had woken it (`logs/run15-c.png`). Run 3 (older settings): 1763 s; run 6c (store holding 8 files): 1430 s. Runs 7, 8, 9, 10, 12, 13 and 14 did not get a drawn screen, with the store and without it; run 13 came closest without it (the migration at 1116 s, QEMU gone 177 s later) and run 14 reached the overlay at 1136 s but never drew (0 swaps, two black screendumps). What makes one boot draw and the next not is still open, and the two tables below say why a short window cannot answer it |
| Drawing cost, software renderer | **measured**, `logs/qemu-long5.log`: `MiniIOMobileFramebuffer: 37 frames in 5312 ms (6 a second), 8076 us each in the driver` at 1125×2436 — 2.74 Mpx a frame through TCG, no GPU. `fbscale=2` measured worse, not better (`54727 us each`, `logs/qemu-run7.log`), because the picture is still scaled up to the panel |
| Input (touch, Home, power, volume) | partly tested — `virtio-tablet` events reach the iOS input stack (`hakios: input: sample type 1 finger 0 …`), a swipe changes the screen (`logs/l2-unlock.ppm` vs `logs/l2-unswiped.ppm`, `logs/l5-after-swipe.ppm` vs `logs/l5-before-swipe.ppm`, and run 15's `logs/run15-d.png` after `touch.py swipe 0.5 0.98 0.5 0.4 250`), and a tap in run 15 brought the Lock Screen up (`logs/run15-c.png`). Timing: `tl: p` stamps each sample in the kernel, `tl: i` the window server's read of it and its handover to IOHID. Under load (run 5, drawing): 217 paired samples, kernel post → read median **76.50 s** (p75 188.02, none under a second), read → IOHID median 21.16 ms, median 67 newer samples already queued. Idle (run 15, 19 paired samples): median **1.68 s** (p75 15.84, max 135.66), handover median 101.53 ms, median 6 queued — the wait tracks what else the guest is doing, not the driver. `python3 tools/latency.py logs/qemu-long5.log` and `… logs/qemu-run15.log`. No gesture verified end to end |
| Audio, network | untested here |
| Kernel rebuild from source in WSL2 | **verified** — `xnu/apply.sh` then `./xnu-build.sh -j8 -k` produced `mach.development.bcm2837` (15 274 128 B) with the virtio-blk and `var_store` changes in it; an incremental rebuild is about two minutes. Function-level symbolication of user space is still out of reach (see the notes below) |

### How long a boot takes here, and why a short run proves nothing

The same image (`userland/system.apfs` 19:35, kernel 19:32, 15 274 128 B) and the same boot
arguments in every run below. Seconds are from the QEMU start epoch in the log's `cmdline` line to
the first `startup complete` out of `backboardd`; the migration column is
`checkInAndWaitForDataMigration`, which runs 5, 6c, 13, 14 and 15 reached.

| Run | `/private/var` at boot | `backboardd` ready | `checkInAndWaitForDataMigration` | Overlay |
|---|---|---|---|---|
| 5 | as init made it | **121 s** | 831 s | guest 1088.9 s |
| 6c | 8 files restored | 237 s | 1262 s | guest 1430 s |
| 7 | 6717 entries, 16 MB | 179 s | — | no |
| 8 | 7037 entries, 19 MB | 383 s | — | no |
| 9 | as init made it | **620 s** | — | no |
| 10 | as init made it | 265 s | — | no |
| 12 | 7037 entries, 19 MB | 203 s | — | no |
| 13 | as init made it | 223 s | 1109 s | no; QEMU gone at 1293 s |
| 14 | as init made it | 164 s | 913 s | guest 1136 s, screen black, 0 swaps |
| 15 | as init made it | **84 s** | 1066 s | guest 1352 s, **drawn at 1442 s** |

Seven times between the fastest and the slowest boot of one unchanged image — 84 s for run 15,
620 s for run 9 — is the first thing to rule out before blaming code or the store. Runs 9 and 10 were
cut at 1500 s while run 9's guest was minutes behind run 5's at the same wall time. Whether the
variance is host load, QEMU's own thread scheduling or TCG's translation cache has not been
separated — a wall-clock run start is not a guest-time zero.

A longer window does not buy a longer life either. The time is the last stamped guest line against
the QEMU start epoch; `end` is how the process actually finished.

| Run | Window | Last stamped line | End |
|---|---|---|---|
| 5 | 3600 s | 1577 s | panic — `Ticket spinlock[0xfffffff007afc880] timeout after 85097799 ticks`, then the loader's `== KERNEL LOG ==` |
| 6c | 1600 s | 1425 s | killed by the host timeout |
| 7 | 1600 s | 181 s | killed by the host timeout; the guest had stopped logging long before |
| 8 | 1400 s | 955 s | killed by the host timeout |
| 9 | 1500 s | 1297 s | killed by the host timeout |
| 10 | 1500 s | 1319 s | the kernel returned to the loader at `loader_return_after=1500` |
| 12 | 2400 s | 435 s | QEMU exit 0 with nothing printed |
| 13 | 2400 s | 1293 s | QEMU exit 0 with nothing printed |
| 14 | 1800 s | 1754 s | killed by the host timeout; the guest was still running (its clock read 815 s) |
| 15 | 1800 s | 1621 s | killed by the host timeout |

Run 5's 3600 s window is beside the point: it panicked 8 minutes after the Lock Screen appeared. The
two 2400 s runs were gone at 440 s and 1293 s. Run 13 came the closest without drawing the UI —
`checkInAndWaitForDataMigration` at 1109 s, where run 5 reached the overlay 258 s after that call —
and then QEMU exited without a dump. A panic prints `== KERNEL LOG ==`, as run 5's did, so run 13's
exit is not one; it is what a guest reset looks like under `qemu/run.sh`'s `-no-reboot`. The panic
run 5 ended with is not the screendump poller's doing either: run 13 never touched the monitor. Run
15, the boot that finally put the Lock Screen on the glass, was ended by its own 1800 s window with
the guest still working — the first time the window was what stopped a run rather than a panic or a
reset.

Notes on the boot above: no panic, guest RAM 7 GB, four cores. Kernel and userland logs repeat
(the console replays a block of lines a few thousand lines later), so count distinct events, not
lines. Where the time goes: `backboardd` puts the Apple logo up at guest ~200 s, SpringBoard's
main thread then waits in LaunchServices (`CoreServices` bundle loading, `pthread_cond_wait`)
while the `lsd` worker thread holds the lock and asks it over synchronous XPC; `lsd` finishes,
the overlay comes off, and the run loop turns — guest 1088.9 s in run 5, 1707 s in run 3. Stacks
at any time: `python3 qemu/touch.py stacks SpringBoard`, then name the addresses with `python3
qemu/dscimg.py sysimage/20F66__iPhone10,3_6/dyld_shared_cache_arm64 ADDR…` — it names the
dylib, as run 8's stack shows (`CoreServices`, `ControlCenterServices`, `libxpc`, `Foundation`),
but not the function: `ipsw dyld a2s` would need a `<cache>.symbols` file that 20F66's cryptex
keeps decmpfs-compressed. Addresses in a stack are runtime ones; subtract the slide the kernel
prints next to `ustacks` before handing them to `dscimg.py`.

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
