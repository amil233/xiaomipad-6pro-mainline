#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Assemble the slot-A boot image from one CI kernel artifact, in one command.
#
# Two things must agree before a boot image is worth flashing:
#
#   * kernel identity -- the artifact's Image, DTB and modules were built from
#     the commit kernel/source.json locks; an artifact of another commit (or a
#     corrupted one) would boot a kernel whose modules do not match the root;
#   * root identity -- the initramfs carries /etc/liuqin-native-root.contract,
#     a hash list over the device files of the root it was assembled for.  The
#     initramfs refuses to mount a root that differs, so a ramdisk built for
#     another user space produces an image that cannot boot.
#
# A kernel-only change never touches the root, so it reuses the installed
# root's ramdisk.  A user-space change rebuilds the root (and its contract)
# together with the boot image; see docs/BUILD.zh-CN.md.
#
# usage:
#   sh tools/build-liuqin-boot.sh                     # artifact of the lock
#   sh tools/build-liuqin-boot.sh --check             # verify, build nothing
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
                           [--native-hashes FILE] [--out DIR] [--check]

  --kernel ARTIFACT    ci/liuqin-kernel-<sha> (or its kernel/ directory);
                       defaults to the artifact of kernel/source.json's commit
  --ramdisk FILE       initramfs to embed; defaults to the installed root's
                       out/initramfs-liuqin/liuqin-firstboot.cpio.gz
  --native-hashes FILE manifest of the installed root; defaults to
                       out/native-root/native-root.hashes
  --out DIR            output directory; defaults to repack/<sha6>-boot and
                       must not exist yet
  --check              verify every input and print the plan, build nothing
EOF
}

kernel=
ramdisk=
hashes=
out_dir=
check_only=0
while [ $# -gt 0 ]; do
	case $1 in
	--kernel) [ $# -ge 2 ] || die '--kernel needs a value'; kernel=$2; shift 2 ;;
	--ramdisk) [ $# -ge 2 ] || die '--ramdisk needs a value'; ramdisk=$2; shift 2 ;;
	--native-hashes) [ $# -ge 2 ] || die '--native-hashes needs a value'; hashes=$2; shift 2 ;;
	--out) [ $# -ge 2 ] || die '--out needs a value'; out_dir=$2; shift 2 ;;
	--check) check_only=1; shift ;;
	-h|--help) usage; exit 0 ;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -f "$lock" ] || die "kernel lock is missing: $lock"
commit=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["commit"])' "$lock")
dtb_rel=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["dtb"])' "$lock")
short=$(printf '%s' "$commit" | cut -c1-6)

# The artifact is the CI output for exactly the locked commit.  Accept either
# the artifact directory or its kernel/ subdirectory, because both spellings
# appear in the documentation and in hand-typed commands.
if [ -z "$kernel" ]; then
	kernel=$workspace_root/ci/liuqin-kernel-$commit
fi
[ -d "$kernel" ] || die "kernel artifact is missing: $kernel (available: $(ls "$workspace_root/ci" 2>/dev/null | tr '\n' ' '))"
if [ -d "$kernel/kernel" ] && [ ! -f "$kernel/build-info.json" ]; then
	artifact=$(CDPATH= cd -- "$kernel" && pwd)
	kernel_dir=$artifact/kernel
else
	kernel_dir=$(CDPATH= cd -- "$kernel" && pwd)
	artifact=$(dirname "$kernel_dir")
fi
[ -f "$kernel_dir/build-info.json" ] || die "not a kernel artifact (no build-info.json): $kernel_dir"
modules_dir=$artifact/kernel-modules

# --- kernel identity ---------------------------------------------------------

artifact_commit=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["commit"])' "$kernel_dir/build-info.json")
[ "$artifact_commit" = "$commit" ] ||
	die "artifact commit $artifact_commit does not match kernel/source.json ($commit); update the lock or pick the right artifact"
say "artifact: $artifact"
say "kernel:   $artifact_commit ($short)"

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
	die 'could not derive the root contract'
python3 "$project_root/tools/lib/cpio-read.py" "$ramdisk" etc/liuqin-native-root.contract \
	>"$work/ramdisk.contract" 2>/dev/null ||
	die "the ramdisk carries no etc/liuqin-native-root.contract: $ramdisk"
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
say "ramdisk:  $(sha "$ramdisk") (contract matches $hashes)"

# --- output and assembly -----------------------------------------------------

[ -n "$out_dir" ] || out_dir=$workspace_root/repack/$short-boot
if [ "$check_only" = 1 ]; then
	say 'check PASS: artifact, root contract and inputs are consistent'
	say "would assemble: $out_dir/boot-liuqin-firstboot.img"
	[ ! -e "$out_dir" ] || say "note: $out_dir already exists; assembly would need --out"
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
say 'next:     fastboot boot  <image>   # trial'
say '          fastboot flash boot_a <image>'
