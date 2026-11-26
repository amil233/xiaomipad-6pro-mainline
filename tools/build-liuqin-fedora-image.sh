#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 把整理好的 Fedora 根目录树做成 `fastboot flash userdata` 能写的 ext4 镜像。
#
# 布局和 Ubuntu 线一样：分区表不动，`userdata` 是唯一的数据分区，一个卷标
# LIUQIN_ROOT 的 ext4，树放在 native-root/ 下（initramfs 把这一层当 /）。
#
#   sudo sh tools/build-liuqin-fedora-image.sh --root DIR --out DIR [--size 8G]
#
# 镜像只做"树 + 25% 余量"，不要求等于分区大小；平板第一次启动后
# `resize2fs /dev/disk/by-partlabel/userdata` 长满整个分区。
set -eu

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin
export PATH

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
marker_text=liuqin-native-root-v1

die() { printf 'build-liuqin-fedora-image: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-fedora-image: %s\n' "$*"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

usage() {
	cat <<'EOF'
usage: build-liuqin-fedora-image.sh --root DIR --out DIR [--size 8G]

  --root DIR   assembled tree (the root the tablet will mount)
  --out DIR    where rootfs.img and SHA256SUMS are written
  --size SIZE  image size, e.g. 8G or 8192M; default: tree + 25%
EOF
}

tool() {
	command -v "$1" 2>/dev/null && return 0
	for candidate in /usr/sbin/"$1" /sbin/"$1" /usr/bin/"$1" /bin/"$1"; do
		[ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
	done
	return 1
}

to_mb() {
	case $1 in
	*[Gg]) printf '%s\n' "$(( ${1%?} * 1024 ))" ;;
	*[Mm]) printf '%s\n' "${1%?}" ;;
	*[Kk]) printf '%s\n' "$(( (${1%?} + 1023) / 1024 ))" ;;
	'' | *[!0-9]*) die "not a size: $1 (use 8G, 8192M, ...)" ;;
	*) printf '%s\n' "$1" ;;
	esac
}

root=
out_dir=
size=
while [ $# -gt 0 ]; do
	case $1 in
	--root) [ $# -ge 2 ] || die '--root needs a value'; root=$2; shift 2 ;;
	--out) [ $# -ge 2 ] || die '--out needs a value'; out_dir=$2; shift 2 ;;
	--size) [ $# -ge 2 ] || die '--size needs a value'; size=$2; shift 2 ;;
	-h | --help) usage; exit 0 ;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -n "$root" ] || die '--root is required'
[ -n "$out_dir" ] || die '--out is required'
[ -d "$root" ] || die "no tree at $root"
[ "$(id -u)" = 0 ] || die 'run as root (ownership, loop-free tree copy and mke2fs)'

# --- 树必须满足 initramfs 会检查的条件 --------------------------------------
[ -x "$root/usr/lib/systemd/systemd" ] || die "the tree has no systemd: $root"
marker=$root/etc/liuqin-native-root
[ -f "$marker" ] && [ ! -L "$marker" ] || die "no marker at $marker (run build-liuqin-fedora-rootfs.sh assemble)"
[ "$(cat "$marker")" = "$marker_text" ] || die "marker content mismatch: $marker"
release=$(cat "$root/usr/share/liuqin/kernel.release" 2>/dev/null || true)
[ -n "$release" ] || die 'the tree carries no /usr/share/liuqin/kernel.release'
[ -d "$root/usr/lib/modules/$release" ] || die "no module tree for $release"
[ -f "$root/usr/lib/modules/$release/modules.dep" ] || die "no modules.dep for $release"

for command in mke2fs e2fsck dumpe2fs debugfs; do
	eval "${command}_bin=\$(tool $command)" || die "$command is required (install e2fsprogs)"
done

# --- 尺寸 -------------------------------------------------------------------
used_mb=$(du -sm --apparent-size "$root" | cut -f1)
if [ -z "$size" ]; then
	root_mb=$(( used_mb * 125 / 100 + 512 ))
	[ "$root_mb" -ge 6144 ] || root_mb=6144
else
	root_mb=$(to_mb "$size")
fi
[ "$root_mb" -ge $(( used_mb + 64 )) ] || die "image size ${root_mb} MiB cannot hold a $used_mb MiB tree"
mkdir -p "$out_dir"
out_dir=$(CDPATH= cd -- "$out_dir" && pwd)
avail_mb=$(df -Pm "$out_dir" | awk 'NR == 2 { print $4 }')
[ "$avail_mb" -ge $((used_mb + 256)) ] ||
	die "not enough space in $out_dir: ${avail_mb} MiB free, ${used_mb} MiB tree"

say "root:   $used_mb MiB, release $release"
say "image:  ${root_mb} MiB ext4, LABEL=LIUQIN_ROOT"

# --- 装配 -------------------------------------------------------------------
rootfs_img=$out_dir/rootfs.img
work=$(mktemp -d "$out_dir/.image.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
say 'staging native-root/'
cp -a --reflink=auto "$root" "$work/native-root" 2>/dev/null ||
	cp -a "$root" "$work/native-root" || die 'could not stage the tree'

say 'formatting'
rm -f "$rootfs_img"
truncate -s "${root_mb}M" "$rootfs_img"
"$mke2fs_bin" -q -F -t ext4 -L LIUQIN_ROOT -m 0 \
	-E lazy_itable_init=0,lazy_journal_init=0 -d "$work" "$rootfs_img" ||
	die "mke2fs failed: $rootfs_img"
"$e2fsck_bin" -fn "$rootfs_img" >/dev/null 2>&1 ||
	{ "$e2fsck_bin" -fn "$rootfs_img" || true; die "e2fsck rejected $rootfs_img"; }
[ "$("$dumpe2fs_bin" -h "$rootfs_img" 2>/dev/null | sed -n 's/^Filesystem volume name: *//p')" = LIUQIN_ROOT ] ||
	die "image label is not LIUQIN_ROOT: $rootfs_img"
"$debugfs_bin" -R 'stat /native-root/etc/liuqin-native-root' "$rootfs_img" 2>/dev/null |
	grep -q 'Type: regular' || die 'the image does not contain native-root/etc/liuqin-native-root'
"$debugfs_bin" -R "stat /native-root/usr/lib/modules/$release" "$rootfs_img" 2>/dev/null |
	grep -q 'Type: directory' || die 'the image does not contain the kernel modules'

rm -rf "$work"
trap - EXIT HUP INT TERM
(
	cd "$out_dir"
	sha256sum rootfs.img >SHA256SUMS
)
say "rootfs: $rootfs_img ($(stat -c '%s' "$rootfs_img") bytes, sha256 $(sha "$rootfs_img" | cut -c1-16)...)"
say 'next: img2simg rootfs.img rootfs.simg, then flash boot_a and userdata'
