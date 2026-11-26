#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 把内核 CI 的产物打成一个 RPM，再装进 Fedora 的根目录树。
#
# 这个脚本要在 Fedora 容器里跑（`docker run ... fedora:45`）：宿主机是
# Ubuntu，没有 rpmbuild/dnf/rpm，而 GitHub Actions 也没有 Fedora 的 runner，
# 用官方 aarch64 镜像起一个容器就够，不需要虚拟机。
#
#   sh tools/build-liuqin-kernel-rpm.sh build     # 出 RPM
#   sh tools/build-liuqin-kernel-rpm.sh install   # 删掉 Fedora 自带内核，装我们的，检查
#   sh tools/build-liuqin-kernel-rpm.sh check     # 只检查已装好的树
#
# 可选环境变量：
#   KERNEL_DIR   内核产物目录（默认取 ci/ 里最新的 liuqin-kernel-*）
#   OUT          输出目录（默认 out/fedora-rpm）
#   TREE         Fedora 的根目录树（默认 tools/local/fedora-kde-mobile-45-arm64/rootfs）
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workspace_root=$project_root
out_dir=${OUT:-"$project_root/out/fedora-rpm"}
tree=${TREE:-"$project_root/tools/local/fedora-kde-mobile-45-arm64/rootfs"}
pkg_name=kernel-liuqin

die() { printf 'build-liuqin-kernel-rpm: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-kernel-rpm: %s\n' "$*"; }

usage() {
	cat <<'EOF'
usage: build-liuqin-kernel-rpm.sh build|install|check

  build    用内核 CI 产物打一个 kernel-liuqin RPM（需要 rpmbuild）
  install  从树里删掉 Fedora 自带的内核包和 /boot 内容，装我们的 RPM（需要 rpm）
  check    检查树里内核模块和登记文件是否齐全
EOF
}

# --- 输入 --------------------------------------------------------------------

# shellcheck source=tools/lib/kernel-artifact.sh
. "$project_root/tools/lib/kernel-artifact.sh"

resolve_inputs() {
	requested=${KERNEL_DIR:-}
	resolve_kernel_artifact "$project_root" "$workspace_root" "$requested" || {
		die 'no consistent kernel artifact (copy one from CI into ci/, or set KERNEL_DIR)'
	}
	release=$(cat "$MODULES_DIR/kernel.release")
	case $release in
	'' | *[!A-Za-z0-9._+-]*) die "unsafe kernel release: $release" ;;
	esac
	# RPM 的 Version 和 Release 里不能有 '-'，把 release 拆成两段。
	base=${release%%-*}
	if [ "$base" = "$release" ]; then
		extra=local
	else
		extra=${release#*-}
	fi
	say "kernel artifact: $ARTIFACT"
	say "kernel release:  $release"
}

# --- build -------------------------------------------------------------------

build_rpm() {
	command -v rpmbuild >/dev/null || die 'rpmbuild is missing; run this inside fedora:45'
	resolve_inputs

	stage=$out_dir/stage
	rm -rf "$out_dir"
	mkdir -p "$stage"
	tar --extract --file "$MODULES_DIR/modules.tar" --directory "$stage" --no-same-owner
	[ -d "$stage/usr/lib/modules/$release" ] ||
		die "module tree has no $release"
	[ -f "$stage/usr/lib/modules/$release/modules.dep" ] ||
		die 'module tree carries no dependency index'
	mkdir -p "$stage/usr/share/liuqin"
	cp "$MODULES_DIR/kernel.release" "$stage/usr/share/liuqin/kernel.release"
	cp "$MODULES_DIR/modules.manifest" "$stage/usr/share/liuqin/kernel-modules.manifest"
	chmod 0644 "$stage/usr/share/liuqin/kernel.release" \
		"$stage/usr/share/liuqin/kernel-modules.manifest"

	modules=$(find "$stage/usr/lib/modules/$release" -name '*.ko*' -type f | wc -l | tr -d ' ')
	say "modules in the payload: $modules"

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
Obsoletes:      liuqin-kernel
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
%post
exit 0
EOF

	say "building $pkg_name-$base-0.1.$extra.aarch64.rpm"
	rpmbuild -bb --quiet \
		--define "_topdir $out_dir/rpmbuild" \
		--define "_rpmdir $out_dir/rpmbuild/RPMS" \
		"$spec" >"$out_dir/rpmbuild.log" 2>&1 ||
		{ tail -30 "$out_dir/rpmbuild.log"; die 'rpmbuild failed'; }
	rpm_file=$out_dir/rpmbuild/RPMS/aarch64/$pkg_name-$base-0.1.$extra.aarch64.rpm
	[ -f "$rpm_file" ] || die "rpmbuild produced no $rpm_file"
	mv "$rpm_file" "$out_dir/"
	rm -rf "$out_dir/stage" "$out_dir/rpmbuild" "$out_dir/$pkg_name.spec"
	say "rpm: $out_dir/$pkg_name-$base-0.1.$extra.aarch64.rpm"
	rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH} (%{SIZE} bytes)\n' \
		"$out_dir/$pkg_name-$base-0.1.$extra.aarch64.rpm"
}

# --- install -----------------------------------------------------------------

find_fedora_kernel_packages() {
	rpm --root "$tree" -qa --qf '%{NAME}\n' 2>/dev/null |
		grep -E '^kernel(-|$)' | grep -v "^$pkg_name$" | sort -u
}

install_into_tree() {
	command -v rpm >/dev/null || die 'rpm is missing; run this inside fedora:45'
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	resolve_inputs

	rpm_file=$(ls "$out_dir"/$pkg_name-*.aarch64.rpm 2>/dev/null | head -1)
	[ -n "$rpm_file" ] || die "no RPM in $out_dir; run the build action first"

	old=$(find_fedora_kernel_packages)
	if [ -n "$old" ]; then
		say 'removing Fedora own kernel packages:'
		printf '%s\n' "$old" | sed 's/^/  /'
		# 这些包的安装脚本会去写 /boot、跑 dracut 和 kernel-install，这里只是
		# 删除文件，不需要它们执行。
		for pkg in $old; do
			rpm --root "$tree" -e --noscripts --nodeps "$pkg" >/dev/null 2>&1 || :
		done
	else
		say 'no Fedora kernel packages found'
	fi
	rm -rf "$tree"/boot/*
	# 删掉不属于我们这个 release 的模块目录（Fedora 自带的那份）。
	for dir in "$tree"/usr/lib/modules/*; do
		[ -d "$dir" ] || continue
		[ "$(basename "$dir")" = "$release" ] || {
			say "removing stale module tree: $dir"
			rm -rf "$dir"
		}
	done

	say "installing $rpm_file"
	rpm --root "$tree" -i --noscripts --nodeps "$rpm_file" ||
		die 'rpm -i failed'
	chmod 0644 "$tree/usr/share/liuqin/kernel.release" 2>/dev/null || :
	check_tree
}

check_tree() {
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	[ -f "$tree/usr/share/liuqin/kernel.release" ] ||
		die 'the tree carries no /usr/share/liuqin/kernel.release'
	recorded=$(cat "$tree/usr/share/liuqin/kernel.release")
	[ -d "$tree/usr/lib/modules/$recorded" ] ||
		die "no module tree for $recorded"
	[ -f "$tree/usr/lib/modules/$recorded/modules.dep" ] ||
		die "no modules.dep for $recorded"
	[ -x "$tree/usr/lib/systemd/systemd" ] || die 'the tree has no systemd'
	modules=$(find "$tree/usr/lib/modules/$recorded" -name '*.ko*' -type f | wc -l | tr -d ' ')
	say "tree: $tree"
	say "release: $recorded, modules: $modules, size: $(du -sm --apparent-size "$tree" | cut -f1) MiB"
	say "rpm: $(rpm --root "$tree" -q $pkg_name 2>/dev/null || echo 'not installed')"
	[ "$modules" -ge 1 ] || die 'the module tree is empty'
}

case ${1:-} in
build) build_rpm ;;
install) install_into_tree ;;
check) resolve_inputs; check_tree ;;
-h | --help) usage; exit 0 ;;
'') usage; exit 1 ;;
*) die "unknown action: $1 (see --help)" ;;
esac
