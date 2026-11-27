#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 传感器用户态的 Fedora 版：按 sources.manifest 取源码、打仓库里的补丁、在
# fedora:45 容器里编，最后打成一个 RPM。
#
# 和 Ubuntu 线那份 build-liuqin-sensors-stack.sh 的区别只在构建环境：那份在
# Ubuntu 根文件系统上用 apt + overlay，这份在 Fedora 容器里用 dnf，源码、补丁、
# 版本完全一致（manifest 里 iio-sensor-proxy 本来就钉在 3.9）。
#
#   sh tools/fedora-container.sh 'sh tools/build-liuqin-sensors-rpm.sh build'
#
#   build   取源码、打补丁、编译、打 RPM
#   install 装进树
#   check   检查树里的二进制和单元
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${OUT:-"$project_root/out/fedora-sensors"}
tree=${TREE:-"$project_root/tools/local/fedora-kde-mobile-45-arm64/rootfs"}
src_dir=${SRC_DIR:-"$project_root/tools/local/sensor-stack-src"}
manifest=$project_root/device/sensors/sources.manifest
patches=$project_root/device/sensors/patches
pkg_name=liuqin-sensors
version=0.1

die() { printf 'build-liuqin-sensors-rpm: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-sensors-rpm: %s\n' "$*"; }

usage() {
	cat <<'EOF'
usage: build-liuqin-sensors-rpm.sh build|install|check

  build    取源码、打补丁、编译，打 liuqin-sensors RPM（需要 meson/ninja/gcc）
  install  装进树（需要 rpm）
  check    检查树里的 hexagonrpcd、iio-sensor-proxy 和单元
EOF
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run through tools/fedora-container.sh"; }

fetch_source() { # COMPONENT
	component=$1
	[ -f "$manifest" ] || die "no sources.manifest"
	row=$(awk -F'\t' -v c="$component" '$1 == c { print; exit }' "$manifest")
	[ -n "$row" ] || die "no manifest row for $component"
	repository=$(printf '%s\n' "$row" | cut -f3)
	commit=$(printf '%s\n' "$row" | cut -f4)
	dir=$src_dir/$component
	if [ ! -d "$dir/.git" ]; then
		say "fetching $component ($commit)"
		git clone --filter=blob:none "$repository" "$dir" >/dev/null 2>&1 ||
			die "clone failed: $repository"
	fi
	git -C "$dir" checkout -q "$commit" || die "cannot check out $commit in $dir"
	git -C "$dir" rev-parse --short HEAD
}

apply_patch() { # REPO PATCH
	git -C "$1" apply --check "$2" 2>/dev/null || die "patch does not apply cleanly: $2"
	git -C "$1" apply "$2" || die "applying failed: $2"
	say "patched $(basename "$1") with $(basename "$2")"
}

build_rpm() {
	# 先装依赖再检查工具：镜像里本来什么构建工具都没有。
	command -v dnf >/dev/null || die 'dnf is missing; run through tools/fedora-container.sh'
	say 'installing build dependencies'
	dnf -y install --setopt=install_weak_deps=False \
		gcc gcc-c++ meson ninja-build pkgconf-pkg-config git \
		protobuf-c-devel qrtr-devel systemd-devel >/dev/null 2>&1 ||
		die 'dnf could not install the build dependencies; the package names need checking for Fedora 45'
	need meson; need ninja; need rpmbuild; need git

	hexagonrpc=$(fetch_source hexagonrpc)
	libssc=$(fetch_source libssc)
	say "hexagonrpc $hexagonrpc, libssc $libssc"

	# hexagonrpcd 的两份补丁：registry 版本兄弟文件、sns_registry 属性 shim。
	for patch in "$patches/0001-"*.patch "$patches/0002-"*.patch; do
		[ -f "$patch" ] || die "missing patch: $patch"
		apply_patch "$src_dir/hexagonrpc" "$patch"
	done

	work=$out_dir/work
	rm -rf "$out_dir"
	mkdir -p "$work" "$out_dir/stage"
	say 'building hexagonrpcd'
	meson setup "$work/hexagonrpc" "$src_dir/hexagonrpc" \
		--prefix=/usr --libdir=lib64 --buildtype=release --wrap-mode=nodownload >/dev/null ||
		die 'meson configure failed for hexagonrpc'
	meson compile -C "$work/hexagonrpc" >/dev/null || die 'compiling hexagonrpc failed'
	DESTDIR=$out_dir/stage meson install -C "$work/hexagonrpc" >/dev/null ||
		die 'installing hexagonrpc into the staging tree failed'
	[ -x "$out_dir/stage/usr/bin/hexagonrpcd" ] || die 'hexagonrpcd was not installed'

	# 只装二进制，不带上游的单元和配置：服务怎么起由我们自己的单元决定。
	rm -rf "$out_dir/stage/etc" "$out_dir/stage/usr/lib/systemd"

	spec=$out_dir/$pkg_name.spec
	cat >"$spec" <<EOF
%define debug_package %{nil}
%define __strip /bin/true
%define _build_id_links none

Name:           $pkg_name
Version:        $version
Release:        1
Summary:        Xiaomi Pad 6 Pro (liuqin) SSC sensor userspace
License:        BSD-3-Clause
BuildArch:      aarch64
AutoReqProv:    no
%description
hexagonrpcd (with the liuqin SSC registry patches) for the Xiaomi Pad 6
Pro.  Built from the pinned sources in device/sensors/sources.manifest.
%install
mkdir -p %{buildroot}
cp -a $out_dir/stage/. %{buildroot}/
%files
/usr/bin/hexagonrpcd
EOF
	say "building $pkg_name-$version-1.aarch64.rpm"
	rpmbuild -bb --quiet --define "_topdir $out_dir/rpmbuild" "$spec" \
		>"$out_dir/rpmbuild.log" 2>&1 || { tail -40 "$out_dir/rpmbuild.log" >&2; die 'rpmbuild failed'; }
	mv "$out_dir/rpmbuild/RPMS/aarch64/$pkg_name-$version-1.aarch64.rpm" "$out_dir/" ||
		die 'rpmbuild produced no RPM'
	rm -rf "$out_dir/work" "$out_dir/stage" "$out_dir/rpmbuild" "$out_dir/$pkg_name.spec"
	say "rpm: $out_dir/$pkg_name-$version-1.aarch64.rpm"
}

install_into_tree() {
	need rpm
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	# shellcheck disable=SC2012
	rpm_file=$(ls -t "$out_dir"/$pkg_name-*.aarch64.rpm 2>/dev/null | head -1)
	[ -n "$rpm_file" ] || die "no RPM in $out_dir; run the build action first"
	say "installing $rpm_file"
	rpm --root "$tree" -U --replacepkgs --noscripts --nosignature --nodeps "$rpm_file" ||
		die 'rpm could not install the package'
	check_tree
}

check_tree() {
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	[ -x "$tree/usr/bin/hexagonrpcd" ] || die 'hexagonrpcd is missing from the tree'
	say "hexagonrpcd: $tree/usr/bin/hexagonrpcd"
	say "package: $(rpm --root "$tree" -q $pkg_name 2>/dev/null || echo 'not installed')"
}

case ${1:-} in
build) build_rpm ;;
install) install_into_tree ;;
check) check_tree ;;
-h | --help) usage; exit 0 ;;
'') usage; exit 1 ;;
*) die "unknown action: $1 (see --help)" ;;
esac
