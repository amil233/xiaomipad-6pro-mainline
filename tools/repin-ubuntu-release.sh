#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Repin the Ubuntu desktop arm64 release pins for a downloaded ISO.
#
# build-liuqin-ubuntu-desktop-rootfs.sh refuses any ISO that is not the
# verified 26.04 release.  When a newer point release (26.04.1, ...) is to be
# used instead, this tool recomputes the full pin set from the ISO bytes and
# prints it as an export-ready environment block:
#
#   UBUNTU_DESKTOP_ISO_NAME      file name inside the input directory
#   UBUNTU_DESKTOP_ISO_BYTES     byte length
#   UBUNTU_DESKTOP_ISO_SHA256    ISO content hash
#   UBUNTU_DESKTOP_BASE_SHA256   casper/minimal.squashfs
#   UBUNTU_DESKTOP_STANDARD_SHA256  casper/minimal.standard.squashfs
#
# Export those values, point UBUNTU_DESKTOP_INPUT at a fresh directory holding
# the ISO, and run the standard pipeline stages.  The pins are evidence, not
# trust: the ISO itself must still be GPG-verified against the Ubuntu CD Image
# signing key.  Pass --sums-url with the release directory SHA256SUMS to have
# this tool cross-check the ISO hash against Canonical's published list.
#
# Run after downloading the ISO; the tool writes nothing to the input
# directory and needs no root.
set -eu

usage() {
	cat >&2 <<'EOF'
usage: repin-ubuntu-release.sh [--input-dir DIR] [--sums-url URL] [--] ISO

  --input-dir DIR   where the pipeline will look for the ISO (informational:
                    only used to derive UBUNTU_DESKTOP_ISO_NAME when the ISO
                    is already inside it)
  --sums-url URL    published SHA256SUMS of the release directory; the
                    computed ISO hash must appear in it
EOF
	exit 2
}

input_dir=
sums_url=
while [ $# -gt 0 ]; do
	case $1 in
	--input-dir) [ $# -ge 2 ] || usage; input_dir=$2; shift 2 ;;
	--sums-url) [ $# -ge 2 ] || usage; sums_url=$2; shift 2 ;;
	--) shift; break ;;
	-*) usage ;;
	*) break ;;
	esac
done
[ $# -eq 1 ] || usage
iso=$1

die() { printf 'repin-ubuntu-release: %s\n' "$*" >&2; exit 1; }

[ -f "$iso" ] || die "ISO is unavailable: $iso"
[ -r "$iso" ] || die "ISO is not readable: $iso"
command -v 7z >/dev/null || die '7z is required (p7zip); isoinfo silently truncates files >2GiB'
command -v sha256sum >/dev/null || die 'sha256sum is required'

iso_name=$(basename "$iso")
iso_bytes=$(stat -c %s "$iso")
iso_sha256=$(sha256sum "$iso" | cut -d' ' -f1)

# The casper layers decide whether the ISO is even the right shape: a desktop
# ISO carries minimal.squashfs + minimal.standard.squashfs, and extracting
# them exercises the same 7z path the pipeline relies on.  The English-pruning
# layer must not be present -- the pipeline refuses it.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

extract_layer() {
	layer=$1
	out=$work/$layer.squashfs
	7z x -so "$iso" "casper/$layer.squashfs" >"$out" 2>/dev/null ||
		{ rm -f "$out"; die "7z cannot extract casper/$layer.squashfs from $iso_name"; }
	[ -s "$out" ] || { rm -f "$out"; die "7z extracted an empty $layer layer"; }
	[ "$(head -c 4 "$out")" = hsqs ] || { rm -f "$out"; die "$layer layer lacks the squashfs magic"; }
	printf '%s\n' "$out"
}

base_path=$(extract_layer minimal)
standard_path=$(extract_layer minimal.standard)
base_sha256=$(sha256sum "$base_path" | cut -d' ' -f1)
standard_sha256=$(sha256sum "$standard_path" | cut -d' ' -f1)

if 7z l "$iso" 2>/dev/null | grep -q 'casper/minimal\.standard\.en\.squashfs'; then
	die 'the English-pruning layer is present in this ISO; it is not a pipeline input'
fi

# Optional cross-check against Canonical's published checksum list.
if [ -n "$sums_url" ]; then
	command -v curl >/dev/null || die 'curl is required with --sums-url'
	sums=$work/SHA256SUMS
	curl --fail --silent --location --output "$sums" "$sums_url" ||
		die "cannot fetch the published checksum list: $sums_url"
	line=$(printf '%s  %s\n' "$iso_sha256" "$iso_name" | grep -Fxf - "$sums" || true)
	[ -n "$line" ] ||
		die "the ISO hash is absent from the published list: $sums_url
verify you have the release that matches $sums_url, not a look-alike"
	printf 'ISO hash cross-checked against the published SHA256SUMS\n'
fi

# Make UBUNTU_DESKTOP_ISO_NAME relative to the input directory when the ISO is
# already where the pipeline will look for it; otherwise keep the plain name.
iso_pin=$iso_name
if [ -n "$input_dir" ] && [ -d "$input_dir" ]; then
	case $iso in
	"$input_dir"/*) iso_pin=$iso_name ;;
	esac
fi

cat <<EOF
# repin-ubuntu-release: $iso_name
# verified by ISO bytes only -- GPG-check the ISO against the Ubuntu CD Image
# signing key before trusting these pins in a shipped build.
export UBUNTU_DESKTOP_ISO_NAME='$iso_pin'
export UBUNTU_DESKTOP_ISO_BYTES=$iso_bytes
export UBUNTU_DESKTOP_ISO_SHA256=$iso_sha256
export UBUNTU_DESKTOP_BASE_SHA256=$base_sha256
export UBUNTU_DESKTOP_STANDARD_SHA256=$standard_sha256
EOF
printf '\ncasper layers verified: base %s, standard %s\n' "$base_sha256" "$standard_sha256" >&2
