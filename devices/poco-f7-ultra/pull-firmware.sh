#!/bin/bash
# Pull the firmware this phone asks for, into fw-*/ at the top of the repository (never committed:
# it is the vendor's). Discovery-driven on purpose: a new SoC has new firmware names, so the list
# comes from the phone's own device tree and firmware directory, not from a table written here.
#
#   devices/poco-f7-ultra/pull-firmware.sh        # phone in Android, on adb
#
# Sets are pulled whole: a firmware name `foo.mdt` brings `foo.b00..foo.bNN` and `foo.mbn` too.
set -u
cd "$(dirname "$0")/../.."
adb get-state >/dev/null 2>&1 || { echo "pull-firmware.sh: no device on adb"; exit 1; }
DIRS="/vendor/firmware /vendor/firmware_mnt/image /odm/firmware"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

sh_() { adb shell "$@" 2>/dev/null | tr -d '\r'; }

# 1. every firmware name the device tree names (firmware-name properties)
sh_ 'for f in $(find /proc/device-tree -name firmware-name 2>/dev/null); do tr -d "\0" < "$f"; echo; done' \
	| sort -u > "$TMP/names"
echo "pull-firmware.sh: $(wc -l < "$TMP/names") firmware names in the device tree"

# 2. plus the files whose names look like this SoC's blocks, so nothing the tree misses is lost
for d in $DIRS; do sh_ ls "$d" 2>/dev/null; done \
	| grep -Ei '^(a[0-9]{3}_|adsp|modem|wpss|ipa|wlan|haptic|.*zap)' \
	| sort -u >> "$TMP/names"
sort -u "$TMP/names" -o "$TMP/names"

# 3. classify and pull
classify() { # NAME -> fw-dir
	case $1 in
	a[0-9][0-9][0-9]_*)            echo fw-gpu ;;
	wpss*|*wlan*|*wifi*)           echo fw-wifi ;;
	adsp*)                         echo fw-audio ;;
	modem*|mba*|qdsp6*)            echo fw-modem ;;
	*ipa*|ipa_fws*)                echo fw-modem ;;
	*haptic*|*aw8*|*aw9*)          echo fw-haptic ;;
	*_zap*)                        echo fw-gpu ;;
	*)                             echo fw-other ;;
	esac
}

pulled=0; missing=0
while read -r name; do
	[ -n "$name" ] || continue
	base=${name##*/}
	# the set: stem before .mdt/.bNN/.mbn
	stem=${base%.*}
	stem=${stem%.b[0-9][0-9]}
	dest=$(classify "$base")
	mkdir -p "$dest"
	found=0
	for d in $DIRS; do
		listing=$(sh_ ls "$d" 2>/dev/null)
		[ -n "$listing" ] || continue
		for f in $(echo "$listing" | grep -E "^${stem}(\.|$)"); do
			adb pull "$d/$f" "$dest/" >/dev/null 2>&1 && found=1
		done
		# the whole adsp/modem set on this phone lives under firmware_mnt/image
		[ "$dest" = fw-modem ] && [ -z "$(ls -A "$dest" 2>/dev/null)" ] && \
			adb pull "$d" "fw-modem/" >/dev/null 2>&1
	done
	if [ $found -eq 1 ]; then pulled=$((pulled+1)); else missing=$((missing+1)); echo "  missing: $base"; fi
done < "$TMP/names"

# 4. what each driver still wants by hand
mkdir -p fw-wifi
sh_ ls /vendor/firmware_mnt/image >/dev/null 2>&1 && \
	adb pull /vendor/firmware_mnt/image fw-wifi/ >/dev/null 2>&1 && echo "pull-firmware.sh: fw-wifi/image: the Wi-Fi files, names unknown until probe.sh"

for d in fw-gpu fw-wifi fw-audio fw-modem fw-haptic fw-other; do
	[ -d "$d" ] && echo "pull-firmware.sh: $d: $(ls -1 "$d" 2>/dev/null | wc -l | tr -d ' ') files"
done
echo "pull-firmware.sh: $pulled names pulled, $missing not found on the phone"
echo "pull-firmware.sh: still manual: fw-wifi/mac (radio address) and fw-wifi/network (SSID/passphrase)"
