#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 从 Fedora KDE Plasma Mobile 的 Live ISO 里取出根文件系统。
#
# Fedora 45 的 aarch64 有两份产物：Live ISO（2.5 GiB）和 Disk 镜像（raw.xz，
# 里面是 btrfs 的根）。我们用 Live ISO：里面的根是 ext4，和现在 Ubuntu 线的
# casper 路线是同一个思路，拿到手就能直接当 ext4 根用，不用动 initramfs。
#
# ISO 里的结构：文件还是叫 `LiveOS/squashfs.img`，但 Fedora 42 起里面换成了
# EROFS（比 squashfs 压缩率更好）。再往里通常是一个 ext4 的 `LiveOS/rootfs.img`，
# 挂上就是完整的根；如果里面没有这个镜像，那解出来的这棵树本身就是根。
# 两种都处理，格式靠魔数判断，不靠文件名。
#
# 用法：
#   sudo tools/build-liuqin-fedora-base.sh download   # 下载并核对 ISO
#   sudo tools/build-liuqin-fedora-base.sh verify     # 只核对已有的 ISO
#   sudo tools/build-liuqin-fedora-base.sh extract    # 解出根目录树 + 清单
#   sudo tools/build-liuqin-fedora-base.sh manifest   # 只重写清单
#   sudo tools/build-liuqin-fedora-base.sh report     # 打印这棵树的情况
#   sudo tools/build-liuqin-fedora-base.sh all        # download + extract + report
#
# 可选的环境变量（都有默认值）：
#   FEDORA_BASE_DIR     放 ISO 和根目录树的地方
#   FEDORA_ISO_NAME     ISO 文件名
#   FEDORA_ISO_URL      ISO 下载地址
#   FEDORA_CHECKSUM_NAME  官方校验文件名
#   FEDORA_ROOT         解出来的根目录
#   FEDORA_MANIFEST     清单文件
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
base_dir=${FEDORA_BASE_DIR:-"$project_root/tools/local/fedora-kde-mobile-45-arm64"}
iso_name=${FEDORA_ISO_NAME:-Fedora-KDE-Mobile-Live-45-1.4.aarch64.iso}
iso_url=${FEDORA_ISO_URL:-https://dl.fedoraproject.org/pub/fedora/linux/releases/45/Spins/aarch64/iso/$iso_name}
checksum_name=${FEDORA_CHECKSUM_NAME:-Fedora-Spins-45-1.4-aarch64-CHECKSUM}
checksum_url=${iso_url%/*}/$checksum_name
iso=$base_dir/$iso_name
checksum_file=$base_dir/$checksum_name
root=${FEDORA_ROOT:-"$base_dir/rootfs"}
manifest=${FEDORA_MANIFEST:-"$base_dir/rootfs.manifest"}
work=$base_dir/work

die() { printf 'build-liuqin-fedora-base: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-fedora-base: %s\n' "$*"; }

usage() {
	cat <<'EOF'
usage: build-liuqin-fedora-base.sh download|verify|extract|manifest|report|all

  download   下载 Live ISO 和官方校验文件，核对之后才保留
  verify     只核对已有的 ISO
  extract    解开 ISO，把根目录树复制到 FEDORA_ROOT，并写出清单（需要 root）
  manifest   只重写清单（需要 root）
  report     打印包的个数、体积、关键包是否存在
  all        download + extract + report
EOF
}

# --- ISO --------------------------------------------------------------------

fetch_checksum() {
	mkdir -p "$base_dir"
	if command -v curl >/dev/null 2>&1; then
		curl --fail --silent --location --output "$checksum_file.part" "$checksum_url" &&
			mv "$checksum_file.part" "$checksum_file" && return 0
		rm -f "$checksum_file.part"
	fi
	[ -f "$checksum_file" ] ||
		die "cannot fetch $checksum_url and no cached copy at $checksum_file"
}

expected_sha256() {
	name=${iso##*/}
	hash=$(awk -v name="$name" '$1 == "SHA256" && $2 == "(" name ")" { print $4 }' "$checksum_file" | head -1)
	[ -n "$hash" ] || die "$checksum_file has no SHA256 entry for $name"
	printf '%s\n' "$hash" | tr 'A-F' 'a-f'
}

verify_iso() {
	[ -f "$iso" ] || die "ISO is unavailable: $iso"
	fetch_checksum
	want=$(expected_sha256) || exit 1
	printf '%s  %s\n' "$want" "$iso" | sha256sum -c --quiet - ||
		die "ISO sha256 does not match $checksum_name; do not use this file"
	say "ISO verified: $iso"
}

download_iso() {
	mkdir -p "$base_dir"
	exec 9>"$base_dir/.download.lock"
	flock -n 9 || die 'another ISO download owns this directory'
	if [ -f "$iso" ]; then
		verify_iso
		say 'using the cached ISO'
		return 0
	fi
	command -v curl >/dev/null || die 'curl is required'
	fetch_checksum
	curl --fail --location --continue-at - --output "$iso.part" "$iso_url" ||
		die "download failed: $iso_url"
	want=$(expected_sha256) || exit 1
	printf '%s  %s\n' "$want" "$iso.part" | sha256sum -c --quiet - ||
		die 'downloaded ISO does not match the official hash; remove the .part file before retrying'
	mv "$iso.part" "$iso"
	say "ISO downloaded and verified: $iso ($(stat -c %s "$iso") bytes)"
}

# --- 根目录树 ----------------------------------------------------------------

# 判断一个镜像文件是什么格式：只看魔数，不靠文件名。
image_kind() { # FILE
	kind_file=$1
	case $(head -c 4 "$kind_file" | od -An -tx1 2>/dev/null | tr -d ' \n') in
	68737173) echo squashfs; return 0 ;;
	1f8b*) echo gzip; return 0 ;;
	fd377a58) echo xz; return 0 ;;
	28b52ffd) echo zstd; return 0 ;;
	esac
	# EROFS 的魔数在 1024 字节处，ext2/3/4 的在 1080 字节处。
	[ "$(od -An -tx1 -j1024 -N4 "$kind_file" 2>/dev/null | tr -d ' \n')" = e2e1f5e0 ] &&
		{ echo erofs; return 0; }
	[ "$(od -An -tx1 -j1080 -N2 "$kind_file" 2>/dev/null | tr -d ' \n')" = 53ef ] &&
		{ echo ext4; return 0; }
	echo unknown
}

# 容器里那个文件系统镜像：优先按 Fedora 的固定位置找，找不到再在浅层找 *.img。
find_root_image() { # DIR
	find_dir=$1
	if [ -f "$find_dir/LiveOS/rootfs.img" ]; then
		printf '%s\n' "$find_dir/LiveOS/rootfs.img"
		return 0
	fi
	find "$find_dir" -maxdepth 2 -type f -name '*.img' | head -1
}

# 把一个镜像打开成一个目录：ext2/3/4 和 EROFS 用挂载，squashfs 用 unsquashfs。
# 结果放在 opened_dir；挂过的目录记进 open_mounts，退出时统一卸载。
open_image() { # IMAGE DIR
	open_file=$1
	open_dir=$2
	open_kind=$(image_kind "$open_file")
	case $open_kind in
	ext2 | ext3 | ext4)
		mkdir -p "$open_dir"
		mount -o loop,ro "$open_file" "$open_dir" ||
			die "cannot loop-mount $open_file (the runner needs loop device support)"
		open_mounts="$open_mounts $open_dir"
		;;
	erofs)
		mkdir -p "$open_dir"
		# 内核可能把 erofs 编成模块，先尝试加载再挂。
		modprobe erofs 2>/dev/null || :
		mount -o loop,ro -t erofs "$open_file" "$open_dir" ||
			die "cannot mount $open_file as EROFS (the runner kernel needs erofs support)"
		open_mounts="$open_mounts $open_dir"
		;;
	squashfs)
		unsquashfs -d "$open_dir" "$open_file" >/dev/null ||
			die "unsquashfs failed: $open_file"
		;;
	*)
		die "unexpected image format ($open_kind) in $open_file"
		;;
	esac
	opened_dir=$open_dir
}

# 复制整棵树，保留属主、权限、ACL 和 SELinux 标签。
copy_tree() { # SRC DEST
	tar -C "$1" --xattrs --xattrs-include='*' --acls --selinux -cf - . |
		tar -C "$2" --xattrs --xattrs-include='*' --acls --selinux -xpf - ||
		die 'copying the tree failed'
}

extract_root() {
	[ "$(id -u)" = 0 ] || die "extract must run as root (loop mount, ownership and labels)"
	verify_iso
	[ ! -e "$root" ] || die "refusing to overwrite an existing tree: $root"
	command -v 7z >/dev/null || die '7z is required (Ubuntu package: 7zip)'
	command -v unsquashfs >/dev/null || die 'unsquashfs is required (package: squashfs-tools)'
	command -v dumpe2fs >/dev/null || die 'dumpe2fs is required (package: e2fsprogs)'

	rm -rf "$work"
	mkdir -p "$work"
	open_mounts=
	cleanup_mounts() {
		for cleanup_dir in $open_mounts; do
			umount "$cleanup_dir" 2>/dev/null || :
		done
	}
	trap cleanup_mounts EXIT HUP INT TERM

	say 'extracting LiveOS/squashfs.img from the ISO'
	if ! 7z x -so "$iso" LiveOS/squashfs.img >"$work/live.img" 2>"$work/7z.log"; then
		say '7z could not read LiveOS/squashfs.img; paths in the ISO that look like it:'
		7z l "$iso" 2>/dev/null | grep -i 'squashfs\|rootfs\|erofs' | sed 's/^/  /' || true
		die 'unexpected ISO layout; the script needs updating'
	fi
	[ -s "$work/live.img" ] || die 'the image extracted from the ISO is empty'
	say "image inside the ISO: $(image_kind "$work/live.img") ($(stat -c %s "$work/live.img") bytes)"

	open_image "$work/live.img" "$work/inner"
	container=$opened_dir

	root_image=$(find_root_image "$container")
	if [ -n "$root_image" ]; then
		say "root filesystem image: $root_image ($(image_kind "$root_image"))"
		open_image "$root_image" "$work/mnt"
		source_tree=$opened_dir
	else
		# 没有内层镜像：打开的那棵树本身就是根。
		[ -f "$container/etc/os-release" ] ||
			die 'no root filesystem inside the ISO; the script needs updating'
		say 'the image itself is the root tree'
		source_tree=$container
	fi

	say 'copying the tree (keeping owners, permissions, ACLs and SELinux labels)'
	copy_tree "$source_tree" "$root"

	cleanup_mounts
	open_mounts=
	trap - EXIT HUP INT TERM

	[ -x "$root/usr/lib/systemd/systemd" ] || die "the copied tree has no systemd: $root"
	grep -q '^ID=fedora' "$root/etc/os-release" 2>/dev/null ||
		die 'the copied tree does not look like Fedora (no ID=fedora in os-release)'
	say "tree: $root"

	rm -f "$work/live.img"
	write_manifest
}

write_manifest() {
	[ "$(id -u)" = 0 ] || die "manifest must run as root (unreadable directories)"
	[ -d "$root" ] || die "tree is unavailable: $root"
	# shellcheck source=tools/lib/rootfs-manifest.sh
	. "$project_root/tools/lib/rootfs-manifest.sh"
	write_tree_manifest "$root" "$manifest"
}

# --- 报告 --------------------------------------------------------------------

report() {
	[ -d "$root" ] || die "tree is unavailable: $root"
	used_mb=$(du -sm --apparent-size "$root" | cut -f1)
	files=$(find "$root" -type f | wc -l | tr -d ' ')
	printf 'root tree:        %s\n' "$root"
	printf 'size:             %s MiB (files: %s)\n' "$used_mb" "$files"
	printf 'systemd:          %s\n' "$([ -x "$root/usr/lib/systemd/systemd" ] && echo yes || echo no)"
	printf 'os-release:       %s\n' "$(grep -h '^PRETTY_NAME=' "$root/etc/os-release" 2>/dev/null | cut -d= -f2- | tr -d '"')"
	printf 'kernel modules:   %s\n' "$(ls "$root/usr/lib/modules" 2>/dev/null | tr '\n' ' ')"
	printf 'selinux config:   %s\n' "$(grep -h '^SELINUX=' "$root/etc/selinux/config" 2>/dev/null || echo 'none')"
	printf 'selinux policy:   %s\n' "$([ -d "$root/etc/selinux/targeted" ] && echo present || echo missing)"

	if command -v rpm >/dev/null 2>&1; then
		printf 'packages:         %s\n' "$(rpm --root "$root" -qa 2>/dev/null | wc -l | tr -d ' ')"
		for pkg in plasma-mobile plasma-workspace plasma-setup sddm selinux-policy-targeted systemd; do
			if rpm --root "$root" -q "$pkg" >/dev/null 2>&1; then
				printf '  %-24s %s\n' "$pkg" "$(rpm --root "$root" -q "$pkg")"
			else
				printf '  %-24s %s\n' "$pkg" 'missing'
			fi
		done
	else
		printf 'packages:         rpm is not installed on this host, skipped\n'
	fi
}

case ${1:-} in
download) download_iso ;;
verify) verify_iso ;;
extract) extract_root ;;
manifest) write_manifest ;;
report) report ;;
all)
	download_iso
	extract_root
	report
	;;
-h | --help) usage; exit 0 ;;
'') usage; exit 1 ;;
*) die "unknown action: $1 (see --help)" ;;
esac
