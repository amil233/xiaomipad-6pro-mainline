#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
download_dir="$project_root/tools/local/downloads"
extract_dir="$project_root/tools/local/aosp-mkbootimg"
commit=954bc3ead5e679005fddf3484d247f2557b3c2c9
archive="aosp-mkbootimg-$commit.tar.gz"
url="https://android.googlesource.com/platform/system/tools/mkbootimg/+archive/$commit.tar.gz"
mkbootimg_sha256=37d84b3d162e0bc62e36c1f4e1c63c85ea0caa9f29be023eb2f8efe006ad948c
unpack_sha256=06b54dd9a07c5281778e29e234e76f6e3faee8bf0c904a5ef88fdee30eeed12e

mkdir -p "$download_dir" "$extract_dir"

# The +archive tarball carries generation timestamps, so its own bytes vary
# between downloads of the same commit -- the archive level cannot be pinned,
# only the extracted files can.  Integrity therefore lands on the two file
# checks below; a corrupt cached archive fails the extraction or those checks.
if [ ! -f "$download_dir/$archive" ]; then
	curl --fail --location "$url" --output "$download_dir/$archive.part"
	mv "$download_dir/$archive.part" "$download_dir/$archive"
fi

tar -xzf "$download_dir/$archive" -C "$extract_dir"
echo "$mkbootimg_sha256  $extract_dir/mkbootimg.py" | sha256sum --check
echo "$unpack_sha256  $extract_dir/unpack_bootimg.py" | sha256sum --check

printf 'AOSP tag: android-16.0.0_r4\ncommit: %s\n' "$commit"
python3 "$extract_dir/mkbootimg.py" --help >/dev/null
python3 "$extract_dir/unpack_bootimg.py" --help >/dev/null
