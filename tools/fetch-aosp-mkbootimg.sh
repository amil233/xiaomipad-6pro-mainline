#!/bin/sh
# Fetch AOSP mkbootimg/unpack_bootimg at a release tag.
#
# The repository is cloned with git, so the files are the tag's real tree and
# git checks the object hashes during the transfer; no separate checksum is
# generated here.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
extract_dir=${EXTRACT_DIR:-"$project_root/tools/local/aosp-mkbootimg"}
tag=${MBOOTIMG_TAG:-android-16.0.0_r4}
url=${MBOOTIMG_URL:-https://android.googlesource.com/platform/system/tools/mkbootimg}

die() { printf 'fetch-aosp-mkbootimg: %s\n' "$*" >&2; exit 1; }

if [ -f "$extract_dir/mkbootimg.py" ] && [ -f "$extract_dir/unpack_bootimg.py" ]; then
	printf 'mkbootimg: using existing checkout %s\n' "$extract_dir"
	python3 "$extract_dir/mkbootimg.py" --help >/dev/null
	python3 "$extract_dir/unpack_bootimg.py" --help >/dev/null
	exit 0
fi
[ ! -e "$extract_dir" ] ||
	die "existing directory is not a complete checkout: $extract_dir (remove it)"

command -v git >/dev/null 2>&1 || die 'git is required'
git clone --quiet --depth 1 --branch "$tag" "$url" "$extract_dir"
commit=$(git -C "$extract_dir" rev-parse HEAD)
printf 'AOSP tag: %s\ncommit: %s\n' "$tag" "$commit"
python3 "$extract_dir/mkbootimg.py" --help >/dev/null
python3 "$extract_dir/unpack_bootimg.py" --help >/dev/null
