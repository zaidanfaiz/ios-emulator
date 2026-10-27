#!/bin/bash
# Read-only dump of the partitions a UEFI port needs, straight off the phone over adb.
# Nothing is written to the phone and no partition is modified: `adb exec-out dd` streams the
# bytes to this machine. Blocks are dumped to dumps/ (git-ignored) with sizes and SHA-256.
#
#   devices/poco-f7-ultra/dump-partitions.sh            # needs root on the phone for /dev/block
#
# Why each block matters:
#   abl           Qualcomm's Android Bootloader — an EDK2/UEFI firmware image. Its platform init
#                 and DXE drivers are the reference a Mu-Silicium port for this SoC is built from.
#   dtbo/dtbo*    the device trees (overlays) the bootloader hands to the kernel
#   boot          Android kernel + ramdisk: the reference for cmdline, memory layout, console
#   vendor_boot   vendor ramdisk: modules and firmware paths
#   xbl*          Qualcomm's own bootloader stages (SBL): memory and power init order
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/dumps
mkdir -p "$OUT"
adb get-state >/dev/null 2>&1 || { echo "dump-partitions.sh: no device on adb"; exit 1; }
[ "$(adb shell id -u | tr -d '\r')" = 0 ] || { echo "dump-partitions.sh: adb is not root (adb root, or a root shell)"; exit 1; }

echo "--- bootloader state ---"
for p in ro.boot.flash.locked ro.boot.verifiedbootstate ro.boot.hardware ro.product.device; do
	printf '%-30s %s\n' "$p" "$(adb shell getprop $p | tr -d '\r')"
done

echo "--- partitions ---"
adb shell 'ls -l /dev/block/by-name/' | tr -d '\r' | tee "$OUT/by-name.txt"

for name in abl dtbo boot vendor_boot; do
	src=$(adb shell "readlink -f /dev/block/by-name/$name" | tr -d '\r' || true)
	[ -n "${src:-}" ] || { echo "  $name: absent"; continue; }
	size=$(adb shell "blockdev --getsize64 $src" | tr -d '\r')
	echo "  $name: $src ($size bytes)"
	adb exec-out "dd if=$src bs=4M 2>/dev/null" > "$OUT/$name.img"
	sha256sum "$OUT/$name.img" | sed "s|$OUT/||"
done

# every dtbo slot, if the device carries several
for n in $(adb shell 'ls /dev/block/by-name/ | grep -E "^dtbo" ' | tr -d '\r'); do
	[ "$n" = dtbo ] && continue
	adb exec-out "dd if=/dev/block/by-name/$n bs=4M 2>/dev/null" > "$OUT/$n.img"
	echo "  $n: $(sha256sum "$OUT/$n.img" | cut -d' ' -f1)"
done

echo "--- memory map (full map needs root) ---"
adb shell cat /proc/iomem | tr -d '\r' > "$OUT/iomem.txt"
adb shell dmesg | tr -d '\r' > "$OUT/dmesg.txt" || echo "  dmesg not readable (dmesg_restrict)"

echo
echo "dump-partitions.sh: wrote $OUT"
du -sh "$OUT"
echo "dump-partitions.sh: dumps/ is git-ignored; never commit vendor or bootloader images"
