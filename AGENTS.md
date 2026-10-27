# AGENTS.md

Operating rules for any agent working in this repository.

## Project

`ios-emulator` boots the **iOS 16.5 (20F66)** user space on **QEMU ARM64** under **WSL2**.
Single deliverable: a boot that reaches Lock Screen, SpringBoard and stock apps, reproducibly,
from this tree.

**In scope:** QEMU (`-M virt`), the loader, the patched XNU, APFS image build, graphics, input,
userland jobs, resource use.

**Out of scope:** physical Android devices (`devices/` is upstream dead weight here),
Apple services/activation, iOS versions other than 16.5/20F66, GPU passthrough, Metal.

## Non-negotiables

1. **Evidence over claims.** "Boots" requires log lines or a screenshot from this machine.
   Compilation success, an Apple logo, or an upstream README claim proves nothing.
2. **Never commit Apple's files.** `system.apfs`, `root.apfs`, `rootfs.dmg`, `cryptex*`,
   `*.ipsw`, `xnuloader/identity.h`, `fw-*/`, `qemu/ram.img`, `logs/` stay untracked.
   `.gitignore` is a whitelist — check before adding.
3. **Fixes, not masks.** A panic is information. Do not silence a failing driver, skip a
   launchd job, or lower a timeout to make a log look clean. If a workaround is unavoidable,
   name it in the commit body and in `docs/`.
4. **Stay close to upstream.** Upstream is HakiOS (`NOTICE`, `LEGAL.md`). Prefer changes that
   could be sent upstream; keep the diff small and justified.
5. **Line endings are LF.** `.sh` files with CRLF fail in WSL. `git config core.autocrlf false`.

## Workflow

```sh
sysimage/fetch.sh                 # once; Apple CDN, ~7.4 GB
REST=1 userland/build.sh          # APFS images
make qemu-open                    # toolchain smoke test (no Apple software)
qemu/run-ios.sh 600 -display gtk  # real boot
```

- Build in the WSL filesystem (`~/ios-emulator`), never on `/mnt/d`: 43k small files over 9p
  take hours to extract and `rm -rf` there fails with `Directory not empty`. Git can live on
  either side; artifacts belong on ext4.
- Incremental only: `userland/build.sh` caches per-stage; do not wipe `sysimage/` between runs
  unless `select-system.py` changed (then `KEEP=1` keeps `rootfs.dmg`).
- Async work goes to `logs/<step>.log`; read the tail, never dump a whole boot log into chat.
  Full-boot logs are ~50k lines.
- Kill a QEMU run with `qemu/stop.sh` (monitor on port 4444), not by killing WSL.

## Testing requirements

Before claiming a step works:

| Step | Required proof |
|---|---|
| Build | exit status 0 **and** the artifact exists with a plausible size |
| Loader | `== XNULOADER v3 ==` with `CurrentEL=1` and the payload entries listed |
| Kernel | reaching `bsd_init: done` and mounting `md0` |
| Userland | `launchd` alive past pid 1 (not `initproc failed to start`) |
| UI | `logs/screen-*.png` via `qemu/screendump.sh` showing Lock Screen or SpringBoard |
| Resource change | before/after numbers from `/proc/meminfo`, `ps` RSS or `time` |

## Resource limits

- Host: 16 GB RAM / 16 threads. WSL capped at `memory=10GB`, `processors=12`, `swap=4GB`.
- Guest RAM: 6 GB minimum (payload mapped at `0xF0000000`), 7 GB for the iOS boot.
- Never run two QEMU instances with the same `QEMU_INSTANCE`.
- Keep `qemu/ram.img` sparse; it is reflinked, not read into RAM.

## Reporting

- Findings as tables: step | result | evidence. No adjectives.
- Failed steps stay in the table as failures with the reason.
- Log excerpts: ≤15 lines, the line that proves the point, plus its location.
- Commit message: area, what changed, why, evidence. Example:
  `loader: claim memory above 0xF0000000 — 2G guest aborted at payload map; see logs/qemu-open.log`
