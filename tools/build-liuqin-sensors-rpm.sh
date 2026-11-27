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
# say 走 stderr：fetch_source 的标准输出要留给 commit 值，混进日志行会污染它。
say() { printf 'build-liuqin-sensors-rpm: %s\n' "$*" >&2; }

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
		glib2-devel libgudev-devel json-glib-devel polkit-devel systemd-devel \
		libqmi-devel python3-devel \
		protobuf-c-devel qrtr-devel >/dev/null 2>&1 ||
		die 'dnf could not install the build dependencies; the package names need checking for Fedora 45'
	need meson; need ninja; need rpmbuild; need git

	hexagonrpc=$(fetch_source hexagonrpc)
	[ -n "$hexagonrpc" ] || die 'could not fetch hexagonrpc'
	libssc=$(fetch_source libssc)
	[ -n "$libssc" ] || die 'could not fetch libssc'
	iio=$(fetch_source iio-sensor-proxy)
	[ -n "$iio" ] || die 'could not fetch iio-sensor-proxy'
	say "hexagonrpc $hexagonrpc, libssc $libssc, iio-sensor-proxy $iio"

	# hexagonrpcd 的两份补丁：registry 版本兄弟文件、sns_registry 属性 shim。
	for patch in "$patches/0001-"*.patch "$patches/0002-"*.patch; do
		[ -f "$patch" ] || die "missing patch: $patch"
		apply_patch "$src_dir/hexagonrpc" "$patch"
	done
	# iio-sensor-proxy 的补丁按编号顺序 0003.. 往后，全部打在同一棵树上。
	for patch in "$patches"/000[3-9]-*.patch; do
		[ -f "$patch" ] || die "missing patch: $patch"
		apply_patch "$src_dir/iio-sensor-proxy" "$patch"
	done

	work=$out_dir/work
	rm -rf "$out_dir"
	mkdir -p "$work" "$out_dir/stage"
	say 'building hexagonrpcd'
	meson setup "$work/hexagonrpc" "$src_dir/hexagonrpc" \
		--prefix=/usr --libdir=lib64 --buildtype=release --wrap-mode=nodownload \
		>"$out_dir/hexagonrpc-configure.log" 2>&1 ||
		{ tail -40 "$out_dir/hexagonrpc-configure.log" >&2; die 'meson configure failed for hexagonrpc'; }
	meson compile -C "$work/hexagonrpc" >"$out_dir/hexagonrpc-compile.log" 2>&1 ||
		{ grep -nE -B4 -A8 '(error:|FAILED)' "$out_dir/hexagonrpc-compile.log" | head -40 >&2;
		   tail -40 "$out_dir/hexagonrpc-compile.log" >&2; die 'compiling hexagonrpc failed'; }
	DESTDIR=$out_dir/stage meson install -C "$work/hexagonrpc" >/dev/null ||
		die 'installing hexagonrpc into the staging tree failed'
	[ -x "$out_dir/stage/usr/bin/hexagonrpcd" ] || die 'hexagonrpcd was not installed'

	say 'building libssc'
	meson setup "$work/libssc" "$src_dir/libssc" \
		--prefix=/usr --libdir=lib64 --buildtype=release --wrap-mode=nodownload \
		>"$out_dir/libssc-configure.log" 2>&1 ||
		{ tail -40 "$out_dir/libssc-configure.log" >&2; die 'meson configure failed for libssc'; }
	meson compile -C "$work/libssc" >"$out_dir/libssc-compile.log" 2>&1 ||
		{ grep -nE '(error|FAILED)' "$out_dir/libssc-compile.log" | head -20 >&2;
		   tail -20 "$out_dir/libssc-compile.log" >&2; die 'compiling libssc failed'; }
	# 装两遍：一遍进容器自己的 /usr（iio-sensor-proxy 的 configure 从 .pc 里读到
	# 的是 /usr/include/libssc，头文件得真的在那里），一遍进 stage 供打包。
	meson install -C "$work/libssc" >/dev/null 2>&1 ||
		die 'installing libssc into the container failed'
	DESTDIR=$out_dir/stage meson install -C "$work/libssc" >/dev/null ||
		die 'installing libssc into the staging tree failed'

	say 'building iio-sensor-proxy'
	meson setup "$work/iio-sensor-proxy" "$src_dir/iio-sensor-proxy" \
		--prefix=/usr --libdir=lib64 --buildtype=release --wrap-mode=nodownload \
		-Dssc-support=enabled -Dtests=false -Dgtk-tests=false -Dgtk_doc=false \
		-Dudevrulesdir=/usr/lib/udev/rules.d \
		-Dsystemdsystemunitdir=/usr/lib/systemd/system \
		--pkg-config-path="$out_dir/stage/usr/lib64/pkgconfig:$out_dir/stage/usr/share/pkgconfig" \
		>"$out_dir/iio-sensor-proxy-configure.log" 2>&1 ||
		{ tail -40 "$out_dir/iio-sensor-proxy-configure.log" >&2; die 'meson configure failed for iio-sensor-proxy'; }
	meson compile -C "$work/iio-sensor-proxy" >"$out_dir/iio-sensor-proxy-compile.log" 2>&1 ||
		{ grep -nE '(error|FAILED)' "$out_dir/iio-sensor-proxy-compile.log" | head -20 >&2;
		   tail -20 "$out_dir/iio-sensor-proxy-compile.log" >&2; die 'compiling iio-sensor-proxy failed'; }
	DESTDIR=$out_dir/stage meson install -C "$work/iio-sensor-proxy" >/dev/null ||
		die 'installing iio-sensor-proxy into the staging tree failed'
	[ -x "$out_dir/stage/usr/libexec/iio-sensor-proxy" ] ||
		die 'iio-sensor-proxy was not installed'

	# 上游的单元和配置不要，用我们自己写的：不经上游的默认值。
	rm -rf "$out_dir/stage/etc" "$out_dir/stage/usr/lib/systemd"
	# libssc 的 mocking 服务器是给测试用的 python 包，设备上不需要；手册页也
	# 不要——rpmbuild 会把它们压成 .gz，清单就跟着对不上。
	rm -rf "$out_dir/stage/usr/share/man" "$out_dir/stage/usr/share/doc"
	for py in "$out_dir"/stage/usr/lib/python3*/site-packages/ssc_server; do
		[ -e "$py" ] || continue
		rm -rf "$py" "$py"-*.dist-info 2>/dev/null || :
	done

	say 'staging our own units'
	overlay=$project_root/device/fedora-overlay/etc/systemd/system
	# 上游单元在前面被删掉了，这两个目录要自己建回来再往里拷。
	mkdir -p "$out_dir/stage/etc/systemd/system/multi-user.target.wants" \
		"$out_dir/stage/usr/local/sbin" \
		"$out_dir/stage/usr/lib/systemd/system"
	cp "$overlay/liuqin-hexagonrpcd-sdsp.service" "$overlay/liuqin-sensor-stack.target" \
		"$overlay/liuqin-slpi.service" "$out_dir/stage/etc/systemd/system/"
	cp "$project_root/device/fedora-overlay/usr/local/sbin/liuqin-slpi" "$out_dir/stage/usr/local/sbin/"
	# iio-sensor-proxy 的 D-Bus 激活靠这三个文件：上游 meson 不装它们（Fedora 是靠
	# RPM 里的 %files 补的），我们卸掉了 Fedora 的包，就得自己带。
	for unit in iio-sensor-proxy.service; do
		cp "$project_root/device/fedora-overlay/usr/lib/systemd/system/$unit" \
			"$out_dir/stage/usr/lib/systemd/system/"
		ln -sfn "../$unit" "$out_dir/stage/etc/systemd/system/multi-user.target.wants/$unit"
	done
	mkdir -p "$out_dir/stage/usr/share/dbus-1/system-services" "$out_dir/stage/usr/share/dbus-1/system.d"
	cp "$project_root/device/fedora-overlay/usr/share/dbus-1/system-services/"*.service \
		"$out_dir/stage/usr/share/dbus-1/system-services/"
	cp "$project_root/device/fedora-overlay/usr/share/dbus-1/system.d/"*.conf \
		"$out_dir/stage/usr/share/dbus-1/system.d/"
	chmod 0755 "$out_dir/stage/usr/local/sbin/liuqin-slpi"
	ln -sfn ../liuqin-slpi.service \
		"$out_dir/stage/etc/systemd/system/multi-user.target.wants/liuqin-slpi.service"
	ln -sfn ../liuqin-hexagonrpcd-sdsp.service \
		"$out_dir/stage/etc/systemd/system/multi-user.target.wants/liuqin-hexagonrpcd-sdsp.service"

	# 文件清单从 stage 里生成，而不是手写：上游的单元名、udev 规则名、
	# 库的 soname 都会随版本变，写死一个就可能在 rpmbuild 上报"找不到文件"。
	# man/doc 不打包：rpmbuild 会在安装之后把它们压缩成 .gz，清单里写的原名
	# 就不存在了，打包会报"File not found"。设备上不需要这些手册页。
	find "$out_dir/stage" \( -type f -o -type l \) -printf '%P\n' |
		grep -vE '^usr/share/(man|doc|info)/' |
		sed 's|^|/|' | sort >"$out_dir/files.list"
	[ -s "$out_dir/files.list" ] || die 'the staging tree is empty'
	spec=$out_dir/$pkg_name.spec
	cat >"$spec" <<EOF
%define debug_package %{nil}
%define __strip /bin/true
%define _build_id_links none
# 不做安装后的 brp 处理：它会把 man 压成 .gz、给 python 包编 .pyc，
# 两者都会变成"装进 buildroot 但没进清单"的文件让打包失败。
%define __os_install_post %{nil}

Name:           $pkg_name
Version:        $version
Release:        1
Summary:        Xiaomi Pad 6 Pro (liuqin) SSC sensor userspace
License:        BSD-3-Clause
BuildArch:      aarch64
AutoReqProv:    no
Provides:       iio-sensor-proxy = 3.9
%description
hexagonrpcd (with the liuqin SSC registry patches) for the Xiaomi Pad 6
Pro.  Built from the pinned sources in device/sensors/sources.manifest.
%install
mkdir -p %{buildroot}
cp -a $out_dir/stage/. %{buildroot}/
%files -f $out_dir/files.list

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
	# Fedora 自带 iio-sensor-proxy，和我们的包装同一批文件。先把它卸掉——设备上
	# 只应该有一份，而且我们这份是打过补丁的。
	if rpm --root "$tree" -q iio-sensor-proxy >/dev/null 2>&1; then
		say "removing Fedora's iio-sensor-proxy (ours replaces it)"
		rpm --root "$tree" -e --noscripts --nodeps iio-sensor-proxy ||
			die 'could not remove the Fedora iio-sensor-proxy package'
	fi
	say "installing $rpm_file"
	rpm --root "$tree" -U --replacepkgs --replacefiles --noscripts --nosignature --nodeps "$rpm_file" ||
		die 'rpm could not install the package'
	check_tree
}

check_tree() {
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	for path in /usr/bin/hexagonrpcd /usr/libexec/iio-sensor-proxy; do
		[ -x "$tree$path" ] || die "missing in the tree: $path"
	done
	say "hexagonrpcd: $tree/usr/bin/hexagonrpcd"
	say "iio-sensor-proxy: $tree/usr/libexec/iio-sensor-proxy"
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
