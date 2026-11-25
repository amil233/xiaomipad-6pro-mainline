#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Build a deliberately mismatched boot.img whose ramdisk rejects the installed
# root, so stage 1 stops in its USB/telnet rescue shell instead of switching
# root.  The normal boot.img is untouched.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
hashes=
kernel=
out=$project_root/out/rescue-boot
corrupt_path=/etc/liuqin-native-root

die() { printf 'build-liuqin-rescue-boot: %s\n' "$*" >&2; exit 1; }
usage() {
	cat <<'USAGE'
usage: build-liuqin-rescue-boot.sh --hashes FILE --kernel ARTIFACT [--out DIR]
                                   [--corrupt-path PATH]

  --hashes FILE          native-root.hashes from the installed root/CI artifact
  --kernel ARTIFACT      ci/liuqin-kernel-<commit> whose release matches the root
  --out DIR              fresh output directory (default out/rescue-boot)
  --corrupt-path PATH    pinned path to falsify (default /etc/liuqin-native-root)
USAGE
}

while [ $# -gt 0 ]; do
	case $1 in
	--hashes) [ $# -ge 2 ] || die '--hashes needs a value'; hashes=$2; shift 2 ;;
	--kernel) [ $# -ge 2 ] || die '--kernel needs a value'; kernel=$2; shift 2 ;;
	--out) [ $# -ge 2 ] || die '--out needs a value'; out=$2; shift 2 ;;
	--corrupt-path) [ $# -ge 2 ] || die '--corrupt-path needs a value'; corrupt_path=$2; shift 2 ;;
	-h | --help) usage; exit 0 ;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -f "$hashes" ] || die "root hash list is missing: $hashes"
[ -d "$kernel" ] || die "kernel artifact is missing: $kernel"
out=$(realpath -m -- "$out")
[ ! -e "$out" ] || die "output already exists: $out"
grep -Fq "  $corrupt_path" "$hashes" ||
	die "the root hash list does not pin $corrupt_path"

work=$(mktemp -d "${TMPDIR:-/tmp}/liuqin-rescue.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cp "$hashes" "$work/native-root.hashes"
python3 - "$work/native-root.hashes" "$corrupt_path" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
lines = []
for line in open(path, encoding='utf-8'):
    digest, _, rel = line.rstrip('\n').partition('  ')
    if rel == needle:
        line = '0' * 64 + '  ' + rel + '\n'
    lines.append(line)
open(path, 'w', encoding='utf-8').writelines(lines)
PY

NATIVE_ROOT_HASHES=$work/native-root.hashes \
KERNEL_SOURCE="$kernel/kernel" KERNEL_OUT="$kernel/kernel" \
FIRMWARE_POOL="$project_root/device/firmware-pool" \
WLAN_HSP2_TUPLE="$project_root/device/wlan-tuple" \
AUDIO_TOPOLOGY="$project_root/out/audio-topology/Xiaomi-Pad-6-Pro-tplg.bin" \
STOCK_OVERLAY_DIR="$project_root/device/abl-analysis/dtbo" \
STOCK_BASE_DIR="$project_root/device/abl-analysis/vendor_boot/dtbs" \
MKBOOTIMG_DIR="$project_root/tools/local/aosp-mkbootimg" \
OUT_DIR="$out" \
sh "$project_root/tools/build-liuqin-native-boot.sh"

printf 'rescue boot: %s/boot-liuqin-native.img\n' "$out"
printf 'flash it to boot_a, power on, then on the host:\n'
printf '  telnet 192.168.7.2 2323\n'
printf 'restore the normal CI boot.img afterwards.\n'
