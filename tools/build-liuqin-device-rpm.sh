#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 设备侧的文件型载荷：固件、WLAN board 数据、ALSA UCM2 配置。打成一个
# `liuqin-device` RPM 装进 Fedora 的根。
#
# 只放文件，不装服务：GNOME 那套定制（dconf、gnome-control-center 电源面板、
# gdm 锁）在这条线上没有对应物，Plasma Mobile 自己带移动形态的亮度、电源菜单和
# 虚拟键盘，不需要照搬。需要跑起来的设备逻辑（MAC、蓝牙地址、传感器栈）等用户
# 态移植时另做。
#
# 在 fedora:45 容器里跑：
#   sh tools/fedora-container.sh 'sh tools/build-liuqin-device-rpm.sh build install'
#
#   build   出 RPM（只要仓库里的 device/ 输入）
#   install 装进树
#   check   检查树里的关键文件
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${OUT:-"$project_root/out/fedora-rpm"}
tree=${TREE:-"$project_root/tools/local/fedora-kde-mobile-45-arm64/rootfs"}
pkg_name=liuqin-device
version=1.0
stage_rel=/usr/lib/firmware

die() { printf 'build-liuqin-device-rpm: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-device-rpm: %s\n' "$*"; }

usage() {
	cat <<'EOF'
usage: build-liuqin-device-rpm.sh build|install|check

  build    出 liuqin-device RPM（需要 rpmbuild）
  install  装进树（需要 rpm）
  check    检查树里的固件、WLAN board 和 UCM2 文件
EOF
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run through tools/fedora-container.sh"; }

build_rpm() {
	need rpmbuild
	firmware=$project_root/device/firmware$stage_rel
	wlan=$project_root/device/wlan-tuple
	ucm=$project_root/device/gnome-overlay/usr/share/alsa/ucm2
	[ -d "$firmware" ] || die "no firmware tree: $firmware"
	[ -f "$wlan/hw2.0/board-2.bin" ] || die "no WLAN tuple: $wlan"
	[ -f "$ucm/conf.d/sm8450/Xiaomi-Pad-6-Pro.conf" ] || die "no UCM2 config: $ucm"

	stage=$out_dir/stage
	# 只清自己这次的中间产物：OUT 目录里可能还有别的包。
	rm -rf "$out_dir/stage" "$out_dir/rpmbuild" "$out_dir/$pkg_name.spec"
	rm -f "$out_dir/$pkg_name-"*.aarch64.rpm
	mkdir -p "$stage/usr/lib/firmware/updates/ath11k/WCN6855/hw2.0" \
		"$stage/usr/lib/firmware/updates/ath11k/WCN6855/hw2.1" \
		"$stage/usr/share/alsa/ucm2/conf.d/sm8450" \
		"$stage/usr/share/alsa/ucm2/Qualcomm/sm8450/Xiaomi-Pad-6-Pro"

	say 'staging firmware'
	cp -a "$firmware/." "$stage/usr/lib/firmware/"

	say 'staging WLAN board data'
	for revision in hw2.0 hw2.1; do
		for file in "$wlan/$revision"/*; do
			[ -f "$file" ] || continue
			case $file in
			*/board-2.bin|*/amss.bin|*/m3.bin|*/regdb.bin) ;;
			*) continue ;;
			esac
			cp "$file" "$stage/usr/lib/firmware/updates/ath11k/WCN6855/$revision/"
		done
	done
	# hw2.1 里没有 regdb.bin，和 hw2.0 共用一份。
	[ -f "$stage/usr/lib/firmware/updates/ath11k/WCN6855/hw2.1/regdb.bin" ] ||
		cp "$stage/usr/lib/firmware/updates/ath11k/WCN6855/hw2.0/regdb.bin" \
			"$stage/usr/lib/firmware/updates/ath11k/WCN6855/hw2.1/regdb.bin"

	say 'staging the rescue channel'
	overlay=$project_root/device/fedora-overlay
	busybox=$project_root/tools/local/busybox-arm64/usr/bin/busybox
	[ -d "$overlay" ] || die "no overlay: $overlay"
	[ -x "$busybox" ] || die "no static busybox at $busybox (run tools/fetch-busybox-arm64.sh)"
	mkdir -p "$stage/usr/local/bin" "$stage/usr/local/sbin" "$stage/etc/systemd/system/multi-user.target.wants" \
		"$stage/etc/udev/rules.d"
	cp "$overlay/usr/local/bin/liuqin-shell" "$stage/usr/local/bin/"
	cp "$overlay/usr/local/sbin/liuqin-rescue" "$overlay/usr/local/sbin/liuqin-usb-rescue" "$stage/usr/local/sbin/"
	cp "$busybox" "$stage/usr/local/bin/busybox"
	cp "$overlay/etc/systemd/system/liuqin-usb-rescue.service" "$stage/etc/systemd/system/"
	ln -sfn ../liuqin-usb-rescue.service \
		"$stage/etc/systemd/system/multi-user.target.wants/liuqin-usb-rescue.service"
	cp "$overlay/etc/udev/rules.d/80-liuqin-fastrpc.rules" "$stage/etc/udev/rules.d/"
	chmod 0755 "$stage/usr/local/bin/liuqin-shell" "$stage/usr/local/bin/busybox" \
		"$stage/usr/local/sbin/liuqin-rescue" "$stage/usr/local/sbin/liuqin-usb-rescue"

	say 'staging UCM2'
	cp "$ucm/conf.d/sm8450/Xiaomi-Pad-6-Pro.conf" "$stage/usr/share/alsa/ucm2/conf.d/sm8450/"
	cp "$ucm/Qualcomm/sm8450/Xiaomi-Pad-6-Pro/HiFi.conf" \
		"$stage/usr/share/alsa/ucm2/Qualcomm/sm8450/Xiaomi-Pad-6-Pro/"

	spec=$out_dir/$pkg_name.spec
	cat >"$spec" <<EOF
%define debug_package %{nil}
%define __strip /bin/true
%define _build_id_links none

Name:           $pkg_name
Version:        $version
Release:        1
Summary:        Xiaomi Pad 6 Pro (liuqin) firmware, WLAN board data and UCM2
License:        Proprietary and MIT
BuildArch:      aarch64
AutoReqProv:    no
%description
Firmware, the WLAN board data and the ALSA UCM2 configuration for the Xiaomi
Pad 6 Pro (liuqin).  Files only: no services and no desktop customisation.
%install
mkdir -p %{buildroot}
cp -a $stage/. %{buildroot}/
%files
/etc/udev/rules.d/80-liuqin-fastrpc.rules
/usr/lib/firmware
/usr/share/alsa/ucm2
/usr/local/bin/busybox
/usr/local/bin/liuqin-shell
/usr/local/sbin/liuqin-rescue
/usr/local/sbin/liuqin-usb-rescue
/etc/systemd/system/liuqin-usb-rescue.service
/etc/systemd/system/multi-user.target.wants/liuqin-usb-rescue.service
EOF

	say "building $pkg_name-$version-1.aarch64.rpm"
	rpmbuild -bb --quiet --define "_topdir $out_dir/rpmbuild" "$spec" \
		>"$out_dir/rpmbuild.log" 2>&1 || { tail -40 "$out_dir/rpmbuild.log" >&2; die 'rpmbuild failed'; }
	mv "$out_dir/rpmbuild/RPMS/aarch64/$pkg_name-$version-1.aarch64.rpm" "$out_dir/" ||
		die 'rpmbuild produced no RPM'
	rm -rf "$out_dir/stage" "$out_dir/rpmbuild" "$out_dir/$pkg_name.spec"
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
	for path in \
		/usr/local/sbin/liuqin-rescue \
		/usr/local/bin/busybox \
		/etc/systemd/system/multi-user.target.wants/liuqin-usb-rescue.service \
		/usr/lib/firmware/updates/ath11k/WCN6855/hw2.0/board-2.bin \
		/usr/lib/firmware/updates/ath11k/WCN6855/hw2.1/board-2.bin \
		/usr/share/alsa/ucm2/conf.d/sm8450/Xiaomi-Pad-6-Pro.conf \
		/usr/share/alsa/ucm2/Qualcomm/sm8450/Xiaomi-Pad-6-Pro/HiFi.conf; do
		[ -f "$tree$path" ] || die "missing in the tree: $path"
	done
	say "firmware files: $(find "$tree/usr/lib/firmware" -type f | wc -l | tr -d ' ')"
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
