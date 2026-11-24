#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Build the optional fingerprint package from the repository sources against
# the target 26.04.1 libfprint/TOD ABI and the current kernel's FPC module.
#
# This is deliberately separate from the generic rootfs build: it needs the
# matching kernel module, the tablet's fpcliu.* firmware and a candidate
# configuration, and the result must be accepted on the tablet before it is
# added to an image.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kernel_module=
firmware=
candidate=
revision=
out=$project_root/out/fingerprint-self

die() { printf 'build-liuqin-fingerprint-self: %s\n' "$*" >&2; exit 1; }

usage() {
	cat <<'USAGE'
usage: build-liuqin-fingerprint-self.sh --kernel-module FILE --firmware DIR \
       --candidate-config FILE --revision VERSION [--out DIR]

  --kernel-module FILE    fpc1264_spi_diag.ko from the current kernel artifact
  --firmware DIR          fpcliu.mdt/fpcliu.b* extracted from modem_a
  --candidate-config FILE JSON with linux_username, linux_uid, kernel_release,
                          base_kernel and boot_image_sha256
  --revision VERSION      package version, e.g. 7.3-1
  --out DIR               fresh output directory (default out/fingerprint-self)

Also needs:
  - FPRINTD_SOURCE pointing at the extracted fprintd-1.94.5 source;
  - libfprint-2-tod-dev, libfprint-2-dev, meson, ninja, pkg-config, gcc;
  - the target 26.04.1 root libraries visible to pkg-config.
USAGE
}

while [ $# -gt 0 ]; do
	case $1 in
	--kernel-module) [ $# -ge 2 ] || die '--kernel-module needs a value'; kernel_module=$2; shift 2 ;;
	--firmware) [ $# -ge 2 ] || die '--firmware needs a value'; firmware=$2; shift 2 ;;
	--candidate-config) [ $# -ge 2 ] || die '--candidate-config needs a value'; candidate=$2; shift 2 ;;
	--revision) [ $# -ge 2 ] || die '--revision needs a value'; revision=$2; shift 2 ;;
	--out) [ $# -ge 2 ] || die '--out needs a value'; out=$2; shift 2 ;;
	-h | --help) usage; exit 0 ;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -n "$kernel_module" ] || die '--kernel-module is required'
[ -n "$firmware" ] || die '--firmware is required'
[ -n "$candidate" ] || die '--candidate-config is required'
[ -n "$revision" ] || die '--revision is required'
[ -n "${FPRINTD_SOURCE:-}" ] || die 'set FPRINTD_SOURCE to the extracted fprintd-1.94.5 tree'
[ -d "$FPRINTD_SOURCE" ] || die "FPRINTD_SOURCE is not a directory: $FPRINTD_SOURCE"
[ -f "$kernel_module" ] || die "kernel module is missing: $kernel_module"
[ -f "$firmware/fpcliu.mdt" ] || die "firmware has no fpcliu.mdt: $firmware"
[ -f "$candidate" ] || die "candidate config is missing: $candidate"

command -v pkg-config >/dev/null 2>&1 || die 'pkg-config is required'
command -v meson >/dev/null 2>&1 || die 'meson is required'
command -v ninja >/dev/null 2>&1 || die 'ninja is required'
pkg-config --exists libfprint-2-tod-1 ||
	die 'libfprint-2-tod-1 development files are required (run on 26.04.1 with libfprint-2-tod-dev)'
pkg-config --exists libfprint-2 ||
	die 'libfprint-2 development files are required (libfprint-2-dev)'

out=$(realpath -m -- "$out")
case $out in
"$project_root"/out/*) ;;
*) die "output must be below $project_root/out" ;;
esac
[ ! -e "$out" ] || die "output already exists: $out"
mkdir -p "$out/clients" "$out/stage" "$out/debs"

python3 - "$candidate" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
missing = [key for key in ('linux_username', 'linux_uid', 'kernel_release',
                           'base_kernel', 'boot_image_sha256') if key not in config]
if missing:
    raise SystemExit('candidate config is missing: ' + ', '.join(missing))
PY

say() { printf 'build-liuqin-fingerprint-self: %s\n' "$*"; }

say 'static clients'
OUT_DIR="$out/clients" sh "$project_root/tools/build-liuqin-fingerprint-oem.sh" clients
say 'native TOD, PAM and private fprintd'
OUT_DIR="$out" FPRINTD_SOURCE="$FPRINTD_SOURCE" \
	sh "$project_root/tools/build-liuqin-fingerprint-oem.sh" native
say 'packing the public build inputs'
python3 "$project_root/device/fingerprint/oem/tools/package_fingerprint.py" \
	--stage "$out/stage" --build "$out" \
	--kernel-module "$kernel_module" --candidate-config "$candidate" \
	--firmware "$firmware" --revision "$revision" \
	--output "$out/fingerprint-build-inputs.tar.gz"
say 'building the Debian package'
python3 "$project_root/tools/build-liuqin-fingerprint-deb.py" \
	--bundle "$out/fingerprint-build-inputs.tar.gz" --out "$out/debs" \
	--version "$revision"
say "package: $out/debs/liuqin-fingerprint_${revision}_arm64.deb"
say "inputs:  $out/fingerprint-build-inputs.tar.gz"
