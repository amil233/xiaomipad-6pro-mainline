#!/bin/sh
# SPDX-License-Identifier: MIT
# Assemble a native boot image from kernel build outputs and a root manifest.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${OUT_DIR:-"$project_root/out/native-boot"}
kernel_source=${KERNEL_SOURCE:-"$project_root/../linux-sm8450-liuqin"}
kernel_out=${KERNEL_OUT:-"$project_root/out/kernel"}
native_root_hashes=${NATIVE_ROOT_HASHES:?"set NATIVE_ROOT_HASHES to the assembled root's native-root.hashes"}
audio_topology=${AUDIO_TOPOLOGY:?"set AUDIO_TOPOLOGY to the built AudioReach topology"}
firmware_pool=${FIRMWARE_POOL:?"set FIRMWARE_POOL to the prepared firmware input directory"}
wlan_tuple=${WLAN_HSP2_TUPLE:?"set WLAN_HSP2_TUPLE to the prepared WLAN tuple"}
stock_overlay_dir=${STOCK_OVERLAY_DIR:?"set STOCK_OVERLAY_DIR to the extracted stock DTBO entries"}
stock_base_dir=${STOCK_BASE_DIR:?"set STOCK_BASE_DIR to the extracted stock vendor_boot DTBs"}
mk_dir=${MKBOOTIMG_DIR:-"$project_root/tools/local/aosp-mkbootimg"}
slot_cc=${SLOT_SUCCESS_GCC:-}
# An arm64-native builder has no cross toolchain; the host gcc emits aarch64.
if [ -z "$slot_cc" ]; then
	if [ "$(uname -m)" = aarch64 ] && command -v gcc >/dev/null 2>&1; then
		slot_cc=gcc
	else
		slot_cc=aarch64-linux-gnu-gcc
	fi
fi
dtc=${DTC:-$kernel_out/scripts/dtc/dtc}
fdtoverlay=${FDTOVERLAY:-$kernel_out/scripts/dtc/fdtoverlay}
image=${KERNEL_IMAGE:-$kernel_out/arch/arm64/boot/Image}
raw_dtb=${KERNEL_DTB:-$kernel_out/arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dtb}
cmdline=$(cat "$project_root/device/native-bootargs.txt")

die() { printf 'build-liuqin-native-boot: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-native-boot: %s\n' "$*"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

case $out_dir in
"$project_root"/out/*) ;;
*) die "output must be below $project_root/out" ;;
esac
case $out_dir in */../*|*/..|*/./*) die 'output path must not contain traversal' ;; esac
[ ! -e "$out_dir" ] && [ ! -L "$out_dir" ] || die "output already exists: $out_dir"
for input in "$image" "$raw_dtb" "$native_root_hashes" "$audio_topology" "$dtc" "$fdtoverlay"; do
	[ -f "$input" ] || die "input missing: $input"
done
[ -d "$firmware_pool" ] && [ -d "$wlan_tuple" ] &&
	[ -d "$stock_overlay_dir" ] && [ -d "$stock_base_dir" ] || die 'firmware/ROM input directory missing'
# The mkbootimg script identities are release pins; any working copy is fine
# for a personal assembly. The boot-image round-trip check in
# build-bootimg.sh still catches a genuinely broken unpack/mk pair.
say "mkbootimg: $(sha "$mk_dir/mkbootimg.py" | cut -c1-16)"
say "unpack_bootimg: $(sha "$mk_dir/unpack_bootimg.py" | cut -c1-16)"

# The source identity gates below are a release-pipeline repetition of the
# assembly-level lock checks (build-liuqin-image.py already validated the
# artifact commit against the product lock and downgraded the .config byte
# comparison to a NOTE).  When the kernel source tree is absent -- assembly
# from a CI artifact on a machine without the kernel checkout -- take the
# commit and the build timestamp from the artifact's build-info.json
# instead; the identity is still anchored to the lock, just by metadata.
kernel_info=$kernel_out/build-info.json
if git -C "$kernel_source" rev-parse --git-dir >/dev/null 2>&1; then
	kernel_source_kind=git
else
	if [ ! -f "$kernel_info" ]; then
		die "neither a kernel source checkout ($kernel_source) nor an artifact build-info.json ($kernel_info) is available"
	fi
	kernel_source_kind=metadata
	say "kernel source: using CI artifact metadata from $kernel_info"
fi

release_file=$kernel_out/include/config/kernel.release
if [ ! -f "$release_file" ]; then
	# CI artifacts do not carry the kernel build tree; the release string
	# is packaged with the prepared module set instead.
	release_file=$kernel_out/../kernel-modules/kernel.release
fi
[ -f "$release_file" ] || die 'kernel release string is unavailable: no build tree and no packaged release'

python3 - "$project_root/kernel/source.json" "$kernel_out" "$native_root_hashes" "$kernel_source_kind" "$kernel_source" "$release_file" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
lock = json.loads(Path(sys.argv[1]).read_text())
out, manifest, kind, source, release_file = (Path(sys.argv[2]), Path(sys.argv[3]),
                                             sys.argv[4], sys.argv[5], Path(sys.argv[6]))
if kind == 'git':
    commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if commit != lock['commit']:
        raise SystemExit('kernel source does not match kernel/source.json')
    if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain']):
        raise SystemExit('kernel source is dirty')
else:
    info = json.loads((out / 'build-info.json').read_text())
    if info['commit'] != lock['commit']:
        raise SystemExit('kernel artifact commit does not match kernel/source.json')
release = release_file.read_bytes()
wanted = hashlib.sha256(release).hexdigest()
rows = [line.split('  ', 1) for line in manifest.read_text().splitlines()]
matches = [h for h, p in rows if p == '/usr/share/liuqin/kernel.release']
if matches != [wanted]:
    raise SystemExit('root filesystem and kernel release do not match')
PY
if [ "$kernel_source_kind" = git ]; then
	source_epoch=$(git -C "$kernel_source" show -s --format=%ct HEAD)
else
	# SOURCE_DATE_EPOCH from the CI artifact keeps the image deterministic.
	source_epoch=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('source_date_epoch', 0))" "$kernel_info")
	[ -n "$source_epoch" ] || source_epoch=0
fi
charger_mode=auto
if [ -n "${INSTALLER_RUNTIME:-}" ]; then charger_mode=0; fi
mkdir -p "$out_dir"

python3 "$project_root/tools/lib/build-root-contract.py" --profile native \
	--device-layer-manifest "$native_root_hashes" --output "$out_dir/native-root.contract"

LIUQIN_STORAGE_MODE=persistent LIUQIN_ROOT_PROFILE=native LIUQIN_EMBED_ROOTFS=0 \
	LIUQIN_CHARGER_MODE="$charger_mode" \
	ROOTFS=none SOURCE_DATE_EPOCH="$source_epoch" SLOT_SUCCESS_GCC="$slot_cc" \
	TOUCH_FIRMWARE_DIR="$firmware_pool/touch-nt36532/vendor/firmware" \
	BT_FIRMWARE_DIR="$firmware_pool/bt-qca6490/vendor/bt_firmware/image" \
	WLAN_BOARD_FILE="$firmware_pool/wlan-qca6490/vendor/firmware_mnt/image/qca6490/bd_m81.elf" \
	WLAN_FIRMWARE_DIR="$firmware_pool/wlan-qca6490/upstream/WCN6855/hw2.0" \
	WLAN_HSP2_TUPLE="$wlan_tuple" \
	REGULATORY_FIRMWARE_DIR="$firmware_pool/regulatory/upstream" \
	GPU_FIRMWARE_DIR="$firmware_pool/gpu-adreno730/vendor" \
	DSP_FIRMWARE_DIR="$firmware_pool/dsp-sm8475/vendor/qcom/sm8475/liuqin" \
	AUDIO_TOPOLOGY="$audio_topology" \
	NATIVE_ROOT_CONTRACT="$out_dir/native-root.contract" NATIVE_ROOT_MANIFEST="$native_root_hashes" \
	OUT_DIR="$out_dir/initramfs" sh "$project_root/tools/lib/build-initramfs.sh"

python3 - "$out_dir/initramfs/liuqin-firstboot.cpio.gz" "$out_dir/liuqin-firstboot.cpio.gz" <<'PY'
import gzip, sys
from pathlib import Path
raw = gzip.decompress(Path(sys.argv[1]).read_bytes())
Path(sys.argv[2]).write_bytes(gzip.compress(raw, compresslevel=1, mtime=0))
PY

# ABL takes the kernel command line from /chosen; keep the boot header empty.
python3 - "$cmdline" "$out_dir/cmdline-overlay.dts" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[2]).write_text('/dts-v1/;\n/plugin/;\n/ { fragment@0 { target-path = "/chosen"; '
                           '__overlay__ { bootargs = ' + json.dumps(sys.argv[1]) + '; }; }; };\n')
PY
"$dtc" -@ -q -I dts -O dtb -o "$out_dir/cmdline-overlay.dtbo" "$out_dir/cmdline-overlay.dts"
"$fdtoverlay" -i "$raw_dtb" -o "$out_dir/input.dtb" "$out_dir/cmdline-overlay.dtbo"

KERNEL_OUT="$kernel_out" IMAGE="$image" DTB="$out_dir/input.dtb" \
	RAMDISK="$out_dir/liuqin-firstboot.cpio.gz" DTC="$dtc" FDTOVERLAY="$fdtoverlay" \
	MKBOOTIMG_DIR="$mk_dir" STOCK_OVERLAY_DIR="$stock_overlay_dir" STOCK_BASE_DIR="$stock_base_dir" \
	ABL_OVERLAY_SINK=1 ABL_DTB02_IDS=0 CMDLINE="$cmdline" HEADER_CMDLINE= \
	OUT_DIR="$out_dir/boot" sh "$project_root/tools/lib/build-bootimg.sh"
mv "$out_dir/boot/boot-liuqin-firstboot.img" "$out_dir/boot-liuqin-native.img"

{
	printf 'status=OFFLINE_BUILT\n'
	if [ "$kernel_source_kind" = git ]; then
		printf 'kernel_commit=%s\n' "$(git -C "$kernel_source" rev-parse HEAD)"
	else
		printf 'kernel_commit=%s\n' "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['commit'])" "$kernel_info")"
	fi
	printf 'source_date_epoch=%s\n' "$source_epoch"
	printf 'image_sha256=%s\n' "$(sha "$image")"
	printf 'raw_dtb_sha256=%s\n' "$(sha "$raw_dtb")"
	printf 'native_root_hashes_sha256=%s\n' "$(sha "$native_root_hashes")"
	printf 'contract_sha256=%s\n' "$(sha "$out_dir/native-root.contract")"
	printf 'ramdisk_sha256=%s\n' "$(sha "$out_dir/liuqin-firstboot.cpio.gz")"
	printf 'boot_sha256=%s\n' "$(sha "$out_dir/boot-liuqin-native.img")"
} >"$out_dir/native-boot.identity"
cat "$out_dir/native-boot.identity"
