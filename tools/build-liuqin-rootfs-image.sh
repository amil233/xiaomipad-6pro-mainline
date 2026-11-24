#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Turn an assembled root filesystem into the ext4 image that
# `fastboot flash userdata` writes.
#
# Layout (2026-11-24): the stock partition table is left untouched.  boot_a is
# replaced by our boot image, and the stock `userdata` partition is the single
# data partition -- one ext4 filesystem labelled LIUQIN_ROOT holding the tree
# below native-root/ (the directory the native initramfs bind-mounts as /).
# There is no linux_root/linux_home split, no separate /home and no /boot
# partition; /home is an ordinary directory on the root.
#
# The Ubuntu 26.04 desktop root itself is assembled off-device (CI bundle); a
# tablet never builds its own root.  This script only converts the archive the
# device will mount into a filesystem fastboot can write.
#
#   rootfs.tar.gz / assembled tree
#     + native-root/ subdirectory
#     -> rootfs.img (LABEL=LIUQIN_ROOT)
#
# It refuses a tree the tablet would reject: the native-root marker must be the
# one the initramfs pins, and the kernel release recorded in the root must have
# its module directory, so this image cannot be flashed beside an Image built
# from another commit.
#
# usage:
#   sudo tools/build-liuqin-rootfs-image.sh --rootfs rootfs.tar.gz --out DIR
#   sudo tools/build-liuqin-rootfs-image.sh --root DIR --out DIR
#        [--size 8G] [--kernel-release 7.3.0-g...] [--check]
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# The native root marker the initramfs pins; build-liuqin-native-root.sh writes
# the same value and initramfs/init checks it before mounting the root.
marker_sha256=4fdae4f7a27af8b0d4a2bbc168c7f01c3c5c6b5e245fcc521389d662f8212c5b

die() { printf 'build-liuqin-rootfs-image: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-rootfs-image: %s\n' "$*"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

usage() {
	cat <<'EOF'
usage: build-liuqin-rootfs-image.sh --rootfs TAR | --root DIR --out DIR
                                   [--size 8G] [--kernel-release RELEASE]
                                   [--check]

  --rootfs TAR         rootfs.tar.gz produced by the image assembly
  --root DIR           an already assembled root tree (same layout as the tar)
  --out DIR            where rootfs.img and SHA256SUMS are written
  --size SIZE          image size, e.g. 8G or 8192M; default: tree + 25%
                       (the tablet can grow it to the whole userdata partition)
  --kernel-release R   assert that R is the release the root carries
  --check              verify the inputs and print the plan, write no image
EOF
}

tool() {
	# e2fsprogs lives in /sbin, which is not always in PATH.
	command -v "$1" 2>/dev/null ||
		for candidate in /usr/sbin/"$1" /sbin/"$1"; do
			[ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
		done
	return 1
}

to_bytes() {
	value=$1
	case $value in
	*[Gg]) printf '%s\n' "$(( ${value%?} * 1024 * 1024 * 1024 ))" ;;
	*[Mm]) printf '%s\n' "$(( ${value%?} * 1024 * 1024 ))" ;;
	*[Kk]) printf '%s\n' "$(( ${value%?} * 1024 ))" ;;
	'' | *[!0-9]*) die "not a size: $value (use 8G, 8192M, ...)" ;;
	*) printf '%s\n' "$value" ;;
	esac
}

root=
archive=
out_dir=
size=
kernel_release=
check_only=0
while [ $# -gt 0 ]; do
	case $1 in
	--rootfs) [ $# -ge 2 ] || die '--rootfs needs a value'; archive=$2; shift 2 ;;
	--root) [ $# -ge 2 ] || die '--root needs a value'; root=$2; shift 2 ;;
	--out) [ $# -ge 2 ] || die '--out needs a value'; out_dir=$2; shift 2 ;;
	--size) [ $# -ge 2 ] || die '--size needs a value'; size=$2; shift 2 ;;
	--kernel-release) [ $# -ge 2 ] || die '--kernel-release needs a value'; kernel_release=$2; shift 2 ;;
	--check) check_only=1; shift ;;
	-h | --help) usage; exit 0 ;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -n "$archive" ] && [ -n "$root" ] && die 'pass exactly one of --rootfs and --root'
[ -n "$archive" ] || [ -n "$root" ] || die 'pass one of --rootfs or --root (see --help)'
[ -n "$out_dir" ] || die '--out is required'
if [ -n "$root" ]; then
	case $(realpath -m -- "$out_dir") in
	"$(realpath -m -- "$root")"/*) die '--out must not be inside the input tree' ;;
	esac
fi
if [ -n "$archive" ]; then
	[ -f "$archive" ] || die "rootfs archive is missing: $archive"
	[ "$(id -u)" = 0 ] || die 'extracting rootfs.tar.gz needs root (numeric ownership, ACLs, xattrs)'
else
	[ -d "$root" ] || die "root tree is missing: $root"
	[ "$(realpath -m -- "$root")" != / ] || die 'the host root is not a valid input'
	if [ "$(id -u)" != 0 ]; then
		foreign=$(find "$root" -not -uid "$(id -u)" -print -quit)
		[ -z "$foreign" ] || die "root tree contains files owned by another user ($foreign); run as root"
	fi
fi

for command in mke2fs e2fsck dumpe2fs debugfs; do
	eval "${command}_bin=\$(tool $command)" || die "$command is required (install e2fsprogs)"
done

mkdir -p "$out_dir"
out_dir=$(CDPATH= cd -- "$out_dir" && pwd)
rootfs_img=$out_dir/rootfs.img
work=$(mktemp -d "$out_dir/.rootfs-image.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# --- assemble the tree the tablet will mount --------------------------------

if [ -n "$archive" ]; then
	say "extracting: $archive"
	sh "$project_root/tools/lib/rootfs-archive.sh" extract "$work/native-root" "$(realpath -- "$archive")"
else
	say "staging:    $root"
	cp -a --link "$root" "$work/native-root" 2>/dev/null ||
		cp -a "$root" "$work/native-root" ||
		die 'could not stage the root tree'
fi
tree=$work/native-root

# --- gates: exactly what the initramfs will accept --------------------------

[ -x "$tree/usr/lib/systemd/systemd" ] || die "not an Ubuntu root (no systemd): $tree"
marker=$tree/etc/liuqin-native-root
[ -f "$marker" ] && [ ! -L "$marker" ] || die "native root marker is missing or a symlink: $marker"
[ "$(sha "$marker")" = "$marker_sha256" ] || die "native root marker content mismatch: $marker"
[ "$(stat -c '%a' "$marker")" = 644 ] || die "native root marker mode is not 644: $marker"
[ "$(id -u)" != 0 ] || [ "$(stat -c '%u:%g' "$marker")" = 0:0 ] ||
	die "native root marker is not owned by root: $marker"

release=$(cat "$tree/usr/share/liuqin/kernel.release" 2>/dev/null || true)
[ -n "$release" ] || die 'the root carries no /usr/share/liuqin/kernel.release'
if [ -n "$kernel_release" ] && [ "$release" != "$kernel_release" ]; then
	die "root kernel release $release does not match $kernel_release"
fi
modules=$tree/usr/lib/modules/$release
[ -d "$modules" ] || die "the root carries no modules for $release (kernel deb not installed?)"
module_count=$(find "$modules" -name '*.ko*' -type f | wc -l | tr -d ' ')
[ "$module_count" -ge 1 ] || die "module directory $release is empty"

# --- size -------------------------------------------------------------------

used_mb=$(du -sm --apparent-size "$tree" | cut -f1)
if [ -z "$size" ]; then
	# Round the payload up with 25% headroom.  The image does not have to match
	# the partition: the filesystem is grown online with resize2fs once the
	# tablet runs from it.
	root_bytes=$(( (used_mb * 125 / 100 + 512 + 1023) / 1024 * 1024 * 1024 ))
	[ "$root_bytes" -ge $((6 * 1024 * 1024 * 1024)) ] ||
		root_bytes=$((6 * 1024 * 1024 * 1024))
else
	root_bytes=$(to_bytes "$size")
fi
[ "$root_bytes" -ge $(( (used_mb * 5 / 4 + 32) * 1024 * 1024 )) ] ||
	die "image size $((root_bytes / 1024 / 1024)) MiB cannot hold a $used_mb MiB tree"
avail_mb=$(df -Pm "$out_dir" | awk 'NR == 2 { print $4 }')
[ "$avail_mb" -ge $((used_mb + 256)) ] ||
	die "not enough space in $out_dir: ${avail_mb} MiB free, ${used_mb} MiB tree"

say "root:       $used_mb MiB, $module_count modules of $release"
say "image:      $((root_bytes / 1024 / 1024)) MiB ext4, LABEL=LIUQIN_ROOT"
say "target:     userdata (single data partition; no /home or /boot partition)"

if [ "$check_only" = 1 ]; then
	say "check PASS: $tree"
	exit 0
fi

# --- write and verify -------------------------------------------------------

say "formatting: $rootfs_img"
rm -f "$rootfs_img"
truncate -s "$root_bytes" "$rootfs_img"
"$mke2fs_bin" -q -F -t ext4 -L LIUQIN_ROOT -m 0 \
	-E lazy_itable_init=0,lazy_journal_init=0 -d "$work" "$rootfs_img" ||
	die "mke2fs failed: $rootfs_img"
"$e2fsck_bin" -fn "$rootfs_img" >/dev/null 2>&1 ||
	{ "$e2fsck_bin" -fn "$rootfs_img" || true; die "e2fsck rejected $rootfs_img"; }
[ "$("$dumpe2fs_bin" -h "$rootfs_img" 2>/dev/null | sed -n 's/^Filesystem volume name: *//p')" = LIUQIN_ROOT ] ||
	die "image label is not LIUQIN_ROOT: $rootfs_img"
"$debugfs_bin" -R 'stat /native-root/etc/liuqin-native-root' "$rootfs_img" 2>/dev/null |
	grep -q 'Type: regular' || die 'rootfs.img does not contain native-root/'
"$debugfs_bin" -R "stat /native-root/usr/lib/modules/$release" "$rootfs_img" 2>/dev/null |
	grep -q 'Type: directory' || die 'rootfs.img does not contain the kernel modules'

# An image from the retired split layout is not something to flash any more.
if [ -f "$out_dir/linux_home.img" ]; then
	rm -f "$out_dir/linux_home.img"
	say 'removed stale linux_home.img (the split layout is retired)'
fi
(
	cd "$out_dir"
	sha256sum rootfs.img >SHA256SUMS
)

say "rootfs:     $rootfs_img ($(stat -c '%s' "$rootfs_img") bytes, sha256 $(sha "$rootfs_img" | cut -c1-16)...)"
say 'next (flashing host):'
say '  fastboot flash boot_a  <bundle>/boot.img'
say "  fastboot flash userdata $rootfs_img"
say 'grow the filesystem to the whole partition after first boot:'
say '  resize2fs /dev/disk/by-partlabel/userdata'
