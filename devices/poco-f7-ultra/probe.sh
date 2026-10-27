#!/bin/bash
# Read-only discovery of a phone over adb, for porting HakiOS to it. Writes device-info.txt
# beside this script. Nothing on the phone is modified.
#
#   devices/poco-f7-ultra/probe.sh            # adb, phone in Android
#
# What it answers, in the order the port needs it: which SoC and codename, which device tree,
# the memory carveouts, the display and touch hardware, and which firmware files exist.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/device-info.txt
adb get-state >/dev/null 2>&1 || { echo "probe.sh: no device on adb (phone in Android, adb authorised)"; exit 1; }

sh_() { adb shell "$@" 2>/dev/null | tr -d '\r'; }
prop() { sh_ getprop "$1"; }

{
	echo "# captured $(date -u +%Y-%m-%dT%H:%M:%SZ) from $(prop ro.serialno)"
	echo
	echo "## identity"
	for p in ro.product.device ro.product.model ro.product.vendor.device ro.board.platform \
	         ro.soc.model ro.soc.manufacturer ro.build.version.release ro.build.fingerprint \
	         ro.boot.hardware ro.boot.product.hardware.sku; do
		printf '%-34s %s\n' "$p" "$(prop $p)"
	done
	echo
	echo "## kernel"
	sh_ uname -a
	echo
	echo "## device tree"
	sh_ ls -l /sys/firmware/fdt /proc/device-tree/model /proc/device-tree/compatible
	sh_ cat /proc/device-tree/model; echo
	sh_ cat /proc/device-tree/compatible | tr '\0' '\n'
	echo
	echo "## memory"
	sh_ cat /proc/meminfo | head -3
	echo "-- reserved-memory nodes --"
	sh_ ls /proc/device-tree/reserved-memory
	echo "-- reg of each (address size) --"
	sh_ 'for d in /proc/device-tree/reserved-memory/*; do printf "%s " "$(basename $d)"; od -An -tx8 "$d/reg" 2>/dev/null | tr -s " " | head -1; done'
	echo
	echo "## display"
	sh_ wm size
	sh_ wm density
	sh_ ls /sys/class/drm
	sh_ 'for d in /proc/device-tree/soc*/*dsi* /proc/device-tree/*/*dsi*; do [ -e "$d" ] && echo "$d"; done' | head -20
	echo
	echo "## touch"
	sh_ getevent -pl 2>/dev/null | head -60
	echo
	echo "## storage"
	sh_ ls /sys/class/ufs /sys/bus/platform/drivers/ufshcd*
	sh_ cat /proc/partitions
	echo
	echo "## firmware inventory (names only, nothing is copied)"
	for d in /vendor/firmware /vendor/firmware_mnt/image /odm/firmware; do
		n=$(sh_ ls "$d" 2>/dev/null | wc -l)
		echo "-- $d: $n entries"
		sh_ ls "$d" 2>/dev/null | grep -Ei 'a8[0-9]{2}|gmu|zap|adsp|modem|wpss|ipa|wlan|haptic' | head -40
	done
	echo
	echo "## firmware names the device tree asks for"
	sh_ 'for f in $(find /proc/device-tree -name firmware-name 2>/dev/null); do printf "%s: " "$f"; tr -d "\0" < "$f"; echo; done' | head -60
	echo
	echo "## clock / interconnect summary (for the driver defaults)"
	sh_ 'cat /proc/device-tree/soc*/qcom,*-freq* 2>/dev/null | head' 
	echo
	echo "## SELinux and root state (informational)"
	sh_ getenforce
	sh_ id
} > "$OUT" 2>&1

echo "probe.sh: wrote $OUT ($(wc -l < "$OUT") lines)"
echo "probe.sh: read it before editing any driver constant"
