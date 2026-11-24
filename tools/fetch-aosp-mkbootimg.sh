#!/bin/sh
# Fetch AOSP mkbootimg/unpack_bootimg at a release tag.
#
# The +archive tarball carries generation timestamps, so the tarball bytes vary
# between downloads; integrity lands on the extracted files, recorded in the
# extract directory's SHA256SUMS.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
download_dir="$project_root/tools/local/downloads"
extract_dir="$project_root/tools/local/aosp-mkbootimg"
tag=android-16.0.0_r4
archive="aosp-mkbootimg-$tag.tar.gz"
url="https://android.googlesource.com/platform/system/tools/mkbootimg/+archive/refs/tags/$tag.tar.gz"

mkdir -p "$download_dir" "$extract_dir"

if [ ! -f "$download_dir/$archive" ]; then
	curl --fail --location "$url" --output "$download_dir/$archive.part"
	mv "$download_dir/$archive.part" "$download_dir/$archive"
fi

tar -xzf "$download_dir/$archive" -C "$extract_dir"
(cd "$extract_dir" && find . -maxdepth 1 -type f -name '*.py' -print0 |
	LC_ALL=C sort -z | xargs -0 sha256sum >SHA256SUMS)

printf 'AOSP tag: %s\n' "$tag"
python3 "$extract_dir/mkbootimg.py" --help >/dev/null
python3 "$extract_dir/unpack_bootimg.py" --help >/dev/null
