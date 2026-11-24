#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Turn an assembled root filesystem into the ext4 image that
# `fastboot flash linux_root` writes.
#
# The build produces rootfs.tar.gz: paths relative to /, numeric ownership,
# ACLs and xattrs preserved.  fastboot writes block devices, so the tablet
# needs a filesystem, and the native initramfs looks for the tree below
# <linux_root>/native-root (it bind-mounts that directory as /).  This script
# is the only place where those two views meet:
#
#   rootfs.tar.gz / assembled tree
#     + native-root/ subdirectory
#     + /etc/fstab entry for the separate home partition (layout, not content)
#     -> rootfs.img (LABEL=LIUQIN_ROOT), optionally linux_home.img
#
# It refuses a tree that the tablet would reject: the native-root marker must
# be the one the initramfs pins, and the kernel release recorded in the root
# must have its module directory, so this image cannot be flashed beside an
# Image built from another commit.
#
# usage:
#   sudo tools/build-liuqin-rootfs-image.sh --rootfs rootfs.tar.gz --out DIR
#   sudo tools/build-liuqin-rootfs-image.sh --root ASSEMBLED_ROOT --out DIR
#        [--size 12G] [--home-size 8G] [--kernel-release 7.3.0-g...] [--check]
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# The native root marker the initramfs pins; build-liuqin-native-root.sh writes
# the same value and initramfs/init checks it before mounting the root.
marker_sha256=4fdae4f7a27af8b0d4a2bbc168c7f01c3c5c6b5e245fcc521389d662f8212c5b
home_line='LABEL=LIUQIN_HOME /home ext4 defaults,nofail,x-systemd.device-timeout=30s 0 2'

die() { printf 'build-liuqin-rootfs-image: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-rootfs-image: %s\n' "$*"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

usage() {
	cat <<'EOF'
usage: build-liuqin-rootfs-image.sh --rootfs TAR | --root DIR --out DIR
                                   [--size 12G] [--home-size 8G]
                                   [--kernel-release RELEASE] [--check]

  --rootfs TAR         rootfs.tar.gz produced by build-liuqin-native-root.sh
  --root DIR           an already assembled root tree (same layout as the tar)
  --out DIR            where rootfs.img, the optional linux_home.img and
                       SHA256SUMS are written
  --size SIZE          image size, e.g. 12G or 8192M; default: tree + 25%
  --home-size SIZE     also create an empty ext4 home image of that size
                       (only for a clean install: flashing it wipes /home)
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
	'' | *[!0-9]*) die "not a size: $value (use 12G, 8192M, ...)" ;;
	*) printf '%s\n' "$value" ;;
	esac
}

root=
archive=
out_dir=
size=
home_size=
kernel_release=
check_only=0
while [ $# -gt 0 ]; do
	case $1 in
	--rootfs) [ $# -ge 2 ] || die '--rootfs needs a value'; archive=$2; shift 2 ;;
	--root) [ $# -ge 2 ] || die '--root needs a value'; root=$2; shift 2 ;;
	--out) [ $# -ge 2 ] || die '--out needs a value'; out_dir=$2; shift 2 ;;
	--size) [ $# -ge 2 ] || die '--size needs a value'; size=$2; shift 2 ;;
	--home-size) [ $# -ge 2 ] || die '--home-size needs a value'; home_size=$2; shift 2 ;;
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
home_img=$out_dir/linux_home.img
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

# --- layout: the home partition is a deployment fact ------------------------

fstab=$tree/etc/fstab
if [ -f "$fstab" ] && awk '$2 == "/home" { found = 1 } END { exit !found }' "$fstab"; then
	say 'fstab:      /home already mounted'
else
	{
		if [ -f "$fstab" ]; then
			cat "$fstab"
		else
			printf '# Written by build-liuqin-rootfs-image.sh. The root filesystem is\n'
			printf '# mounted by the boot image, which finds it by LABEL=LIUQIN_ROOT.\n'
		fi
		printf '%s\n' "$home_line"
	} >"$work/fstab.new"
	rm -f "$fstab"                       # staged copy: never edit the input tree
	mv "$work/fstab.new" "$fstab"
	chmod 0644 "$fstab"
	[ "$(id -u)" != 0 ] || chown 0:0 "$fstab"
	say "fstab:      added $home_line"
fi

# --- size -------------------------------------------------------------------

used_mb=$(du -sm --apparent-size "$tree" | cut -f1)
if [ -z "$size" ]; then
	# Round the payload up to whole GiB with 25% headroom.  The image does not
	# have to match the partition: the filesystem is grown online with
	# resize2fs once the tablet runs from it.
	root_bytes=$(( (used_mb * 125 / 100 + 512 + 1023) / 1024 * 1024 * 1024 ))
	[ "$root_bytes" -ge $((6 * 1024 * 1024 * 1024)) ] ||
		root_bytes=$((6 * 1024 * 1024 * 1024))
else
	root_bytes=$(to_bytes "$size")
fi
[ "$root_bytes" -ge $(( (used_mb * 5 / 4 + 32) * 1024 * 1024 )) ] ||
	die "image size $((root_bytes / 1024 / 1024)) MiB cannot hold a $used_mb MiB tree"
home_bytes=0
[ -z "$home_size" ] || home_bytes=$(to_bytes "$home_size")
[ "$home_bytes" = 0 ] || [ "$home_bytes" -ge $((16 * 1024 * 1024)) ] ||
	die '--home-size is implausibly small'
avail_mb=$(df -Pm "$out_dir" | awk 'NR == 2 { print $4 }')
[ "$avail_mb" -ge $((used_mb + 256)) ] ||
	die "not enough space in $out_dir: ${avail_mb} MiB free, ${used_mb} MiB tree"

say "root:       $used_mb MiB, $module_count modules of $release"
say "image:      $((root_bytes / 1024 / 1024)) MiB ext4, LABEL=LIUQIN_ROOT"
[ "$home_bytes" = 0 ] || say "home:       $((home_bytes / 1024 / 1024)) MiB ext4, LABEL=LIUQIN_HOME"

if [ "$check_only" = 1 ]; then
	say "check PASS: $tree"
	exit 0
fi

# --- write and verify -------------------------------------------------------

write_image() {
	image=$1
	bytes=$2
	label=$3
	say "formatting: $image"
	rm -f "$image"
	truncate -s "$bytes" "$image"
	if [ "$label" = LIUQIN_ROOT ]; then
		"$mke2fs_bin" -q -F -t ext4 -L LIUQIN_ROOT -m 0 \
			-E lazy_itable_init=0,lazy_journal_init=0 -d "$work" "$image" ||
			die "mke2fs failed: $image"
	else
		"$mke2fs_bin" -q -F -t ext4 -L "$label" -m 0 \
			-E lazy_itable_init=0,lazy_journal_init=0 "$image" ||
			die "mke2fs failed: $image"
	fi
	"$e2fsck_bin" -fn "$image" >/dev/null 2>&1 ||
		{ "$e2fsck_bin" -fn "$image" || true; die "e2fsck rejected $image"; }
	[ "$("$dumpe2fs_bin" -h "$image" 2>/dev/null | sed -n 's/^Filesystem volume name: *//p')" = "$label" ] ||
		die "image label is not $label: $image"
}

write_image "$rootfs_img" "$root_bytes" LIUQIN_ROOT
"$debugfs_bin" -R 'stat /native-root/etc/liuqin-native-root' "$rootfs_img" 2>/dev/null |
	grep -q 'Type: regular' || die 'rootfs.img does not contain native-root/'
"$debugfs_bin" -R "stat /native-root/usr/lib/modules/$release" "$rootfs_img" 2>/dev/null |
	grep -q 'Type: directory' || die 'rootfs.img does not contain the kernel modules'

if [ "$home_bytes" != 0 ]; then
	write_image "$home_img" "$home_bytes" LIUQIN_HOME
elif [ -f "$home_img" ]; then
	rm -f "$home_img"
	say 'removed stale linux_home.img (this run did not ask for one)'
fi

(
	cd "$out_dir"
	set -- rootfs.img
	[ "$home_bytes" = 0 ] || set -- "$@" linux_home.img
	sha256sum "$@" >SHA256SUMS
)

say "rootfs:     $rootfs_img ($(stat -c '%s' "$rootfs_img") bytes, sha256 $(sha "$rootfs_img" | cut -c1-16)...)"
[ "$home_bytes" = 0 ] ||
	say "home:       $home_img ($(stat -c '%s' "$home_img") bytes, sha256 $(sha "$home_img" | cut -c1-16)...)"
say 'next (flashing host):'
say '  fastboot flash boot_a   <bundle>/boot.img'
say "  fastboot flash linux_root $rootfs_img"
[ "$home_bytes" = 0 ] || say "  fastboot flash linux_home $home_img   # clean install only, wipes /home"
say 'grow the filesystem to the whole partition later: resize2fs /dev/disk/by-partlabel/linux_root'
