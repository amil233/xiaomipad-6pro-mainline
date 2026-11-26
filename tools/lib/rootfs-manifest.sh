#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 写一棵目录树的清单：每个文件一行，内容是哈希、类型、权限、属主和路径。
# 只读，不改树。行格式和 Ubuntu 线的 rootfs.manifest 一致，方便以后对比。
#
#   . tools/lib/rootfs-manifest.sh
#   write_tree_manifest ROOT MANIFEST
#
# 清单必须由真正的 root 写：树里有普通用户读不到的目录（例如 /root），
# 权限不足会悄悄少一大截，清单看起来正常但其实是错的。

die_manifest() { printf 'rootfs-manifest: %s\n' "$*" >&2; exit 1; }

write_tree_manifest() { # ROOT MANIFEST
	root=$1
	manifest=$2
	[ -d "$root" ] || die_manifest "tree is not a directory: $root"
	paths=$manifest.paths
	tmp=$manifest.tmp
	(cd "$root" && find . -printf '%y %m %u:%g %p\n') >"$paths" ||
		die_manifest 'find over the tree failed; refusing a truncated manifest'
	LC_ALL=C sort -k4 "$paths" >"$paths.sorted"
	mv "$paths.sorted" "$paths"
	: >"$tmp"
	while IFS= read -r line; do
		type=${line%% *}
		rest=${line#* }
		path=${rest#* }
		path=${path#* }
		case $type in
		f)
			printf '%s  %s\n' \
				"$(cd "$root" && sha256sum "$path" | cut -d' ' -f1)" "$line" >>"$tmp" ||
				die_manifest "sha256 failed for $path" ;;
		*)
			printf '%s  %s\n' '-' "$line" >>"$tmp" ;;
		esac
	done <"$paths"
	rm -f "$paths"
	entries=$(wc -l <"$tmp" | tr -d ' ')
	[ "$entries" -ge 1000 ] ||
		die_manifest "manifest is implausibly small: $entries entries"
	mv "$tmp" "$manifest"
	chmod 0644 "$manifest"
	printf 'tree manifest: %s (%s entries)\n' "$manifest" "$entries"
	sha256sum "$manifest"
}
