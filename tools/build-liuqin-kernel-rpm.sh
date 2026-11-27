#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 内核产物在 Fedora 上的形态：一个 RPM，装进 Fedora 的根目录树。
#
# 宿主机是 Ubuntu，没有 rpmbuild / rpm / dnf，所以这个脚本要在 Fedora 容器里
# 跑，由 tools/fedora-container.sh 负责起容器：
#
#   sh tools/fedora-container.sh \
#     'sh tools/build-liuqin-kernel-rpm.sh build install'
#
# 三个动作互相独立，可以只跑其中一个：
#
#   build    从内核 CI 产物打出一个 RPM（只要产物）
#   install  把 RPM 装进树里，先清掉 Fedora 自带的内核（只要 RPM 和树）
#   check    检查树里的内核模块、登记文件和 systemd（只要树）
#
# 可选环境变量：
#   KERNEL_DIR   内核产物目录；默认取 ci/ 下最新的 liuqin-kernel-*
#   OUT          RPM 输出目录；默认 out/fedora-rpm
#   TREE         Fedora 根目录树；默认 tools/local/fedora-kde-mobile-45-arm64/rootfs
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${OUT:-"$project_root/out/fedora-rpm"}
tree=${TREE:-"$project_root/tools/local/fedora-kde-mobile-45-arm64/rootfs"}
pkg_name=kernel-liuqin

die() { printf 'build-liuqin-kernel-rpm: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-kernel-rpm: %s\n' "$*"; }

usage() {
	cat <<'EOF'
usage: build-liuqin-kernel-rpm.sh ACTION...

  build    用内核 CI 产物打一个 kernel-liuqin RPM（需要 rpmbuild）
  install  清掉树里 Fedora 自带的内核，把 RPM 装进去（需要 rpm）
  check    检查树里内核模块、登记文件和 systemd

多个动作按顺序执行，例如 `build install`。所有动作都能重复跑。
EOF
}

need() { # 工具名 用途
	command -v "$1" >/dev/null 2>&1 || die "$1 is missing ($2); run this through tools/fedora-container.sh"
}

# --- 产物 --------------------------------------------------------------------

artifact_release() {
	# 产物的一致性检查用 python3 读 build-info.json，容器里默认没有它。
	need python3 'the kernel artifact check needs it'
	# shellcheck source=tools/lib/kernel-artifact.sh
	. "$project_root/tools/lib/kernel-artifact.sh"
	resolve_kernel_artifact "$project_root" "$project_root" "${KERNEL_DIR:-}" || die \
		'no consistent kernel artifact (copy one from CI into ci/, or set KERNEL_DIR)'
	release=$(cat "$MODULES_DIR/kernel.release")
	case $release in
	'' | *[!A-Za-z0-9._+-]*) die "unsafe kernel release: $release" ;;
	esac
	say "kernel artifact: $ARTIFACT"
	say "kernel release:  $release"
	modules_dir=$MODULES_DIR
}

rpm_release() {
	# shellcheck disable=SC2012
	rpm_file=$(ls -t "$out_dir"/$pkg_name-*.aarch64.rpm 2>/dev/null | head -1)
	[ -n "$rpm_file" ] || die "no RPM in $out_dir; run the build action first"
	release=$(rpm -qp --provides "$rpm_file" 2>/dev/null |
		sed -n 's/^kernel-uname-r = //p' | head -1)
	[ -n "$release" ] || die "cannot read the kernel release from $rpm_file"
}

# --- build -------------------------------------------------------------------

build_rpm() {
	need rpmbuild 'packaging'
	artifact_release

	# RPM 的 Version 和 Release 里都不能有 '-'，把 7.3.0-g<sha> 拆成两段。
	base=${release%%-*}
	if [ "$base" = "$release" ]; then
		extra=local
	else
		extra=${release#*-}
	fi

	stage=$out_dir/stage
	# 只清自己这次的中间产物：OUT 目录里可能还有另一个包。
	rm -rf "$out_dir/stage" "$out_dir/rpmbuild" "$out_dir/$pkg.spec"
	rm -f "$out_dir/$pkg-"*.aarch64.rpm
	mkdir -p "$stage"
	tar --extract --file "$modules_dir/modules.tar" --directory "$stage" --no-same-owner
	[ -f "$stage/usr/lib/modules/$release/modules.dep" ] ||
		die "the module tree has no $release/modules.dep"
	mkdir -p "$stage/usr/share/liuqin"
	cp "$modules_dir/kernel.release" "$stage/usr/share/liuqin/kernel.release"
	cp "$modules_dir/modules.manifest" "$stage/usr/share/liuqin/kernel-modules.manifest"
	chmod 0644 "$stage/usr/share/liuqin/kernel.release" \
		"$stage/usr/share/liuqin/kernel-modules.manifest"
	say "modules in the payload: $(find "$stage/usr/lib/modules/$release" -name '*.ko*' -type f | wc -l | tr -d ' ')"

	spec=$out_dir/$pkg_name.spec
	cat >"$spec" <<EOF
%define debug_package %{nil}
%define __strip /bin/true
%define __objcopy /bin/true
%define _build_id_links none

Name:           $pkg_name
Version:        $base
Release:        0.1.$extra
Summary:        Xiaomi Pad 6 Pro (liuqin) kernel modules
License:        GPL-2.0-only
BuildArch:      aarch64
AutoReqProv:    no
Provides:       kernel-uname-r = $release
%description
Kernel modules and the release marker for the Xiaomi Pad 6 Pro (liuqin).
The kernel image itself is flashed separately as boot.img; this package only
puts the matching modules and /usr/share/liuqin/kernel.release on the system.
%install
mkdir -p %{buildroot}
cp -a $stage/. %{buildroot}/
%files
/usr/lib/modules/$release
/usr/share/liuqin/kernel.release
/usr/share/liuqin/kernel-modules.manifest
EOF

	say "building $pkg_name-$base-0.1.$extra.aarch64.rpm"
	rpmbuild -bb --quiet \
		--define "_topdir $out_dir/rpmbuild" \
		"$spec" >"$out_dir/rpmbuild.log" 2>&1 ||
		{ tail -40 "$out_dir/rpmbuild.log" >&2; die 'rpmbuild failed'; }
	mv "$out_dir/rpmbuild/RPMS/aarch64/$pkg_name-$base-0.1.$extra.aarch64.rpm" "$out_dir/" ||
		die 'rpmbuild reported success but produced no RPM'
	rm -rf "$out_dir/stage" "$out_dir/rpmbuild" "$out_dir/$pkg_name.spec"
	say "rpm: $out_dir/$pkg_name-$base-0.1.$extra.aarch64.rpm"
}

# --- install -----------------------------------------------------------------

prune_fedora_kernel() { # RELEASE
	prune_release=$1
	# Fedora 自带的内核包在安装/卸载时会跑 kernel-install 和 dracut、往 /boot
	# 写东西；这里只是把它们从树里拿掉，所以脚本一律不执行。
	old=$(rpm --root "$tree" -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null |
		grep -E '^kernel(-|\.)' | grep -v "^$pkg_name-" || true)
	if [ -n "$old" ]; then
		say 'removing the Fedora kernel packages:'
		printf '%s\n' "$old" | sed 's/^/  /'
		for pkg in $old; do
			rpm --root "$tree" -e --noscripts --nodeps "$pkg" >/dev/null 2>&1 || :
		done
	fi
	# /boot 里是 Fedora 的内核、initramfs 和引导项，我们用不到：内核从 boot.img
	# 启动，模块在 /usr/lib/modules 下。
	rm -rf "$tree"/boot/* 2>/dev/null || :
	for dir in "$tree"/usr/lib/modules/*; do
		[ -d "$dir" ] || continue
		[ "$(basename "$dir")" = "$prune_release" ] || {
			say "removing stale module tree: $dir"
			rm -rf "$dir"
		}
	done
}

install_into_tree() {
	need rpm 'installing'
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	rpm_release
	say "installing into $tree (release $release)"
	prune_fedora_kernel "$release"
	# --nosignature: 包是我们自己打的，没有签名，Fedora 的 rpm 默认要求校验。
	# --replacepkgs: 重复跑这个动作时覆盖已装的同名同版本包。
	rpm --root "$tree" -U --replacepkgs --noscripts --nosignature --nodeps "$rpm_file" ||
		die 'rpm could not install the package'
	check_tree
}

# --- check -------------------------------------------------------------------

check_tree() {
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	marker=$tree/usr/share/liuqin/kernel.release
	[ -f "$marker" ] || die "the tree carries no $marker"
	recorded=$(cat "$marker")
	[ -d "$tree/usr/lib/modules/$recorded" ] || die "no module tree for $recorded"
	[ -f "$tree/usr/lib/modules/$recorded/modules.dep" ] || die "no modules.dep for $recorded"
	[ -x "$tree/usr/lib/systemd/systemd" ] || die 'the tree has no systemd'
	modules=$(find "$tree/usr/lib/modules/$recorded" -name '*.ko*' -type f | wc -l | tr -d ' ')
	[ "$modules" -ge 1 ] || die 'the module tree is empty'
	say "tree: $tree"
	say "release: $recorded; modules: $modules; size: $(du -sm --apparent-size "$tree" | cut -f1) MiB"
	say "package: $(rpm --root "$tree" -q $pkg_name 2>/dev/null || echo 'not installed')"
}

# --- 入口 --------------------------------------------------------------------

[ $# -ge 1 ] || { usage; exit 1; }
for action in "$@"; do
	case $action in
	build) build_rpm ;;
	install) install_into_tree ;;
	check) check_tree ;;
	-h | --help) usage; exit 0 ;;
	*) die "unknown action: $action (see --help)" ;;
	esac
done
