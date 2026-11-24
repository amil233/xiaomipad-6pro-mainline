#!/bin/sh
# Fetch the static ARM64 BusyBox used by the initramfs.
#
# The package comes from the Ubuntu archive through apt, which checks it
# against the signed package metadata; no hash is stored or generated here.
# Only the AArch64/static shape the initramfs needs is checked afterwards.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
download_dir=${DOWNLOAD_DIR:-"$project_root/tools/local/downloads"}
extract_dir=${EXTRACT_DIR:-"$project_root/tools/local/busybox-arm64"}

die() { printf 'fetch-busybox-arm64: %s\n' "$*" >&2; exit 1; }

mkdir -p "$download_dir" "$extract_dir"
command -v apt-get >/dev/null 2>&1 || die 'apt-get is required (Ubuntu build host)'

# Refresh nothing here: the caller's package lists decide the version, and apt
# verifies the download against their signed metadata.
(cd "$download_dir" && apt-get download busybox-static)
package=$(ls -t "$download_dir"/busybox-static_*_arm64.deb 2>/dev/null | head -n 1)
[ -n "$package" ] || die 'apt-get download produced no busybox-static arm64 package'

dpkg-deb --field "$package" Package Version Architecture
[ "$(dpkg-deb --field "$package" Architecture)" = arm64 ] ||
	die 'package architecture is not arm64'
dpkg-deb --extract "$package" "$extract_dir"

binary=$extract_dir/usr/bin/busybox
[ -x "$binary" ] || die "extracted BusyBox is missing: $binary"
file "$binary" | grep -q 'ELF 64-bit LSB.*ARM aarch64' ||
	die 'the extracted busybox is not an AArch64 executable'
if readelf -l "$binary" | grep -q INTERP; then
	die 'the extracted busybox is dynamically linked'
fi
printf 'busybox: %s (%s bytes)\n' "$binary" "$(stat -c %s "$binary")"
