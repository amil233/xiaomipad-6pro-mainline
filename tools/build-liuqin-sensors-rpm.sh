#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 传感器用户态的 Fedora 版：按 sources.manifest 取源码、打仓库里的补丁、在
# fedora:45 容器里编，最后打成一个 RPM。
#
# 和 Ubuntu 线那份 build-liuqin-sensors-stack.sh 的区别：那份在 Ubuntu 根文件
# 系统上用 apt + overlay，这份在 Fedora 容器里用 dnf。源码和版本钉在同一份
# sources.manifest 上（iio-sensor-proxy 3.9、libssc 0.4.4、hexagonrpc 0.5.0），
# 但补丁集比 Ubuntu 线多三份 0008–0010：它们是参考项目
# （yzddmr6/xiaomipad-6pro-mainline，Ubuntu 26.04 上跑通的实现）为 SSC 环境光
# 加的，Ubuntu 线一直没跟上。补丁原文与作者信息保持不动。
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
	# 源码目录可能被上一次运行改过（补丁已经打上）。回到干净的提交，否则第二次
	# 运行会在 apply --check 上失败；CI 每次是全新目录，本地跑不会。
	git -C "$dir" reset -q --hard "$commit" || die "cannot reset $dir to $commit"
	git -C "$dir" clean -qfd || die "cannot clean $dir"
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
	# 0001/0002 属于 hexagonrpcd，上面已经打过，跳过。
	for patch in "$patches"/00[0-9][0-9]-*.patch; do
		[ -f "$patch" ] || die "missing patch: $patch"
		case $(basename "$patch") in
		0001-* | 0002-*) continue ;;
		esac
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
	# Fedora 的 iio-sensor-proxy 包继续留在设备上：单元、udev 规则、D-Bus 策略、
	# polkit 策略和 monitor-sensor 都由它提供。参考项目在 Ubuntu 上就是这么做的
	# （只替换二进制，unit/udev/dbus/polkit 留给发行包），这也是这套东西在 Fedora
	# 上唯一不会因为"我们自己漏装一份"而整条链断掉的安排——2026-11-27 那次就是
	# 我们自己接管这四份文件之后把单元删掉了。
	#
	# 所以：把上游 meson 装进 staging 的同名文件删掉，只把打过补丁的二进制改名
	# 放到 /usr/libexec（RPM 装的包文件不该进 /usr/local），由 drop-in 把
	# ExecStart 指过去。
	mkdir -p "$out_dir/stage/usr/libexec"
	mv "$out_dir/stage/usr/libexec/iio-sensor-proxy" \
		"$out_dir/stage/usr/libexec/liuqin-iio-sensor-proxy"
	# 只删上游装的那几份，别整目录删：hexagonrpcd 和 ssccli 也住在 /usr/bin，
	# 整段 rm -rf /usr/bin 会把它们一起删掉（2026-11-28 那次 CI 就是这么挂的：
	# 包照打不误，装完树里没有 /usr/bin/hexagonrpcd）。
	# hexagonrpc 还会往 libdir/systemd/system 塞三份模板单元（不是 systemd 的搜索
	# 路径，也没被任何东西引用），一并丢掉。
	rm -rf "$out_dir/stage/etc" \
		"$out_dir/stage/usr/lib/systemd" "$out_dir/stage/usr/lib/udev" \
		"$out_dir/stage/usr/lib64/systemd" \
		"$out_dir/stage/usr/share/dbus-1" "$out_dir/stage/usr/share/polkit-1"
	rm -f "$out_dir/stage/usr/bin/monitor-sensor"
	# libssc 的 mocking 服务器是给测试用的 python 包，设备上不需要；手册页也
	# 不要——rpmbuild 会把它们压成 .gz，清单就跟着对不上。
	rm -rf "$out_dir/stage/usr/share/man" "$out_dir/stage/usr/share/doc"
	for py in "$out_dir"/stage/usr/lib/python3*/site-packages/ssc_server; do
		[ -e "$py" ] || continue
		rm -rf "$py" "$py"-*.dist-info 2>/dev/null || :
	done

	say 'staging our own units'
	overlay=$project_root/device/fedora-overlay/etc/systemd/system
	# /etc 被清过，先建回来放我们自己的 unit（上游那份在 /usr/lib/systemd）。
	mkdir -p "$out_dir/stage/etc/systemd/system/multi-user.target.wants" \
		"$out_dir/stage/usr/local/sbin"
	cp "$overlay/liuqin-hexagonrpcd-sdsp.service" "$overlay/liuqin-sensor-stack.target" \
		"$overlay/liuqin-slpi.service" "$overlay/liuqin-ssc-sample-gate.service" \
		"$out_dir/stage/etc/systemd/system/"
	cp "$project_root/device/fedora-overlay/usr/local/sbin/liuqin-slpi" "$out_dir/stage/usr/local/sbin/"
	# 目录与账户的声明（tmpfiles/sysusers）和 registry 导入工具，照 Ubuntu 的
	# device/sensors-overlay 搬过来；少了 tmpfiles，首启时 /var/lib/liuqin-sensors
	# 和 /run/liuqin-sensors 不一定存在。
	mkdir -p "$out_dir/stage/etc/sysusers.d" "$out_dir/stage/etc/tmpfiles.d"
	cp "$project_root/device/fedora-overlay/etc/sysusers.d/liuqin-fastrpc.conf" \
		"$out_dir/stage/etc/sysusers.d/"
	cp "$project_root/device/fedora-overlay/etc/tmpfiles.d/liuqin-sensors.conf" \
		"$out_dir/stage/etc/tmpfiles.d/"
	cp "$project_root/device/fedora-overlay/usr/local/sbin/liuqin-sensor-registry-import" \
		"$out_dir/stage/usr/local/sbin/"
	chmod 0755 "$out_dir/stage/usr/local/sbin/liuqin-sensor-registry-import"
	# polkit：claim-sensor 不受 session-active 时序影响（Ubuntu 线实测的必要条件），
	# 否则桌面第一次 claim 被拒，整个会话拿不到方向数据。
	mkdir -p "$out_dir/stage/etc/polkit-1/rules.d"
	cp "$project_root/device/fedora-overlay/etc/polkit-1/rules.d/49-liuqin-sensorproxy.rules" \
		"$out_dir/stage/etc/polkit-1/rules.d/"
	chmod 0644 "$out_dir/stage/etc/polkit-1/rules.d/49-liuqin-sensorproxy.rules"
	# 加速度计的预热门禁：ssccli 真实取一次测量，才允许 iio-sensor-proxy 发布。
	mkdir -p "$out_dir/stage/usr/libexec" "$out_dir/stage/etc/systemd/system/iio-sensor-proxy.service.d"
	cp "$project_root/device/fedora-overlay/usr/libexec/liuqin-ssc-sample-gate" \
		"$out_dir/stage/usr/libexec/"
	cp "$project_root/device/fedora-overlay/etc/systemd/system/iio-sensor-proxy.service.d/90-liuqin-ssc.conf" \
		"$out_dir/stage/etc/systemd/system/iio-sensor-proxy.service.d/"
	# gate 不单独开机启用：它由 iio-sensor-proxy 的 drop-in 用 Wants 拉起来，
	# 而 iio-sensor-proxy 由 D-Bus / udev 按需激活——开机时节点还没有，早启动
	# 只会失败（Ubuntu 线同样是这么安排的）。
	chmod 0755 "$out_dir/stage/usr/libexec/liuqin-ssc-sample-gate"
	# 不装 D-Bus 激活条目。Fedora 和 Debian 的 iio-sensor-proxy 包文件清单是同一组
	# 六份（monitor-sensor、单元、udev 规则、二进制、bus 策略、polkit 策略），两边
	# 都没有 /usr/share/dbus-1/system-services 这一条；代理是 udev 规则在
	# /dev/fastrpc-sdsp 出现时用 SYSTEMD_WANTS 拉起来的，Ubuntu 上跑通的就是这个
	# 路径。多写一条激活条目只是多一个可能出错的环节。
	chmod 0755 "$out_dir/stage/usr/local/sbin/liuqin-slpi"
	# 只启用 liuqin-slpi：它负责把 SLPI 拉起来、sdsp 节点才会出现。
	# hexagonrpcd 和 gate 由 udev 的 SYSTEMD_WANTS 在设备事件里拉起
	# （Ubuntu 线明确写了不要开机启用它们：节点还不存在时会被跳过，之后
	# udev 的 SYSTEMD_WANTS 也会变成 no-op）。
	ln -sfn ../liuqin-slpi.service \
		"$out_dir/stage/etc/systemd/system/multi-user.target.wants/liuqin-slpi.service"

	# 文件清单从 stage 里生成，而不是手写：上游的单元名、udev 规则名、
	# 库的 soname 都会随版本变，写死一个就可能在 rpmbuild 上报"找不到文件"。
	# man/doc 不打包：rpmbuild 会在安装之后把它们压缩成 .gz，清单里写的原名
	# 就不存在了，打包会报"File not found"。设备上不需要这些手册页。
	# 打包前把"包里必须有什么"钉死：只删了该删的东西，二进制都还在。
	for path in /usr/bin/hexagonrpcd /usr/bin/ssccli \
		/usr/libexec/liuqin-iio-sensor-proxy /usr/libexec/liuqin-ssc-sample-gate \
		/usr/local/sbin/liuqin-slpi; do
		[ -f "$out_dir/stage$path" ] ||
			die "the staged package would not contain $path"
	done
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
# 不再 Provides 同名包：Fedora 的 iio-sensor-proxy 继续装着，提供单元、udev 规则、
# bus/polkit 策略和 monitor-sensor；我们只补 /usr/libexec 下的一个二进制。
Requires:       iio-sensor-proxy >= 3.8
%description
hexagonrpcd (with the liuqin SSC registry patches), libssc, ssccli and the
patched iio-sensor-proxy binary for the Xiaomi Pad 6 Pro.  Built from the
pinned sources in device/sensors/sources.manifest.
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

ensure_tree_packages() {
	# 树里缺的运行时包，从容器自己的仓库抓下来装进树：KDE Mobile 的包集和
	# Workstation 不一样，libqmi / libqrtr-glib / protobuf-c 不一定在。
	# 只抓这几个包本身（不 --resolve），它们的依赖（glibc、glib2）树里本来就有，
	# 避免顺带把整个基础系统换成仓库版本。
	say "the tree is missing: $*; fetching them"
	command -v dnf >/dev/null 2>&1 ||
		die "the tree lacks $*, and dnf is not available to fetch them"
	mkdir -p "$out_dir/tree-rpms"
	rm -f "$out_dir"/tree-rpms/*.rpm
	dnf -y download --destdir="$out_dir/tree-rpms" "$@" >"$out_dir/tree-dnf.log" 2>&1 ||
		{ tail -30 "$out_dir/tree-dnf.log" >&2; die "dnf could not download $*"; }
	rpm --root "$tree" -U --noscripts --nosignature --nodeps --replacefiles \
		"$out_dir"/tree-rpms/*.rpm >"$out_dir/tree-rpm.log" 2>&1 ||
		{ tail -30 "$out_dir/tree-rpm.log" >&2; die "rpm could not install $* into the tree"; }
	say "installed into the tree: $*"
}

install_into_tree() {
	need rpm
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	# shellcheck disable=SC2012
	rpm_file=$(ls -t "$out_dir"/$pkg_name-*.aarch64.rpm 2>/dev/null | head -1)
	[ -n "$rpm_file" ] || die "no RPM in $out_dir; run the build action first"
	# 发行包提供单元、udev 规则、D-Bus 策略、polkit 策略和 monitor-sensor；
	# libssc 运行时还要 libqmi / libqrtr-glib / protobuf-c。缺哪个补哪个，
	# 不要等到真机上动态链接失败。
	missing=
	for pkg in iio-sensor-proxy libqmi libqrtr-glib protobuf-c; do
		rpm --root "$tree" -q "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
	done
	# shellcheck disable=SC2086
	[ -z "$missing" ] || ensure_tree_packages $missing
	say "installing $rpm_file"
	rpm --root "$tree" -U --replacepkgs --noscripts --nosignature --nodeps "$rpm_file" ||
		die 'rpm could not install the package'
	check_tree
}

check_tree() {
	[ -d "$tree" ] || die "no Fedora tree at $tree"
	for path in /usr/bin/hexagonrpcd /usr/libexec/liuqin-iio-sensor-proxy; do
		[ -x "$tree$path" ] || die "missing in the tree: $path"
	done
	for path in /usr/lib/systemd/system/iio-sensor-proxy.service \
		/usr/lib/udev/rules.d/80-iio-sensor-proxy.rules; do
		[ -e "$tree$path" ] || die "the proxy cannot be started without $path"
	done
	say "hexagonrpcd: $tree/usr/bin/hexagonrpcd"
	say "patched proxy: $tree/usr/libexec/liuqin-iio-sensor-proxy"
	# libssc 在运行时要链 libqmi-glib、libqrtr-glib、libprotobuf-c。这三份都不是
	# Fedora iio-sensor-proxy 包的依赖（那个包只要 glib/gudev/polkit），KDE Mobile
	# 的包集里也不一定有。缺任何一个，ssccli 和代理都会在动态链接阶段直接退出，
	# 表现就是 gate 失败、代理不出现——和内核、固件都没有关系。
	for pkg in libqmi libqrtr-glib protobuf-c; do
		rpm --root "$tree" -q "$pkg" >/dev/null 2>&1 ||
			die "the tree still has no $pkg after the fetch step"
	done
	say "distro package: $(rpm --root "$tree" -q iio-sensor-proxy 2>/dev/null || echo 'not installed')"
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
