#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 把 Fedora 的根目录树整理成 liuqin 能启动的根，并写出它的清单和哈希表。
#
# 树来自 Live ISO（ext4 的 EROFS 根），已经装好了我们的内核包。这里只做三件
# 发行版层面必须做的事，其余一律不动、只报告：
#
#   1. 写 liuqin 的根标记文件（initramfs 靠它认根）
#   2. 清掉 machine-id，让每台机器第一次启动时自己生成
#   3. SELinux 从 enforcing 改成 permissive（标签没打全之前，先不拦）
#
# 另外把树的哈希表写出来：build-liuqin-native-boot.sh 要用它生成 initramfs
# 里的准入清单，并核对树的 kernel.release 和内核产物是否同一次构建。
#
#   sudo sh tools/build-liuqin-fedora-rootfs.sh assemble   # 整理树 + 写哈希表
#   sudo sh tools/build-liuqin-fedora-rootfs.sh hashes     # 只重写哈希表
#   sudo sh tools/build-liuqin-fedora-rootfs.sh report     # 打印树里的关键事实
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tree=${TREE:-"$project_root/tools/local/fedora-kde-mobile-45-arm64/rootfs"}
out=${OUT:-"$project_root/tools/local/fedora-kde-mobile-45-arm64"}
hashes_file=${HASHES:-"$out/native-root.hashes"}
marker_text=liuqin-native-root-v1

die() { printf 'build-liuqin-fedora-rootfs: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-fedora-rootfs: %s\n' "$*"; }

usage() {
	cat <<'EOF'
usage: build-liuqin-fedora-rootfs.sh assemble|hashes|report

  assemble  整理树（根标记、machine-id、SELinux），然后写哈希表
  hashes    只重写 native-root.hashes
  report    打印树里的用户、登录管理器、fstab、SELinux 等情况
EOF
}

check_tree() {
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	[ -x "$tree/usr/lib/systemd/systemd" ] || die "the tree has no systemd: $tree"
	grep -q '^ID=fedora' "$tree/etc/os-release" 2>/dev/null ||
		die 'the tree does not look like Fedora (no ID=fedora in os-release)'
	[ -f "$tree/usr/share/liuqin/kernel.release" ] ||
		die 'the tree carries no /usr/share/liuqin/kernel.release; install the kernel package first'
}

# --- 整理 --------------------------------------------------------------------

assemble_tree() {
	check_tree
	release=$(cat "$tree/usr/share/liuqin/kernel.release")
	[ -d "$tree/usr/lib/modules/$release" ] || die "no module tree for $release"

	# 根标记：initramfs 只认这个文件的内容和权限。
	printf '%s\n' "$marker_text" >"$tree/etc/liuqin-native-root"
	chown 0:0 "$tree/etc/liuqin-native-root"
	chmod 0644 "$tree/etc/liuqin-native-root"
	say "root marker: $marker_text"

	# machine-id：留空，第一次启动时由 systemd 生成；随机种子也一起清掉。
	mkdir -p "$tree/etc"
	: >"$tree/etc/machine-id"
	chown 0:0 "$tree/etc/machine-id"
	chmod 0444 "$tree/etc/machine-id"
	rm -f "$tree/var/lib/systemd/random-seed"
	say 'machine-id: emptied'

	# fastrpc 账户：设备节点由内核建（/dev/fastrpc-*），但 hexagonrpcd 要以这个
	# 用户运行，provision 脚本也按这个名字查 uid。离线建号，不依赖 RPM 的脚本。
	ensure_fastrpc_account

	# SELinux：第一次启动先 permissive，标签和策略后面再收紧。
	if [ -f "$tree/etc/selinux/config" ]; then
		sed -i 's/^SELINUX=.*/SELINUX=permissive/' "$tree/etc/selinux/config"
		grep -qx 'SELINUX=permissive' "$tree/etc/selinux/config" ||
			die 'could not set SELINUX=permissive'
		say 'selinux: permissive'
	else
		say 'selinux: no /etc/selinux/config, left alone'
	fi

	write_hashes
}

ensure_fastrpc_account() {
	grep -q '^fastrpc:' "$tree/etc/group" && grep -q '^fastrpc:' "$tree/etc/passwd" && return 0
	# Fedora 的系统号段是 201–999，而且这套镜像已经用掉不少，所以从 999 往下
	# 找第一个空位，而不是"最大的加一"。
	pick_free_id() { # FILE
		for candidate in $(seq 999 -1 201); do
			awk -F: -v id="$candidate" '$3 == id { found = 1 } END { exit !found }' "$1" ||
				{ printf '%s\n' "$candidate"; return 0; }
		done
		return 1
	}
	uid=$(pick_free_id "$tree/etc/passwd") || die 'no free system uid for fastrpc'
	gid=$(pick_free_id "$tree/etc/group") || die 'no free system gid for fastrpc'
	if ! grep -q "^fastrpc:" "$tree/etc/group"; then
		printf 'fastrpc:x:%s:\n' "$gid" >>"$tree/etc/group"
	fi
	if ! grep -q "^fastrpc:" "$tree/etc/passwd"; then
		printf 'fastrpc:x:%s:%s::/var/lib/hexagonrpcd:/usr/sbin/nologin\n' "$uid" "$gid" \
			>>"$tree/etc/passwd"
	fi
	if [ -f "$tree/etc/shadow" ] && ! grep -q '^fastrpc:' "$tree/etc/shadow"; then
		printf 'fastrpc:*:19000:0:99999:7:::\n' >>"$tree/etc/shadow"
	fi
	mkdir -p "$tree/var/lib/hexagonrpcd"
	chown "$uid:$gid" "$tree/var/lib/hexagonrpcd"
	chmod 0750 "$tree/var/lib/hexagonrpcd"
	say "fastrpc account: uid=$uid gid=$gid"
}

# --- 哈希表 ------------------------------------------------------------------

write_hashes() {
	check_tree
	[ "$(id -u)" = 0 ] || die 'hashes must run as root (unreadable directories)'
	work=$(mktemp -d)
	trap 'rm -rf "$work"' EXIT HUP INT TERM
	( cd "$tree" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum -z ) >"$work/filehashes" ||
		die 'hashing the tree failed'
	python3 - "$work/filehashes" "$hashes_file" <<'PY' || die 'writing the hash list failed'
import sys
from pathlib import Path
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
out = []
for record in src.read_bytes().split(b'\0'):
    if not record:
        continue
    digest, path = record.split(b'  ', 1)
    name = path.decode()
    if name.startswith('./'):
        name = name[2:]
    out.append(digest.decode() + '  /' + name)
if len(out) < 1000:
    raise SystemExit('implausibly small hash list')
dst.write_text('\n'.join(sorted(out)) + '\n')
print('hash list: %s (%d files)' % (dst, len(out)))
PY
	chmod 0644 "$hashes_file"
	rm -rf "$work"
	trap - EXIT HUP INT TERM
	sha256sum "$hashes_file"
}

# --- 报告 --------------------------------------------------------------------

report() {
	check_tree
	release=$(cat "$tree/usr/share/liuqin/kernel.release")
	printf 'tree:            %s\n' "$tree"
	printf 'size:            %s MiB\n' "$(du -sm --apparent-size "$tree" | cut -f1)"
	printf 'kernel release:  %s\n' "$release"
	printf 'modules:         %s\n' "$(find "$tree/usr/lib/modules/$release" -name '*.ko*' -type f | wc -l | tr -d ' ')"
	printf 'os-release:      %s\n' "$(grep -h '^PRETTY_NAME=' "$tree/etc/os-release" | cut -d= -f2- | tr -d '"')"
	printf 'selinux:         %s\n' "$(grep -h '^SELINUX=' "$tree/etc/selinux/config" 2>/dev/null || echo none)"
	printf 'machine-id:      %s bytes%s\n' \
		"$(stat -c %s "$tree/etc/machine-id" 2>/dev/null || echo missing)" \
		"$([ -f "$tree/etc/liuqin-native-root" ] && echo ', liuqin marker present')"

	# 人类账户：第一次启动要么用它，要么让首次设置去建。
	printf 'human users:     %s\n' \
		"$(awk -F: '$3 >= 1000 && $3 < 60000 { printf "%s(uid %s, home %s) ", $1, $3, $6 }' "$tree/etc/passwd" 2>/dev/null)"
	printf 'login manager:   %s\n' \
		"$(for u in plasmalogin sddm gdm lightdm; do [ -e "$tree/usr/lib/systemd/system/$u.service" ] && printf '%s ' "$u"; done)"
	printf 'plasma-setup:    %s\n' \
		"$([ -e "$tree/usr/lib/systemd/system/plasma-setup.service" ] && echo present || echo missing)"
	printf 'plasma-setup on: %s\n' \
		"$([ -L "$tree/etc/systemd/system/multi-user.target.wants/plasma-setup.service" ] && echo enabled || echo not-enabled)"
	printf 'fstab:           %s\n' \
		"$([ -f "$tree/etc/fstab" ] && tr '\n' ' ' <"$tree/etc/fstab" || echo missing)"
	printf 'autologin files: %s\n' \
		"$(grep -rl 'Autologin\|autologin' "$tree/etc/plasmalogin.conf" "$tree/etc/plasmalogin.conf.d" \
			"$tree/etc/sysconfig/plasmalogin" 2>/dev/null | tr '\n' ' ')"
	printf 'default target:  %s\n' "$(readlink "$tree/etc/systemd/system/default.target" 2>/dev/null || echo none)"
	printf 'enabled units:   %s\n' \
		"$(find "$tree/etc/systemd/system" -name '*.wants' -o -name '*.requires' 2>/dev/null |
			xargs -r ls 2>/dev/null | wc -l | tr -d ' ')"
	printf 'firmware files:  %s\n' "$(find "$tree/usr/lib/firmware" -type f 2>/dev/null | wc -l | tr -d ' ')"
}

case ${1:-} in
assemble) assemble_tree ;;
hashes) write_hashes ;;
report) report ;;
-h | --help) usage; exit 0 ;;
'') usage; exit 1 ;;
*) die "unknown action: $1 (see --help)" ;;
esac
