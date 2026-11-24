#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Assemble the slot-A boot image from one CI kernel artifact, in one command.
#
# Two things are checked before the image is assembled:
#
#   * the artifact is self-consistent -- its directory name equals the commit
#     recorded in kernel/build-info.json, and both SHA256SUMS files verify;
#   * the initramfs carries a hash list of the installed root's device files.
#     This script recomputes that list from out/native-root/native-root.hashes
#     and refuses a ramdisk built for a different root.
#
# A kernel-only change does not touch the root, so it reuses the installed
# root's ramdisk.  A user-space change rebuilds the root and the boot image
# together; see docs/BUILD.zh-CN.md.
#
# usage:
#   sh tools/build-liuqin-boot.sh                     # newest ci/ artifact
#   sh tools/build-liuqin-boot.sh --check             # verify, build nothing
#   sh tools/build-liuqin-boot.sh --deb               # also the kernel deb
#   sh tools/build-liuqin-boot.sh --kernel CI_DIR --ramdisk FILE --out DIR
#
# Everything is local: the kernel is not compiled here, and no device is
# touched.  Flashing is a separate, explicit step.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workspace_root=$(CDPATH= cd -- "$project_root/.." && pwd)
lock=$project_root/kernel/source.json

die() { printf 'build-liuqin-boot: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-boot: %s\n' "$*"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

usage() {
	cat <<'EOF'
usage: build-liuqin-boot.sh [--kernel ARTIFACT] [--ramdisk FILE]
                           [--native-hashes FILE] [--out DIR] [--deb] [--check]

  --kernel ARTIFACT    ci/liuqin-kernel-<commit> (or its kernel/ directory);
                       defaults to the newest artifact under ci/
  --ramdisk FILE       initramfs to embed; defaults to the installed root's
                       out/initramfs-liuqin/liuqin-firstboot.cpio.gz
  --native-hashes FILE manifest of the installed root; defaults to
                       out/native-root/native-root.hashes
  --out DIR            output directory; defaults to repack/<sha6>-boot and
                       must not exist yet
  --deb                also package the matching liuqin-kernel deb into
                       out/liuqin-debs (the other half of a kernel update)
  --check              verify every input and print the plan, build nothing
EOF
}

kernel=
ramdisk=
hashes=
out_dir=
with_deb=0
check_only=0
while [ $# -gt 0 ]; do
	case $1 in
	--kernel) [ $# -ge 2 ] || die '--kernel needs a value'; kernel=$2; shift 2 ;;
	--ramdisk) [ $# -ge 2 ] || die '--ramdisk needs a value'; ramdisk=$2; shift 2 ;;
	--native-hashes) [ $# -ge 2 ] || die '--native-hashes needs a value'; hashes=$2; shift 2 ;;
	--out) [ $# -ge 2 ] || die '--out needs a value'; out_dir=$2; shift 2 ;;
	--deb) with_deb=1; shift ;;
	--check) check_only=1; shift ;;
	-h|--help) usage; exit 0 ;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -f "$lock" ] || die "kernel/source.json is missing: $lock"
dtb_rel=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["dtb"])' "$lock")

# --- kernel artifact ---------------------------------------------------------

# shellcheck source=tools/lib/kernel-artifact.sh
. "$project_root/tools/lib/kernel-artifact.sh"
if ! resolve_kernel_artifact "$project_root" "$workspace_root" "$kernel"; then
	if [ -n "$kernel" ]; then
		die "not a consistent artifact (directory name must be liuqin-kernel-<build-info commit>): $kernel"
	fi
	die "no ci/liuqin-kernel-* artifact found; copy one from CI or pass --kernel"
fi
artifact=$ARTIFACT kernel_dir=$KERNEL_DIR modules_dir=$MODULES_DIR commit=$KERNEL_COMMIT
short=$(printf '%s' "$commit" | cut -c1-6)
say "artifact: $artifact"
say "kernel:   $commit ($short)"

say 'verifying artifact checksums'
(cd "$kernel_dir" && sha256sum -c --quiet SHA256SUMS) || die "artifact checksum failure: $kernel_dir"
if [ -d "$modules_dir" ]; then
	(cd "$modules_dir" && sha256sum -c --quiet SHA256SUMS) || die "module checksum failure: $modules_dir"
	release=$(cat "$modules_dir/kernel.release" 2>/dev/null || true)
else
	release=
fi
[ -n "$release" ] || die "kernel release string is unavailable (no $modules_dir/kernel.release); rerun the CI action"
[ -f "$kernel_dir/arch/arm64/boot/Image" ] || die "artifact carries no Image: $kernel_dir"
[ -f "$kernel_dir/arch/arm64/boot/dts/$dtb_rel" ] || die "artifact carries no $dtb_rel"
say "release:  $release"

# --- root identity -----------------------------------------------------------

[ -n "$hashes" ] || hashes=$project_root/out/native-root/native-root.hashes
[ -f "$hashes" ] || die "installed-root manifest is missing: $hashes (run tools/build-liuqin-native-root.sh manifest on the rootfs host, or copy it from the bundle)"
[ -n "$ramdisk" ] || ramdisk=$project_root/out/initramfs-liuqin/liuqin-firstboot.cpio.gz
[ -f "$ramdisk" ] || die "ramdisk is missing: $ramdisk"
command -v cmp >/dev/null 2>&1 || die 'cmp is required'

work=$(mktemp -d "${TMPDIR:-/tmp}/liuqin-boot.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 "$project_root/tools/lib/build-root-contract.py" --profile native \
	--device-layer-manifest "$hashes" --output "$work/expected.contract" >/dev/null ||
	die 'could not derive the root file list'
python3 "$project_root/tools/lib/cpio-read.py" "$ramdisk" etc/liuqin-native-root.contract \
	>"$work/ramdisk.contract" 2>/dev/null ||
	die "the ramdisk has no root file list (etc/liuqin-native-root.contract): $ramdisk"
if ! cmp -s "$work/expected.contract" "$work/ramdisk.contract"; then
	cat >&2 <<EOF
build-liuqin-boot: the ramdisk was built for a different root filesystem.
  ramdisk contract:  $(sha "$work/ramdisk.contract")
  installed root:    $(sha "$work/expected.contract")  ($hashes)
The initramfs would refuse this root on the tablet.
  * kernel-only change: use the ramdisk that shipped with that root
    (bundle/liuqin-firstboot.cpio.gz, docs/INSTALL.zh-CN.md section 2);
  * user-space change: boot.img and rootfs.tar.gz come from the same new
    bundle; refresh both local files (docs/BUILD.zh-CN.md section 4).
EOF
	exit 1
fi
say "ramdisk:  $(sha "$ramdisk") (root file list matches $hashes)"

# --- output and assembly -----------------------------------------------------

[ -n "$out_dir" ] || out_dir=$workspace_root/repack/$short-boot
if [ "$check_only" = 1 ]; then
	say 'check PASS: artifact, root file list and inputs are consistent'
	say "would assemble: $out_dir/boot-liuqin-firstboot.img"
	[ ! -e "$out_dir" ] || say "note: $out_dir already exists; assembly would need --out"
	if [ "$with_deb" = 1 ]; then
		command -v dpkg-deb >/dev/null 2>&1 || die 'dpkg-deb is required for --deb'
		say "would package:  $project_root/out/liuqin-debs/liuqin-kernel_0.1_arm64.deb"
	fi
	exit 0
fi
if [ -e "$out_dir" ]; then
	die "output already exists: $out_dir (pass --out to keep the old image)"
fi

dtc=${DTC:-$(command -v dtc 2>/dev/null || true)}
fdtoverlay=${FDTOVERLAY:-$(command -v fdtoverlay 2>/dev/null || true)}
[ -n "$dtc" ] || die 'dtc is required (install device-tree-compiler or pass DTC=...)'
[ -n "$fdtoverlay" ] || die 'fdtoverlay is required (install device-tree-compiler or pass FDTOVERLAY=...)'

say "assembling: $out_dir"
KERNEL_OUT="$kernel_dir" OUT_DIR="$out_dir" RAMDISK="$ramdisk" \
	DTC="$dtc" FDTOVERLAY="$fdtoverlay" \
	sh "$project_root/tools/lib/build-bootimg.sh"

image=$out_dir/boot-liuqin-firstboot.img
[ -f "$image" ] || die "assembly produced no boot image: $image"
say "image:    $image ($(stat -c '%s' "$image") bytes)"
say "sha256:   $(sha "$image")"

if [ "$with_deb" = 1 ]; then
	command -v dpkg-deb >/dev/null 2>&1 || die 'dpkg-deb is required for --deb'
	say 'packaging the matching kernel deb'
	deb_dir=$project_root/out/liuqin-debs
	KERNEL_MODULES_DIR="$modules_dir" \
		KERNEL_IMAGE="$kernel_dir/arch/arm64/boot/Image" \
		KERNEL_DTB="$kernel_dir/arch/arm64/boot/dts/$dtb_rel" \
		OUT_DIR="$deb_dir" \
		sh "$project_root/tools/build-liuqin-debs.sh" kernel
	deb=$(ls "$deb_dir"/liuqin-kernel_*.deb 2>/dev/null | head -n 1)
	[ -n "$deb" ] || die "the deb package was not produced in $deb_dir"
	say "deb:      $deb ($(stat -c '%s' "$deb") bytes, sha256 $(sha "$deb" | cut -c1-16)...)"
fi

say 'next:     fastboot boot  <image>   # trial'
say '          fastboot flash boot_a <image>'
[ "$with_deb" = 0 ] || say '          dpkg -i <deb> on the tablet, then flash the image (INSTALL section 3)'
