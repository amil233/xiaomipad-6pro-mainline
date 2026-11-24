#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Assemble the Ubuntu root filesystem on the build machine.
#
# The desktop root, its chroot and the archive need tens of gigabytes; the
# development machine does not have them (it keeps only the kernel boot image,
# which is seconds of dtc/mkbootimg work).  This is the single command the build
# machine runs: it prepares the inputs (cached slow builds included) and then
# assembles boot.img + rootfs.tar.gz into out/image/bundle.
#
# Requirements, checked by --check:
#   * root (chroot, ownership, tar xattrs)
#   * aarch64 host, or qemu-aarch64 binfmt with the P flag on another arch
#   * about 20 GiB free (ISO 3.9 + casper 3.2 + desktop root 3.2 + copy 3.2 + tar ~3 GiB)
#   * the tracked firmware pool, WLAN tuple, sensor configuration and
#     AudioReach sources, the Ubuntu ISO, and the kernel artifact
#
# usage:
#   sudo sh tools/build-liuqin-rootfs.sh --check     # report readiness only
#   sudo sh tools/build-liuqin-rootfs.sh             # prepare, then assemble
#   sudo sh tools/build-liuqin-rootfs.sh --kernel ci/liuqin-kernel-<commit>/kernel
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workspace_root=$(CDPATH= cd -- "$project_root/.." && pwd)
base_dir=$project_root/tools/local/ubuntu-desktop-26.04.1-arm64
base_root=$base_dir/rootfs
base_manifest=$base_dir/rootfs.manifest
inputs_json=$project_root/out/image-inputs.local.json

die() { printf 'build-liuqin-rootfs: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-rootfs: %s\n' "$*"; }

usage() {
	cat <<'EOF'
usage: build-liuqin-rootfs.sh [--check] [--rootfs-only] [--fingerprint] [--kernel DIR] [--out DIR]

  --kernel DIR    artifact root or its kernel/ directory; defaults to the
                  newest artifact under ci/
  --out DIR       assembly output inside out/; defaults to out/image
  --rootfs-only   assemble rootfs.tar.gz only (tracked firmware, no boot.img)
  --fingerprint   also include the optional fingerprint package
  --check         print the readiness report and exit; write nothing
EOF
}

kernel=
out_dir=$project_root/out/image
check_only=0
rootfs_only=0
with_fingerprint=0
while [ $# -gt 0 ]; do
	case $1 in
	--rootfs-only) rootfs_only=1; shift ;;
	--fingerprint) with_fingerprint=1; shift ;;
	--kernel) [ $# -ge 2 ] || die '--kernel needs a value'; kernel=$2; shift 2 ;;
	--out) [ $# -ge 2 ] || die '--out needs a value'; out_dir=$2; shift 2 ;;
	--check) check_only=1; shift ;;
	-h | --help) usage; exit 0 ;;
	*) die "unknown argument: $1" ;;
	esac
done

out_dir=$(realpath -m -- "$out_dir")

failures=0
report() { # report OK|MISSING|WARN description
	case $1 in
	OK) printf '  ok      %s\n' "$2" ;;
	MISSING) failures=$((failures + 1)); printf '  MISSING %s\n' "$2" ;;
	WARN) printf '  warn    %s\n' "$2" ;;
	esac
}

say 'build host'
arch=$(uname -m)
if [ "$arch" = aarch64 ]; then
	report OK "arch aarch64 (native chroot, no qemu)"
elif grep -qs P /proc/sys/fs/binfmt_misc/qemu-aarch64; then
	report OK "arch $arch with qemu-aarch64 binfmt"
else
	report MISSING "arch $arch without qemu-aarch64 binfmt (need an aarch64 host or binfmt)"
fi
if [ "$(id -u)" = 0 ]; then report OK 'running as root'; else report MISSING 'root (run with sudo)'; fi
free_gb=$(df -Pm "$project_root" | awk 'NR == 2 { print int($4 / 1024) }')
need_gb=20
[ "$rootfs_only" = 1 ] && need_gb=13
if [ "${free_gb:-0}" -ge "$need_gb" ]; then
	report OK "free space ${free_gb} GiB on $project_root"
else
	report MISSING "free space ${free_gb:-0} GiB (need about $need_gb GiB)"
fi
tools='python3 dpkg-deb tar gzip sha256sum curl git flock chroot mount unshare 7z unsquashfs file readelf gcc m4 alsatplg zstd patch'
for tool in $tools; do
	command -v "$tool" >/dev/null 2>&1 || report MISSING "tool: $tool"
done
if command -v gcc >/dev/null 2>&1 && [ "$(gcc -dumpmachine 2>/dev/null)" != "${arch}-linux-gnu" ] &&
	[ "$arch" = aarch64 ]; then
	report WARN "host gcc reports $(gcc -dumpmachine), expected aarch64-linux-gnu"
fi
if [ -d "$base_root" ] && [ -f "$base_manifest" ]; then
	report OK "Ubuntu desktop base: $base_dir"
else
	report WARN "Ubuntu desktop base missing; the first run downloads and extracts it (~4.1 GiB ISO)"
fi

say 'kernel artifact'
# shellcheck source=tools/lib/kernel-artifact.sh
. "$project_root/tools/lib/kernel-artifact.sh"
if resolve_kernel_artifact "$project_root" "$workspace_root" "$kernel"; then
	kernel_dir=$KERNEL_DIR
	report OK "artifact $KERNEL_COMMIT"
	if [ -f "$MODULES_DIR/modules.tar" ]; then
		report OK 'artifact carries the prepared module set'
	else
		report MISSING 'artifact has no kernel-modules/ (the build machine has no kernel tree)'
	fi
else
	report MISSING 'no consistent ci/liuqin-kernel-* artifact (copy one from CI or pass --kernel)'
fi

audio_sources_ok() {
	[ -f "$project_root/device/audio-topology/upstream/audioreach/audioreach.m4" ] ||
		[ -f "$project_root/../audioreach-topology/audioreach/audioreach.m4" ] ||
		[ -f "$project_root/tools/local/audioreach-topology/audioreach/audioreach.m4" ]
}

say 'inputs'
if [ -d "$project_root/device/sensors/rom" ]; then
	report OK 'tracked sensor configuration: device/sensors/rom'
else
	report MISSING 'tracked sensor configuration device/sensors/rom'
fi
if [ -x "$project_root/tools/local/busybox-arm64/usr/bin/busybox" ]; then
	report OK 'busybox'
else
	report MISSING 'busybox under tools/local (fetch-busybox-arm64.sh)'
fi
if [ -d "$project_root/device/firmware-pool" ]; then
	report OK 'tracked firmware pool: device/firmware-pool'
else
	report MISSING 'tracked firmware pool device/firmware-pool'
fi
if [ -f "$project_root/device/wlan-tuple/hw2.0/board-2.bin" ]; then
	report OK 'tracked WLAN tuple: device/wlan-tuple'
else
	report MISSING 'tracked WLAN tuple device/wlan-tuple'
fi
if audio_sources_ok; then
	report OK 'AudioReach topology sources'
else
	report MISSING 'AudioReach topology sources (device/audio-topology/upstream)'
fi
if [ "$rootfs_only" = 0 ]; then
	if [ -d "$project_root/tools/local/aosp-mkbootimg" ]; then
		report OK 'mkbootimg'
	else
		report MISSING 'mkbootimg under tools/local (fetch-aosp-mkbootimg.sh)'
	fi
	if [ -d "$project_root/tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis/dtbo" ] &&
		[ -d "$project_root/tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis/vendor_boot/dtbs" ]; then
		report OK 'ABL overlay/base DTB analysis'
	else
		report MISSING 'ABL overlay/base DTB analysis (tools/extract-v14-vendor.sh)'
	fi
fi

if [ "$check_only" = 1 ]; then
	if [ "$failures" = 0 ]; then
		say 'check PASS: ready to assemble'
		exit 0
	fi
	say "check FAIL: $failures requirement(s) missing"
	exit 1
fi
[ "$failures" = 0 ] || die "$failures requirement(s) missing; run --check for the report"
[ "$(id -u)" = 0 ] || die 'run as root (sudo)'
command -v 7z >/dev/null 2>&1 || [ -d "$base_root" ] ||
	die '7z is required to extract the Ubuntu ISO (install the 7zip package)'

# --- prepare the Ubuntu base (first run only) -------------------------------

if [ ! -d "$base_root" ] || [ ! -f "$base_manifest" ]; then
	say 'preparing the Ubuntu 26.04.1 desktop base (download, casper, extract)'
	sh "$project_root/tools/build-liuqin-ubuntu-desktop-rootfs.sh" download
	sh "$project_root/tools/build-liuqin-ubuntu-desktop-rootfs.sh" casper
	sh "$project_root/tools/build-liuqin-ubuntu-desktop-rootfs.sh" extract
fi
if [ "${DROP_ISO:-0}" = 1 ]; then
	rm -rf "$base_dir/iso"
	rm -f "$base_dir"/*.iso
fi

# --- rootfs-only ------------------------------------------------------------

if [ "$rootfs_only" = 1 ]; then
	say 'preparing rootfs inputs'
	fingerprint_arg=
	[ "$with_fingerprint" = 1 ] && fingerprint_arg=--fingerprint
	python3 "$project_root/tools/prepare-image-inputs.py" run --rootfs $fingerprint_arg
	[ -f "$inputs_json" ] || die "input preparation produced no $inputs_json"
	say 'assembling rootfs'
	python3 "$project_root/tools/build-liuqin-image.py" \
		--inputs "$inputs_json" --kernel-out "$kernel_dir" --out "$out_dir" \
		--stage rootfs
	tar=$out_dir/root/rootfs.tar.gz
	hashes=$out_dir/root/native-root.hashes
	[ -f "$tar" ] || die "assembly produced no rootfs tar: $tar"
	say "rootfs: $tar"
	say "hashes: $hashes"
	say 'next:   split the tar for upload; build boot.img separately when pairing a fresh root'
	exit 0
fi

# --- slow inputs (sensors stack, power panel, firmware, topology, WLAN) -----

say 'preparing inputs'
fingerprint_arg=
[ "$with_fingerprint" = 1 ] && fingerprint_arg=--fingerprint
python3 "$project_root/tools/prepare-image-inputs.py" run $fingerprint_arg
[ -f "$inputs_json" ] || die "input preparation produced no $inputs_json"

# --- assemble ---------------------------------------------------------------

say 'assembling rootfs and boot image'
python3 "$project_root/tools/build-liuqin-image.py" \
	--inputs "$inputs_json" --kernel-out "$kernel_dir" --out "$out_dir"

bundle=$out_dir/bundle
[ -d "$bundle" ] || die "assembly produced no bundle: $bundle"
say "bundle: $bundle"
say "boot:   $bundle/boot.img"
say "rootfs: $bundle/rootfs.tar.gz"
say "hashes: $bundle/native-root.hashes"
say "next:   copy the bundle to the flashing host, then INSTALL section 2"
