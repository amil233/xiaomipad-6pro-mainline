#!/bin/sh
# SPDX-License-Identifier: MIT
#
# 断言构建出来的 RPM 里确实包含整条传感器链需要的文件。
#
# 这些路径不是"清单好看"，每一个对应链上的一环：缺 udev 规则就没有
# ssc-accel 属性、缺 gate 就没有真实测量、缺 drop-in 就没有 Requires 关系、
# 缺 sns_reg_version 就加载不了 registry。离线用 `rpm -qlp` 就能查，不需要设备。
#
#   sh tools/verify-liuqin-rpms.sh OUT_DIR...
set -eu

die() { printf 'verify-liuqin-rpms: %s\n' "$*" >&2; exit 1; }
say() { printf 'verify-liuqin-rpms: %s\n' "$*"; }
[ "$#" -ge 1 ] || die 'usage: verify-liuqin-rpms.sh OUT_DIR...'

rpm_files=
for dir in "$@"; do
	for file in "$dir"/*.aarch64.rpm; do
		[ -f "$file" ] || continue
		rpm_files="$rpm_files $file"
	done
done
[ -n "$rpm_files" ] || die 'no RPM files found'

has() { # PATH
	case_path=$1
	for file in $rpm_files; do
		if rpm -qlp "$file" 2>/dev/null | grep -qxF "$case_path"; then
			return 0
		fi
	done
	return 1
}

has_glob() { # SUFFIX_PATTERN
	for file in $rpm_files; do
		if rpm -qlp "$file" 2>/dev/null | grep -qE "$1"; then
			return 0
		fi
	done
	return 1
}

missing=0
require() {
	has "$1" || { printf '  MISSING %s\n' "$1" >&2; missing=$((missing + 1)); }
}

# 设备包：权限规则、固件、UCM2、救援通道
require /etc/udev/rules.d/80-liuqin-fastrpc.rules
require /usr/lib/firmware/updates/ath11k/WCN6855/hw2.0/board-2.bin
require /usr/share/alsa/ucm2/conf.d/sm8450/Xiaomi-Pad-6-Pro.conf
require /usr/local/sbin/liuqin-rescue
require /usr/local/bin/busybox

# 传感器包：daemon、ssccli、gate、桥接文件
require /usr/bin/hexagonrpcd
require /usr/bin/ssccli
require /usr/libexec/liuqin-ssc-sample-gate
require /etc/systemd/system/liuqin-ssc-sample-gate.service
require /etc/systemd/system/iio-sensor-proxy.service.d/90-liuqin-ssc.conf
require /etc/polkit-1/rules.d/49-liuqin-sensorproxy.rules
require /etc/sysusers.d/liuqin-fastrpc.conf
require /etc/tmpfiles.d/liuqin-sensors.conf
require /usr/local/sbin/liuqin-slpi
require /etc/systemd/system/liuqin-slpi.service
require /etc/systemd/system/liuqin-hexagonrpcd-sdsp.service
require /usr/share/dbus-1/system-services/net.hadess.SensorProxy.service
require /usr/libexec/iio-sensor-proxy
has_glob '^/usr/lib64/libssc\.so' || { printf '  MISSING libssc shared object\n' >&2; missing=$((missing + 1)); }

# 谁都不该把 host 侧的开发文件带进来
for file in $rpm_files; do
	if rpm -qlp "$file" 2>/dev/null | grep -qE '^/usr/share/(man|doc|info)/'; then
		printf '  UNEXPECTED documentation in %s\n' "$file" >&2
		missing=$((missing + 1))
	fi
done

[ "$missing" = 0 ] || die "$missing expected path(s) missing"
say "package contents OK: $(printf '%s\n' $rpm_files | wc -l | tr -d ' ') RPM(s)"
