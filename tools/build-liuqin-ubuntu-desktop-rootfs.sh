#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Extract the Canonical Ubuntu 26.04 desktop arm64 rootfs from the pinned ISO.
#
# Three stages, each independently gated:
#   1. verify the ISO byte identity (size + sha256, previously GPG-verified
#      against the Ubuntu CD Image signing key);
#   2. extract the two casper layer squashfs images from the ISO without root
#      and verify their pinned hashes -- the English-pruning layer is refused;
#   3. extract base then standard over it with a root unsquashfs, then emit a
#      tree manifest (path, mode, owner, sha256) for comparison and pinning.
#
# Stage 3 needs real root so device nodes, ownership and xattrs survive.  Run
# it as:  sudo tools/build-liuqin-ubuntu-desktop-rootfs.sh extract
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
input_dir=${UBUNTU_DESKTOP_INPUT:-"$project_root/tools/local/ubuntu-desktop-26.04-arm64"}
iso=$input_dir/${UBUNTU_DESKTOP_ISO_NAME:-ubuntu-26.04-desktop-arm64.iso}
iso_url=${UBUNTU_DESKTOP_URL:-https://cdimage.ubuntu.com/ubuntu/releases/26.04/release/ubuntu-26.04-desktop-arm64.iso}
# Every pin below defaults to the verified 26.04 release.  Repin a newer point
# release with tools/repin-ubuntu-release.sh and export the pins it prints
# (UBUNTU_DESKTOP_ISO_BYTES etc.) instead of editing this file.
iso_bytes=${UBUNTU_DESKTOP_ISO_BYTES:-4161089536}
iso_sha256=${UBUNTU_DESKTOP_ISO_SHA256:-c2afd538d66fdd77377d03f1ed2ac76a34f1c116baecc9a8170d68f833121f57}
base_sha256=${UBUNTU_DESKTOP_BASE_SHA256:-82613d06f973778f6d49c817d7eb764a7fd812016a30a7f8006e8f61d718b393}
standard_sha256=${UBUNTU_DESKTOP_STANDARD_SHA256:-fce0e2440cdbb6ebaf03efe3dd844c0e1a3b5facaca913e18f312e30a8f9fdaf}
en_layer_sha256=${UBUNTU_DESKTOP_EN_LAYER_SHA256:-a22be06ccf2e742570aa0a1925cc6b9a616ebbec87466c59480f7df8022272ba}
rootfs=${DESKTOP_ROOTFS:-"$input_dir/rootfs"}

die() { printf 'build-liuqin-ubuntu-desktop-rootfs: %s\n' "$*" >&2; exit 1; }

verify_iso() {
	[ -f "$iso" ] || die "ISO is unavailable: $iso (re-download from https://cdimage.ubuntu.com/ubuntu/releases/26.04/release/)"
	[ "$(stat -c %s "$iso")" = "$iso_bytes" ] || die "ISO size differs from $iso_bytes"
	printf '%s  %s\n' "$iso_sha256" "$iso" | sha256sum -c --quiet - ||
		die 'ISO sha256 mismatch; do not use this file'
}

download_iso() {
	mkdir -p "$input_dir"
	exec 9>"$input_dir/.download.lock"
	flock -n 9 || die 'another ISO download owns this input directory'
	if [ -f "$iso" ]; then
		verify_iso
		printf 'Using cached Ubuntu ISO\n'
		return
	fi
	command -v curl >/dev/null || die 'curl is required'
	# A mirror override must supply the same pinned bytes, never a newer release.
	curl --fail --location --continue-at - --output "$iso.part" "$iso_url"
	[ "$(stat -c %s "$iso.part")" = "$iso_bytes" ] || die 'downloaded ISO size mismatch'
	printf '%s  %s\n' "$iso_sha256" "$iso.part" | sha256sum -c --quiet - ||
		die 'downloaded ISO hash mismatch; remove the .part file before retrying'
	mv "$iso.part" "$iso"
	printf 'Ubuntu ISO downloaded and verified\n'
}

extract_casper() {
	verify_iso
	command -v 7z >/dev/null || die '7z is required (p7zip); isoinfo silently truncates files >2GiB'
	mkdir -p "$input_dir/iso/casper"
	for layer in minimal minimal.standard; do
		out=$input_dir/iso/casper/$layer.squashfs
		7z x -so "$iso" "casper/$layer.squashfs" >"$out.tmp" 2>/dev/null
		[ -s "$out.tmp" ] || { rm -f "$out.tmp"; die "7z extracted an empty $layer layer"; }
		[ "$(head -c 4 "$out.tmp")" = hsqs ] || { rm -f "$out.tmp"; die "$layer layer lacks the squashfs magic"; }
		mv "$out.tmp" "$out"
	done
	printf '%s  %s\n' "$base_sha256" "$input_dir/iso/casper/minimal.squashfs" \
		| sha256sum -c --quiet - || die 'base layer hash mismatch'
	printf '%s  %s\n' "$standard_sha256" "$input_dir/iso/casper/minimal.standard.squashfs" \
		| sha256sum -c --quiet - || die 'standard layer hash mismatch'
	printf 'casper layers verified: base %s, standard %s\n' "$base_sha256" "$standard_sha256"
}

extract_rootfs() {
	[ "$(id -u)" = 0 ] || die "stage 3 must run as real root (sudo $0 extract)"
	[ -f "$input_dir/iso/casper/minimal.squashfs" ] || extract_casper
	printf '%s  %s\n' "$base_sha256" "$input_dir/iso/casper/minimal.squashfs" \
		| sha256sum -c --quiet - || die 'base layer hash mismatch'
	printf '%s  %s\n' "$standard_sha256" "$input_dir/iso/casper/minimal.standard.squashfs" \
		| sha256sum -c --quiet - || die 'standard layer hash mismatch'
	[ ! -e "$rootfs" ] || die "refusing to overwrite an existing rootfs: $rootfs"
	# The English-pruning layer carries device-node/hardlink deletion
	# semantics, not a language delta; it must never be applied.
	if [ -f "$input_dir/iso/casper/minimal.standard.en.squashfs" ]; then
		printf '%s  %s\n' "$en_layer_sha256" "$input_dir/iso/casper/minimal.standard.en.squashfs" \
			| sha256sum -c --quiet - || :
		die 'the English-pruning layer is present; remove it, it is not an input'
	fi
	unsquashfs -d "$rootfs" "$input_dir/iso/casper/minimal.squashfs" >/dev/null
	unsquashfs -f -d "$rootfs" "$input_dir/iso/casper/minimal.standard.squashfs" >/dev/null
	write_manifest
}

write_manifest() {
	# The tree is root-owned with unreadable directories (e.g. apt lists
	# partial/); an unprivileged run sees a partial tree.  Require real root
	# and treat any find failure as fatal -- a truncated manifest is a false
	# identity, worse than none.
	[ "$(id -u)" = 0 ] || die "manifest stage must run as real root (sudo $0 manifest)"
	manifest=${DESKTOP_ROOTFS_MANIFEST:-"$input_dir/rootfs.manifest"}
	tmp=$manifest.tmp
	paths=$manifest.paths.tmp
	(cd "$rootfs" && find . -printf '%y %m %u:%g %p\n') >"$paths" ||
		{ rm -f "$paths"; die 'find over the rootfs failed; refusing a truncated manifest'; }
	LC_ALL=C sort -k4 "$paths" >"$paths.sorted"
	mv "$paths.sorted" "$paths"
	: >"$tmp"
	while IFS= read -r line; do
		type=${line%% *}; rest=${line#* }
		path=${rest#* }; path=${path#* }
		case $type in
		f) printf '%s  %s\n' "$(cd "$rootfs" && sha256sum "$path" | cut -d' ' -f1)" "$line" ||
			{ rm -f "$tmp" "$paths"; die "sha256 failed for $path"; } ;;
		*) printf '%s  %s\n' '-' "$line" ;;
		esac
	done <"$paths" >"$tmp"
	rm -f "$paths"
	entries=$(wc -l <"$tmp" | tr -d ' ')
	[ "$entries" -ge 100000 ] ||
		{ rm -f "$tmp"; die "manifest is implausibly small: $entries entries"; }
	mv "$tmp" "$manifest"
	chmod 0644 "$manifest"
	printf 'tree manifest: %s (%s entries)\n' "$manifest" "$entries"
	sha256sum "$manifest"
}

case ${1:-} in
download) download_iso ;;
verify-iso) verify_iso; printf 'ISO verified: %s bytes, %s\n' "$iso_bytes" "$iso_sha256" ;;
casper) extract_casper ;;
extract) extract_rootfs ;;
manifest) [ -d "$rootfs" ] || die "rootfs is unavailable: $rootfs"; write_manifest ;;
*) die 'usage: build-liuqin-ubuntu-desktop-rootfs.sh download|verify-iso|casper|extract|manifest' ;;
esac
