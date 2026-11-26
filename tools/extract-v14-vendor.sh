#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Extract the V14 vendor tree that the rootfs build reads: the sensor
# configuration (/etc/sensors) and the VPU blob (/firmware/vpu20_4v.mbn).
#
# The input is the official V14.0.9.0.TMYCNXM fastboot package; super.img is an
# Android sparse image, and the in-tree lpunpack.py already converts sparse on
# the fly, so simg2img is not needed.  fsck.erofs extracts with permissions and
# xattrs; running unprivileged is fine because the build only reads these files.
#
# The rest of tools/local (firmware pool, ABL analysis, WLAN tuple, ISO) is
# prepared by the scripts in docs/BUILD.zh-CN.md section 4.1; this script only
# fills the vendor tree those steps expect.
#
# usage: sh tools/extract-v14-vendor.sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workspace_root=$(CDPATH= cd -- "$project_root/.." && pwd)
rom=${V14_ROM_DIR:-$workspace_root/liuqin_images_V14.0.9.0.TMYCNXM_13.0}
super=$rom/images/super.img
lpunpack=$workspace_root/lpunpack/lpunpack.py
base=$project_root/tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/extracted
work=${WORK_DIR:-$base/.work}
dest=$base/super-work/vendor-extract

die() { printf 'extract-v14-vendor: %s\n' "$*" >&2; exit 1; }
say() { printf 'extract-v14-vendor: %s\n' "$*"; }

[ -f "$super" ] || die "super.img is missing: $super (set V14_ROM_DIR)"
[ -f "$lpunpack" ] || die "lpunpack.py is missing: $lpunpack"
case $dest in
"$project_root"/tools/local/roms/*) ;;
*) die "refusing an output outside tools/local/roms: $dest" ;;
esac
if [ -d "$dest/etc/sensors" ] && [ -f "$dest/firmware/vpu20_4v.mbn" ]; then
	say "already extracted: $dest"
	exit 0
fi
fsck=${FSCK_EROFS:-$(command -v fsck.erofs 2>/dev/null || true)}
if [ -z "$fsck" ]; then
	for candidate in /usr/sbin/fsck.erofs /usr/bin/fsck.erofs; do
		[ -x "$candidate" ] && { fsck=$candidate; break; }
	done
fi
[ -n "$fsck" ] || die 'fsck.erofs is missing (install erofs-utils, or set FSCK_EROFS)'

mkdir -p "$work"
if [ ! -f "$work/vendor_a.img" ]; then
	say "unpacking vendor_a from $super"
	python3 "$lpunpack" -p vendor_a "$super" "$work"
fi
[ -f "$work/vendor_a.img" ] || die "vendor_a extraction produced no image in $work"

say "extracting vendor_a to $dest"
rm -rf "$dest"
mkdir -p "$dest"
"$fsck" --extract="$dest" "$work/vendor_a.img" >/dev/null ||
	die "fsck.erofs could not extract $work/vendor_a.img"

[ -d "$dest/etc/sensors" ] || die 'the vendor tree carries no /etc/sensors'
[ -f "$dest/firmware/vpu20_4v.mbn" ] || die 'the vendor tree carries no /firmware/vpu20_4v.mbn'
sensor_files=$(find "$dest/etc/sensors" -type f | wc -l | tr -d ' ')
say "vendor tree ready: $dest ($sensor_files sensor files)"
say 'next: build the Fedora root from the Live ISO (tools/build-liuqin-fedora-base.sh)'
