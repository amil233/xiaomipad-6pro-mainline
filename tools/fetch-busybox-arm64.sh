#!/bin/sh
# Fetch the static ARM64 BusyBox used by the initramfs.
#
# No hash is stored in the repository: the package is identified by its
# dpkg fields and its AArch64/static binary shape, and the extracted files are
# recorded in tools/local/busybox-arm64/SHA256SUMS for later comparison.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
download_dir="$project_root/tools/local/downloads"
extract_dir="$project_root/tools/local/busybox-arm64"
package=busybox-static_1.36.1-6ubuntu3.1_arm64.deb
url="http://ports.ubuntu.com/pool/main/b/busybox/$package"

mkdir -p "$download_dir" "$extract_dir"

if [ ! -f "$download_dir/$package" ]; then
	curl --fail --location "$url" --output "$download_dir/$package.part"
	mv "$download_dir/$package.part" "$download_dir/$package"
fi
dpkg-deb --field "$download_dir/$package" Package Version Architecture
if [ "$(dpkg-deb --field "$download_dir/$package" Architecture)" != arm64 ]; then
	printf 'fetch-busybox-arm64: package architecture is not arm64\n' >&2
	exit 1
fi
dpkg-deb --extract "$download_dir/$package" "$extract_dir"
file "$extract_dir/usr/bin/busybox" | grep -q 'ELF 64-bit LSB.*ARM aarch64' ||
	die 'the extracted busybox is not an AArch64 executable'
(cd "$extract_dir" && find usr -type f -print0 | LC_ALL=C sort -z |
	xargs -0 sha256sum >SHA256SUMS)
printf 'busybox: %s\n' "$(sha256sum "$extract_dir/usr/bin/busybox" | cut -d' ' -f1)"
