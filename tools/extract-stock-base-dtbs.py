#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Split the concatenated DTB area of a stock vendor_boot image into dtb-NN.dtb.

unpack_bootimg.py (from tools/fetch-aosp-mkbootimg.sh) extracts vendor_boot's
DTB area as one file holding several FDTs back to back; build-bootimg.sh
enumerates them as `dtb-[0-9][0-9].dtb` and requires exactly 14 for liuqin, so
a wrong split or ROM version fails the build rather than the boot. Usage:

    python3 tools/extract-stock-base-dtbs.py <vendor_boot.img> <output-dir>

or, with the vendor_boot image already unpacked:

    python3 tools/extract-stock-base-dtbs.py --from-unpacked <unpacked-dir> <output-dir>
"""
import struct
import subprocess
import sys
from pathlib import Path

FDT_MAGIC = 0xD00DFEED

args = sys.argv[1:]
from_unpacked = args[:1] == ['--from-unpacked']
if from_unpacked:
    args = args[1:]
if len(args) != 2:
    sys.exit(__doc__.strip())
src, out = Path(args[0]), Path(args[1])
project_root = Path(__file__).resolve().parents[1]

if from_unpacked:
    unpacked = src
else:
    unpacker = project_root / 'tools/local/aosp-mkbootimg/unpack_bootimg.py'
    if not unpacker.exists():
        sys.exit(f'cannot find {unpacker}; run tools/fetch-aosp-mkbootimg.sh first')
    unpacked = project_root / 'out' / 'vb-unpacked'
    unpacked.mkdir(parents=True, exist_ok=True)
    subprocess.run(['python3', str(unpacker), '--boot_img', str(src),
                    '--out', str(unpacked)], check=True)
dtb_area = unpacked / 'dtb'
if not dtb_area.exists():
    sys.exit(f'{unpacked}: no dtb area found (is this a vendor_boot image?)')
blob = dtb_area.read_bytes()

out.mkdir(parents=True, exist_ok=True)
i, n = 0, 0
while i < len(blob):
    if struct.unpack('>I', blob[i:i + 4])[0] != FDT_MAGIC:
        # The DTB area is concatenated without padding; probe forward in
        # four-byte steps so a surprise gap still surfaces instead of
        # truncating the set.
        j = i + 4
        while j < len(blob) and struct.unpack('>I', blob[j:j + 4])[0] != FDT_MAGIC:
            j += 4
        if j >= len(blob):
            sys.exit(f'0x{n}: trailing {len(blob) - i} bytes are not an FDT')
        print(f'warning: skipped {j - i} non-FDT bytes at offset {i}')
        i = j
    total = struct.unpack('>I', blob[i + 4:i + 8])[0]
    if i + total > len(blob):
        sys.exit(f'dtb-{n:02d}: FDT at offset {i} claims {total} bytes past EOF')
    (out / f'dtb-{n:02d}.dtb').write_bytes(blob[i:i + total])
    print(f'dtb-{n:02d}.dtb: {total} bytes at offset {i}')
    n += 1
    i += total
print(f'{n} base DTBs written to {out}')
