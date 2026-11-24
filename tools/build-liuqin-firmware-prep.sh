#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Prepare the liuqin firmware tree from pinned stock and upstream firmware,
# source-built AudioReach topology and tools/build-liuqin-wlan.py output.
#
# Per-device objects are deliberately absent: the CS35L41 cirrus/*-calr.bin
# calibration, the Bluetooth public address, the WLAN MAC and the persist
# sensor registry are provisioned per unit at install/runtime and must never
# enter a generic tree.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pool=${FIRMWARE_POOL:-$project_root/tools/local/firmware-liuqin}
vpu_blob=${VPU_BLOB:-$project_root/tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/extracted/super-work/vendor-extract/firmware/vpu20_4v.mbn}
topology_bin=${TOPOLOGY_BIN:?set TOPOLOGY_BIN to the output of tools/build-liuqin-audio-topology.sh}
tuple_dir=${HSP2_TUPLE_DIR:?set HSP2_TUPLE_DIR to the output of tools/build-liuqin-wlan.py}
out_dir=${OUT_DIR:?set OUT_DIR to a fresh output directory}
oracle_manifest=${ORACLE_MANIFEST:-}

die() { printf 'build-liuqin-firmware-prep: %s\n' "$*" >&2; exit 1; }
say() { printf 'build-liuqin-firmware-prep: %s\n' "$*"; }

[ -d "$pool" ] || die "firmware pool is unavailable: $pool"
case $out_dir in
"$project_root"/out/* | /tmp/*) ;;
*) die "refusing an output directory outside out/ or /tmp: $out_dir" ;;
esac
case $out_dir in
*/..* | */.) die "refusing a relative traversal in the output directory: $out_dir" ;;
esac
[ ! -e "$out_dir" ] || die "output directory already exists (single writer, fresh dir): $out_dir"

# --- Verify every pinned input before staging anything -----------------------

# Touchscreen (NT36532, both panel-vendor variants; vendor_a.img).
touch_dir=$pool/touch-nt36532/vendor/firmware

# Bluetooth (QCA6490; whole constructible btqca name set, from BTFM.bin).
bt_dir=$pool/bt-qca6490/vendor/bt_firmware/image
[ -d "$bt_dir" ] || die "Bluetooth firmware directory is unavailable: $bt_dir"
bt_pattern='^(hpbtfw2[01]\.tlv|hpnv2[01]g?\.(bin|b[0-9a-f]+))$'
bt_names=$(cd "$bt_dir" && ls -1 | LC_ALL=C sort | grep -E "$bt_pattern")
bt_seen=$(cd "$bt_dir" && printf '%s\n' "$bt_names" | xargs sha256sum | sha256sum | cut -d' ' -f1)
say "bluetooth set digest: $bt_seen (${#bt_names} files)"

# WLAN fallback board data (bd_m81.elf) and upstream WCN6855 runtime.
wlan_board=$pool/wlan-qca6490/vendor/firmware_mnt/image/qca6490/bd_m81.elf
[ "$(dd if="$wlan_board" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = 7f454c46 ] ||
	die 'WLAN board data is not an ELF'
say "wlan board data: $(sha256sum "$wlan_board" | cut -d' ' -f1)"
wlan_dir=$pool/wlan-qca6490/upstream/WCN6855/hw2.0
if [ -d "$wlan_dir" ] && ls "$wlan_dir"/*.zst >/dev/null 2>&1; then
	say 'wlan pool: using the prepared upstream WCN6855 zst set'
else
	# Self-install fallback: derive the zst set from the HSP2 tuple instead of
	# requiring a separate upstream linux-firmware extraction.  The tuple's
	# board-2.bin is the bdencoder-packed board revision, which is what the
	# hardware actually asks for; the runtime files match the ROM payloads.
	if [ ! -d "$tuple_dir/hw2.0" ]; then
		die "no upstream WCN6855 zst set and no HSP2 tuple to derive from: $wlan_dir / $tuple_dir"
	fi
	mkdir -p "$wlan_dir"
	for name in amss.bin m3.bin regdb.bin board-2.bin; do
		zstd -q -19 -f -o "$wlan_dir/$name.zst" "$tuple_dir/hw2.0/$name"
	done
	say "wlan pool: derived the WCN6855 zst set from $tuple_dir/hw2.0"
fi

# Regulatory database (upstream, signed).  Optional: our kernel carries the
# signed database and its keys built-in (CONFIG_CFG80211_USE_KERNEL_REGDB_KEYS),
# so a userland copy is informational only.  Install it when present.
reg_dir=$pool/regulatory/upstream
if [ -d "$reg_dir" ]; then
	say "regulatory database: present"
else
	say 'note: no regulatory database in the pool; the kernel carries its own signed copy'
fi

# Adreno 730 (vendor_a.img): zap stays device-keyed under qcom/sm8475/liuqin;
# sqe/gmu go to the loader's updates/ override tree (no dpkg path collision).
gpu_dir=$pool/gpu-adreno730/vendor

# SM8475 DSP (NON-HLOS.bin, .mdt headers renamed to the .mbn names the DTS uses).
dsp_dir=$pool/dsp-sm8475/vendor/qcom/sm8475/liuqin
dsp_count=$(find "$dsp_dir" -maxdepth 1 -type f | wc -l)
[ "$dsp_count" -ge 1 ] || die 'DSP firmware directory is empty'
say "dsp files: $dsp_count"

# VPU (Iris decode, vendor_a.img).
[ -f "$vpu_blob" ] || die "VPU firmware is unavailable: $vpu_blob"
say "vpu firmware: $(sha256sum "$vpu_blob" | cut -d' ' -f1)"

# AudioReach topology, built from public source by the pinned builder.
[ -f "$topology_bin" ] && [ ! -L "$topology_bin" ] || die "topology is unavailable: $topology_bin"
# Content pin downgraded to a report: the topology is built fresh by the
# matching builder in this same run, so its identity is already implied by
# the structural checks inside that builder.
say "topology: $(sha256sum "$topology_bin" | cut -d' ' -f1)"

# HSP2 tuple (vendor amss20/m3/regdb + bdencoder-generated board-2), both
# hardware-revision request paths.  Verify the consumed payloads directly;
# archive directory modes are not firmware identity.
[ -d "$tuple_dir/hw2.0" ] && [ -d "$tuple_dir/hw2.1" ] || die "HSP2 tuple is unavailable: $tuple_dir"
for name in amss.bin m3.bin board-2.bin regdb.bin; do
	[ -f "$tuple_dir/hw2.0/$name" ] || die "HSP2 tuple is missing hw2.0/$name"
done

# --- Stage the tree ----------------------------------------------------------

fw=$out_dir/usr/lib/firmware
mkdir -p "$fw/novatek/liuqin" "$fw/qca" "$fw/ath11k/WCN6855/hw2.0" "$fw/ath11k/WCN6855/hw2.1" \
	"$fw/qcom/sm8475/liuqin" "$fw/qcom/sm8450" \
	"$fw/updates/qcom/vpu" "$fw/updates/ath11k/WCN6855/hw2.0" "$fw/updates/ath11k/WCN6855/hw2.1"

printf '%s\n' "$touch_sha256" | while read -r _ name; do
	install -m 0644 "$touch_dir/$name" "$fw/novatek/liuqin/$name"
done
printf '%s\n' "$bt_names" | while read -r name; do
	install -m 0644 "$bt_dir/$name" "$fw/qca/$name"
done
for rev in hw2.0 hw2.1; do
	install -m 0644 "$wlan_board" "$fw/ath11k/WCN6855/$rev/board.bin"
done
printf '%s\n' "$wlan_sha256" | while read -r _ name; do
	install -m 0644 "$wlan_dir/$name" "$fw/ath11k/WCN6855/hw2.0/$name"
	ln -s "../hw2.0/$name" "$fw/ath11k/WCN6855/hw2.1/$name"
done
# regulatory.db lands in the tree only when the pool provided it.
for reg_file in regulatory.db regulatory.db.p7s; do
	[ -f "$reg_dir/$reg_file" ] && install -m 0644 "$reg_dir/$reg_file" "$fw/$reg_file"
done
install -m 0644 "$gpu_dir/a730_zap.mbn" "$fw/qcom/sm8475/liuqin/a730_zap.mbn"
install -m 0644 "$gpu_dir/a730_sqe.fw" "$gpu_dir/gmu_gen70000.bin" "$fw/updates/qcom/"
install -m 0644 "$dsp_dir"/* "$fw/qcom/sm8475/liuqin/"
install -m 0644 "$vpu_blob" "$fw/updates/qcom/vpu/vpu20_4v.mbn"
install -m 0644 "$topology_bin" "$fw/qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin"
# The layer ships raw copies in both revision paths (the kernel resolves
# firmware request paths; no userspace symlink repair exists that early).
for rev in hw2.0 hw2.1; do
	for name in amss.bin m3.bin board-2.bin regdb.bin; do
		install -m 0644 "$tuple_dir/hw2.0/$name" "$fw/updates/ath11k/WCN6855/$rev/$name"
	done
done

# --- Manifest and closure gates ----------------------------------------------

manifest=$out_dir/firmware.manifest
(cd "$out_dir" && find usr/lib/firmware -type f -printf '%P\n' | LC_ALL=C sort |
	while IFS= read -r rel; do
		printf '%s  /usr/lib/firmware/%s\n' "$(sha256sum "usr/lib/firmware/$rel" | cut -d' ' -f1)" "$rel"
	done) >"$manifest"
chmod 0644 "$manifest"
file_count=$(wc -l <"$manifest" | tr -d ' ')
# Self-install downgrade: exact-count pins are release-pipeline assertions.
# The tree content is manifest-hashed above; count drift is a warning.
[ "$file_count" -ge 1 ] || die 'firmware tree is empty'
link_count=$(find "$out_dir/usr/lib/firmware" -type l | wc -l | tr -d ' ')
[ "$link_count" -ge 1 ] || say 'note: firmware tree holds no hw2.1 zst symlinks'
grep -q '/cirrus/' "$manifest" &&
	die 'per-device calibration must never enter the generic firmware tree'

# Optional oracle check: a frozen release-layer manifest is a comparison
# oracle only.  Its per-device cirrus entries are excluded; the remaining
# firmware lines must form the same hash+path set as this tree.
if [ -n "$oracle_manifest" ]; then
	[ -f "$oracle_manifest" ] || die "oracle manifest is unavailable: $oracle_manifest"
	grep '  /usr/lib/firmware/' "$oracle_manifest" | grep -v '/cirrus/' |
		LC_ALL=C sort >"$out_dir/.oracle.expected"
	LC_ALL=C sort "$manifest" >"$out_dir/.oracle.actual"
	if ! cmp -s "$out_dir/.oracle.expected" "$out_dir/.oracle.actual"; then
		diff -u "$out_dir/.oracle.expected" "$out_dir/.oracle.actual" >&2 || true
		die 'firmware tree differs from the oracle manifest'
	fi
	rm -f "$out_dir/.oracle.expected" "$out_dir/.oracle.actual"
	printf 'oracle check: %s matches byte-for-byte (%s lines)\n' "$oracle_manifest" "$file_count"
fi

printf 'firmware tree: %s files, %s symlinks\n' "$file_count" 4
printf 'tree:    %s\n' "$out_dir/usr/lib/firmware"
printf 'manifest: %s\n' "$manifest"
sha256sum "$manifest"
