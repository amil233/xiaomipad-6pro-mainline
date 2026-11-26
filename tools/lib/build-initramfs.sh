#!/bin/sh

set -eu
umask 022

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
busybox=${BUSYBOX:-"$project_root/tools/local/busybox-arm64/usr/bin/busybox"}
# Explicitly select a stage-2 image, or ROOTFS=none for a persistent root.
if [ -z "${ROOTFS+isset}" ]; then
	echo "error: ROOTFS is not set, and it has no default." >&2
	echo "       ROOTFS=out/rootfs/rootfs.squashfs" >&2
	echo "           the two-stage image: initramfs + Ubuntu Base in RAM" >&2
	echo "       ROOTFS=none" >&2
	echo "           no embedded stage-2 image" >&2
	exit 1
fi
rootfs=$ROOTFS
if [ "$rootfs" = none ]; then
	rootfs=
elif [ -z "$rootfs" ]; then
	echo "error: ROOTFS is set but empty, which is the trap this check exists" >&2
	echo "       for. Write ROOTFS=none to ask for the stage-1-only image." >&2
	exit 1
fi
# The touchscreen firmware has to be here and not only in the stage-2 rootfs.
# nvt_ts_probe() queues Boot_Update_Firmware with zero delay, so request_firmware()
# runs while the initramfs is still the root filesystem -- long before the
# squashfs is even attached to a loop device. The retry that would eventually
# find it in the rootfs is the ESD watchdog, and that only fires once the driver
# has decided the controller is alive, which it cannot do if the first download
# never happened. Half a megabyte against a 32 MB initramfs buys certainty.
touch_firmware_dir=${TOUCH_FIRMWARE_DIR:-"$project_root/tools/local/firmware-liuqin/touch-nt36532/vendor/firmware"}
touch_firmware_names="novatek_nt36532_m81_fw_csot.bin novatek_nt36532_m81_fw_tm.bin"
# The Bluetooth firmware is here for the same reason, arrived at the same way.
# hci_register_dev() queues hdev->power_on, and hci_power_on() calls
# hci_dev_open() straight away, which runs hdev->setup -- qca_setup() -- which
# is where the two request_firmware() calls live. Nothing waits for a user: by
# the time /init has finished counting block devices the requests have already
# been made and answered, or already failed. Ubuntu Base ships no BlueZ, so
# there is no second chance from userspace either: no hciconfig, no btmgmt,
# nothing that could re-open hci0 once the rootfs is up. One megabyte, and it
# is the difference between the driver having a chance and not.
#
# The selection rule is explained by the callers: build-liuqin-fedora-boot.sh here,
# the two scripts ship the identical set, from the identical directory, and both
# check it against the same digest.
bt_firmware_dir=${BT_FIRMWARE_DIR:-"$project_root/tools/local/firmware-liuqin/bt-qca6490/vendor/bt_firmware/image"}
bt_firmware_pattern='^(hpbtfw2[01]\.tlv|hpnv2[01]g?\.(bin|b[0-9a-f]+))$'
wlan_board_file=${WLAN_BOARD_FILE:-"$project_root/tools/local/firmware-liuqin/wlan-qca6490/vendor/firmware_mnt/image/qca6490/bd_m81.elf"}
wlan_firmware_dir=${WLAN_FIRMWARE_DIR:-"$project_root/tools/local/firmware-liuqin/wlan-qca6490/upstream/WCN6855/hw2.0"}
# The GNOME product image uses the complete HSP2-amss20 tuple that passed the
# device validation. ath11k probes before
# switch_root, so carrying this only in the stage-2 device layer would leave a
# cold boot on the old HSP1.1 tuple.  Keep all four protocol inputs atomic and
# put raw copies in firmware/updates for both hardware revision request paths.
wlan_hsp2_tuple=${WLAN_HSP2_TUPLE:-"$project_root/out/wlan"}
audio_topology=${AUDIO_TOPOLOGY:-"$project_root/out/audio-topology/Xiaomi-Pad-6-Pro-tplg.bin"}
regulatory_firmware_dir=${REGULATORY_FIRMWARE_DIR:-"$project_root/tools/local/firmware-liuqin/regulatory/upstream"}
gpu_firmware_dir=${GPU_FIRMWARE_DIR:-"$project_root/tools/local/firmware-liuqin/gpu-adreno730/vendor"}
dsp_firmware_dir=${DSP_FIRMWARE_DIR:-"$project_root/tools/local/firmware-liuqin/dsp-sm8475/vendor/qcom/sm8475/liuqin"}
slot_success_source="$project_root/device/boot/liuqin-mark-slot-successful.c"
slot_success_gcc=$(command -v "${SLOT_SUCCESS_GCC:-aarch64-linux-gnu-gcc}" || true)
# An arm64-native builder has no cross toolchain: the host gcc already emits
# aarch64.  Fall back to it rather than failing the build.
if [ -z "$slot_success_gcc" ] && [ "$(uname -m)" = aarch64 ]; then
	slot_success_gcc=$(command -v gcc || true)
	[ -n "$slot_success_gcc" ] && echo "note: slot-success helper using the native host gcc ($slot_success_gcc)" >&2
fi
charger_mode_source="$project_root/device/charger-mode/liuqin-charger-mode"
charger_key_source="$project_root/device/charger-mode/liuqin-charger-mode-power-key.c"
charger_exit_source="$project_root/device/charger-mode/liuqin-charger-mode-exit.c"
source_dir="$project_root/initramfs"
out_dir=${OUT_DIR:-"$project_root/out/initramfs-liuqin"}
source_epoch=${SOURCE_DATE_EPOCH:-0}
storage_mode=${LIUQIN_STORAGE_MODE:-readonly}
embed_rootfs=${LIUQIN_EMBED_ROOTFS:-1}
root_profile=${LIUQIN_ROOT_PROFILE:-fedora}
case $storage_mode in
readonly|persistent) ;;
*)
	echo "error: LIUQIN_STORAGE_MODE must be readonly or persistent, not: $storage_mode" >&2
	exit 1
	;;
esac
case $embed_rootfs in
0|1) ;;
*)
	echo "error: LIUQIN_EMBED_ROOTFS must be 0 or 1, not: $embed_rootfs" >&2
	exit 1
	;;
esac
if [ "$embed_rootfs" = 0 ] && [ "$storage_mode" != persistent ]; then
	echo "error: a rootfs-free initramfs is only valid in persistent mode" >&2
	exit 1
fi
case $root_profile in
fedora) ;;
*) echo "error: LIUQIN_ROOT_PROFILE must be fedora on this branch" >&2; exit 1 ;;
esac
if [ "$root_profile" = fedora ] && [ "$storage_mode" != persistent ]; then
	echo "error: the $root_profile root profile requires persistent mode" >&2
	exit 1
fi
charger_mode=${LIUQIN_CHARGER_MODE:-auto}
case $charger_mode in
auto)
	if [ "$storage_mode" = persistent ] && [ "$root_profile" = fedora ]; then
		charger_mode=1
	else
		charger_mode=0
	fi
	;;
0|1) ;;
*) echo "error: LIUQIN_CHARGER_MODE must be auto, 0 or 1" >&2; exit 1 ;;
esac
if [ "$root_profile" = fedora ] && [ "$charger_mode" != 1 ]; then
	echo "error: a persistent image must include charger-mode hold" >&2
	exit 1
fi
if [ "$root_profile" = fedora ]; then
	[ -d "$wlan_hsp2_tuple/hw2.0" ] && [ -d "$wlan_hsp2_tuple/hw2.1" ] || {
		echo "error: the GNOME image requires the reviewed HSP2 WLAN tuple: $wlan_hsp2_tuple" >&2
		exit 1
	}
	for wlan_name in amss.bin m3.bin board-2.bin regdb.bin; do
		for wlan_revision in hw2.0 hw2.1; do
			[ -f "$wlan_hsp2_tuple/$wlan_revision/$wlan_name" ] || {
				echo "error: HSP2 WLAN tuple lacks $wlan_revision/$wlan_name" >&2
				exit 1
			}
			done
	done
	[ -f "$audio_topology" ] && [ ! -L "$audio_topology" ] || {
		echo "error: AudioReach topology is unavailable: $audio_topology" >&2
		exit 1
	}
fi
if [ ! -x "$busybox" ]; then
	echo "error: static ARM64 BusyBox is unavailable: $busybox" >&2
	exit 1
fi

if ! readelf -h "$busybox" | grep -q 'Machine:.*AArch64'; then
	echo "error: BusyBox is not an AArch64 executable: $busybox" >&2
	exit 1
fi

if readelf -l "$busybox" | grep -q 'INTERP'; then
	echo "error: BusyBox is dynamically linked: $busybox" >&2
	exit 1
fi

if [ ! -d "$bt_firmware_dir" ]; then
	echo "error: Bluetooth firmware directory is unavailable: $bt_firmware_dir" >&2
	exit 1
fi
[ -f "$wlan_board_file" ] || {
	echo "error: WLAN board data is unavailable: $wlan_board_file" >&2
	exit 1
}
if [ "$(dd if="$wlan_board_file" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" != 7f454c46 ]; then
	echo 'error: WLAN board data is not an ELF' >&2
	exit 1
fi

if [ -n "$rootfs" ] && [ ! -r "$rootfs" ]; then
	echo "error: stage-2 root filesystem is unavailable: $rootfs" >&2
	echo "       pass ROOTFS=none to ask for the stage-1-only image." >&2
	echo "       build the stage-1-only diagnostic initramfs." >&2
	exit 1
fi

# boot.img 和 rootfs 是分别刷进去的。这里把这次构建的内核版本号钉进
# initramfs，stage 1 拿它和根里的 /usr/share/liuqin/kernel.release 比，不一致
# 就拒绝挂载——这是“两个一起刷”这条规则的执行方式。
if [ -z "${EXPECTED_RELEASE:-}" ]; then
	echo "error: set EXPECTED_RELEASE to the kernel release this image boots" >&2
	exit 1
fi
case $EXPECTED_RELEASE in
'' | *[!A-Za-z0-9._+-]*) echo "error: unsafe kernel release: $EXPECTED_RELEASE" >&2; exit 1 ;;
esac

mkdir -p "$out_dir"
# The cpio below runs inside `cd "$staging"`, so every path it is handed has to
# be absolute. The built-in default already is; a relative OUT_DIR= on the
# command line was not, and failed there with a message about a file it had
# created moments earlier.
out_dir=$(CDPATH= cd -- "$out_dir" && pwd)
archive="$out_dir/liuqin-firstboot.cpio.gz"
raw_archive="$out_dir/.liuqin-firstboot.cpio.$$"
staging=$(mktemp -d "$out_dir/.staging.XXXXXX")
cleanup() {
	rm -f "$raw_archive" "$raw_archive.gz"
	rm -rf "$staging"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$staging/bin" "$staging/sbin" "$staging/etc" "$staging/proc" \
	"$staging/sys" "$staging/dev" "$staging/run" "$staging/usr/bin" \
	"$staging/usr/sbin"
cp "$busybox" "$staging/bin/busybox"
cp "$source_dir/init" "$staging/init"
cp "$source_dir/etc/issue" "$staging/etc/issue"
cp "$source_dir/etc/mdev.conf" "$staging/etc/mdev.conf"
chmod 0644 "$staging/etc/mdev.conf"
chmod 0755 "$staging/init" "$staging/bin/busybox"
printf '%s\n' "$storage_mode" >"$staging/etc/liuqin-storage-mode"
chmod 0644 "$staging/etc/liuqin-storage-mode"
printf '%s\n' "$EXPECTED_RELEASE" >"$staging/etc/liuqin-expected-release"
chmod 0644 "$staging/etc/liuqin-expected-release"
if [ "$storage_mode" = persistent ]; then
	"$slot_success_gcc" -static -Os -s "$slot_success_source" \
		-o "$staging/bin/liuqin-mark-slot-successful"
	chmod 0755 "$staging/bin/liuqin-mark-slot-successful"
	if ! readelf -h "$staging/bin/liuqin-mark-slot-successful" | grep -q 'Machine:.*AArch64' ||
		readelf -l "$staging/bin/liuqin-mark-slot-successful" | grep -q INTERP; then
		echo "error: slot-success helper is not a static AArch64 ELF" >&2
		exit 1
	fi
fi
if [ "$charger_mode" = 1 ]; then
	printf '%s\n' hold-v1 >"$staging/etc/liuqin-charger-mode"
	chmod 0644 "$staging/etc/liuqin-charger-mode"
	cp "$charger_mode_source" "$staging/bin/liuqin-charger-mode"
	chmod 0755 "$staging/bin/liuqin-charger-mode"
	for charger_helper in key exit; do
		case $charger_helper in
		key) charger_source=$charger_key_source; charger_output=liuqin-charger-mode-power-key ;;
		exit) charger_source=$charger_exit_source; charger_output=liuqin-charger-mode-exit ;;
		esac
		"$slot_success_gcc" -static -Os -s -Wall -Wextra -Werror \
			"$charger_source" -o "$staging/bin/$charger_output"
		chmod 0755 "$staging/bin/$charger_output"
		if ! readelf -h "$staging/bin/$charger_output" | grep -q 'Machine:.*AArch64' ||
			readelf -l "$staging/bin/$charger_output" | grep -q INTERP; then
			echo "error: $charger_output is not a static AArch64 ELF" >&2
			exit 1
		fi
	done
fi

mkdir -p "$staging/lib/firmware/novatek/liuqin"
for firmware_name in $touch_firmware_names; do
	[ -f "$touch_firmware_dir/$firmware_name" ] || {
		echo "error: touch firmware is missing: $touch_firmware_dir/$firmware_name" >&2
		exit 1
	}
	cp "$touch_firmware_dir/$firmware_name" \
		"$staging/lib/firmware/novatek/liuqin/$firmware_name"
	chmod 0644 "$staging/lib/firmware/novatek/liuqin/$firmware_name"
done

# btqca.c hardcodes the qca/ prefix into every name it builds, so this directory
# is not a choice.
mkdir -p "$staging/lib/firmware/qca"
printf '%s\n' "$bt_firmware_names" | while read -r firmware_name; do
	cp "$bt_firmware_dir/$firmware_name" "$staging/lib/firmware/qca/$firmware_name"
	chmod 0644 "$staging/lib/firmware/qca/$firmware_name"
done

# ath11k probes and boots MHI before /init can switch_root, so WLAN firmware is
# just as stage-1-critical as the BT blobs above. Keep one physical compressed
# copy under hw2.0 and symlink hw2.1 to it, matching upstream linux-firmware.
for hw_revision in hw2.0 hw2.1; do
	mkdir -p "$staging/lib/firmware/ath11k/WCN6855/$hw_revision"
	cp "$wlan_board_file" \
		"$staging/lib/firmware/ath11k/WCN6855/$hw_revision/board.bin"
	chmod 0644 "$staging/lib/firmware/ath11k/WCN6855/$hw_revision/board.bin"
done
# Self-install fallback: the pool's upstream WCN6855 zst set is optional; when
# absent, derive it from the HSP2 tuple exactly like build-liuqin-firmware-prep.sh
# does (same payloads, bdencoder-packed board-2 for this board revision).
wlan_zst_tmp=$staging/.wlan-zst
mkdir -p "$wlan_zst_tmp"
if [ -d "$wlan_firmware_dir" ] && ls "$wlan_firmware_dir"/*.zst >/dev/null 2>&1; then
	wlan_zst_source=$wlan_firmware_dir
else
	for wlan_tuple_name in amss.bin m3.bin regdb.bin board-2.bin; do
		zstd -q -19 -f -o "$wlan_zst_tmp/$wlan_tuple_name.zst" \
			"$wlan_hsp2_tuple/hw2.0/$wlan_tuple_name" 2>/dev/null || {
			echo "error: WLAN stage-1 firmware unavailable: neither $wlan_firmware_dir nor the HSP2 tuple supplies $wlan_tuple_name" >&2
			exit 1
		}
	done
	wlan_zst_source=$wlan_zst_tmp
fi
for firmware_name in amss.bin.zst board-2.bin.zst m3.bin.zst regdb.bin.zst; do
	cp "$wlan_zst_source/$firmware_name" \
		"$staging/lib/firmware/ath11k/WCN6855/hw2.0/$firmware_name"
	chmod 0644 "$staging/lib/firmware/ath11k/WCN6855/hw2.0/$firmware_name"
	ln -s "../hw2.0/$firmware_name" \
		"$staging/lib/firmware/ath11k/WCN6855/hw2.1/$firmware_name"
done
rm -rf "$wlan_zst_tmp"

if [ "$root_profile" = fedora ]; then
	for wlan_revision in hw2.0 hw2.1; do
		for wlan_name in amss.bin m3.bin board-2.bin regdb.bin; do
			install -D -m 0644 "$wlan_hsp2_tuple/$wlan_revision/$wlan_name" \
				"$staging/lib/firmware/updates/ath11k/WCN6855/$wlan_revision/$wlan_name"
		done
	done
	install -D -m 0644 "$audio_topology" \
		"$staging/lib/firmware/qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin"
fi

# cfg80211 is built in and requests its signed regulatory database while still
# in stage 1. The kernel configuration requires the matching PKCS#7 signature,
# so keep the pair together when the pool ships them.  Our kernel carries the
# signed database and its keys built in (CONFIG_CFG80211_USE_KERNEL_REGDB_KEYS),
# so the userland pair is optional; skip it rather than fail the build.
for firmware_name in regulatory.db regulatory.db.p7s; do
	if [ -f "$regulatory_firmware_dir/$firmware_name" ]; then
		cp "$regulatory_firmware_dir/$firmware_name" "$staging/lib/firmware/$firmware_name"
		chmod 0644 "$staging/lib/firmware/$firmware_name"
	else
		echo "note: regulatory $firmware_name is absent; the kernel carries its own signed copy" >&2
	fi
done

# DRM/GPU and all three PAS remoteprocs probe before /init can switch_root.
# Mirror the exact stage-2 layout here so neither side depends on probe timing.
mkdir -p "$staging/lib/firmware/qcom/sm8475/liuqin"
cp "$gpu_firmware_dir/a730_zap.mbn" \
	"$staging/lib/firmware/qcom/sm8475/liuqin/a730_zap.mbn"
cp "$gpu_firmware_dir/a730_sqe.fw" "$gpu_firmware_dir/gmu_gen70000.bin" \
	"$staging/lib/firmware/qcom/"
cp "$dsp_firmware_dir"/* "$staging/lib/firmware/qcom/sm8475/liuqin/"

if [ -n "$rootfs" ] && [ "$embed_rootfs" = 1 ]; then
	mkdir -p "$staging/mnt/lower" "$staging/mnt/rw" "$staging/newroot"
	cp "$rootfs" "$staging/rootfs.squashfs"
	chmod 0644 "$staging/rootfs.squashfs"
fi

# `ln` and `udhcpd` were used by the init script long before they were linked
# here: the Ubuntu BusyBox is built with the standalone shell, so its own `sh`
# dispatches applets it cannot find in PATH. That is a property of one vendor's
# build, not of BusyBox, and nothing outside `sh` gets it -- so link every applet
# the init script names.
for applet in basename blockdev cat chmod chroot cp cttyhack cut dmesg findfs \
	hostname ip kill killall ln losetup ls mkdir mount poweroff readlink reboot \
	setsid sh sha256sum sleep stat switch_root sync telnetd udhcpd umount; do
	ln -s busybox "$staging/bin/$applet"
done
ln -s ../bin/busybox "$staging/sbin/mdev"

find "$staging" -exec touch -h -d "@$source_epoch" {} +

(
	cd "$staging"
	find . -print0 | LC_ALL=C sort -z | \
		cpio --null --create --format=newc --owner=0:0 --reproducible \
			--file="$raw_archive"
)
gzip -n -9 "$raw_archive"
mv "$raw_archive.gz" "$archive"

if [ -n "$rootfs" ]; then
	sha256sum "$archive" "$busybox" "$rootfs"
else
	sha256sum "$archive" "$busybox"
fi
printf 'bluetooth firmware: %s files\n' "$(printf '%s\n' "$bt_firmware_names" | wc -l)"
printf 'initramfs: %s bytes\n' "$(stat -c %s "$archive")"
printf 'initramfs: %s\n' "$archive"
printf 'storage mode: %s\n' "$storage_mode"
printf 'embedded rootfs: %s\n' "$embed_rootfs"
printf 'root profile: %s\n' "$root_profile"
printf 'charger mode: %s\n' "$charger_mode"
