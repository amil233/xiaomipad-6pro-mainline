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
#
# 实现上分两批：元数据一次 find，哈希一次 sha256sum（xargs 分批，一次几百个
# 文件），最后用 python 拼起来。早先的写法是"每个文件 fork 一次 sha256sum"，
# 13 万个文件要跑将近十分钟，是 Report 步骤慢的全部原因。

die_manifest() { printf 'rootfs-manifest: %s\n' "$*" >&2; exit 1; }

write_tree_manifest() { # ROOT MANIFEST
	root=$1
	manifest=$2
	[ -d "$root" ] || die_manifest "tree is not a directory: $root"
	work=$(mktemp -d) || die_manifest 'cannot create a scratch directory'
	trap 'rm -rf "$work"' EXIT HUP INT TERM

	( cd "$root" && find . -printf '%y %m %u:%g %p\0' ) >"$work/meta" || {
		rm -rf "$work"
		die_manifest 'find over the tree failed; refusing a truncated manifest'
	}
	( cd "$root" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum -z ) \
		>"$work/hashes" || {
		rm -rf "$work"
		die_manifest 'hashing the tree failed'
	}

	python3 - "$work/meta" "$work/hashes" "$manifest" <<'PY' || {
import sys
from pathlib import Path

meta_path, hash_path, out_path = (Path(p) for p in sys.argv[1:4])
digests = {}
for record in hash_path.read_bytes().split(b'\0'):
    if not record:
        continue
    digest, name = record.split(b'  ', 1)
    digests[name.decode()] = digest.decode()

rows = []
for record in meta_path.read_bytes().split(b'\0'):
    if not record:
        continue
    fields = record.decode().split(' ', 3)
    if len(fields) != 4:
        raise SystemExit('malformed metadata record')
    kind, mode, owner, name = fields
    digest = digests.get(name, '-')
    rows.append('%s  %s %s %s %s' % (digest, kind, mode, owner, name))

if len(rows) < 1000:
    raise SystemExit('implausibly small manifest')
out_path.write_text('\n'.join(rows) + '\n')
print('tree manifest: %s (%d entries)' % (out_path, len(rows)))
PY
		rm -rf "$work"
		die_manifest 'writing the manifest failed'
	}
	rm -rf "$work"
	trap - EXIT HUP INT TERM
	chmod 0644 "$manifest"
	sha256sum "$manifest"
}
