#!/bin/bash
# Pull this phone's own device tree over adb and turn it into the SoC boot-args the kernel takes
# (tools/soc-args.py). Same as ../poco-x5-pro/pull-soc.sh; the values are whatever this phone has.
# Needs the phone in Android with adb (root not required: /sys/firmware/fdt is world-readable).
set -e
cd "$(dirname "$0")/../.."
PATH=$PWD/tools/macos-bin/platform-tools:$PATH
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
adb pull /sys/firmware/fdt "$tmp/fdt" >/dev/null || { echo "pull-soc.sh: cannot read /sys/firmware/fdt over adb"; exit 1; }
# keep what we read, so the args can be re-derived without the phone
cp "$tmp/fdt" "$(dirname "$0")/device-tree.dtb"
tools/soc-args.py "$tmp/fdt" | tee "$(dirname "$0")/soc.args"
echo "pull-soc.sh: wrote $(dirname "$0")/soc.args and device-tree.dtb"
echo "pull-soc.sh: run ../poco-f7-ultra/probe.sh for the reserved-memory values soc-args.py does not read"
