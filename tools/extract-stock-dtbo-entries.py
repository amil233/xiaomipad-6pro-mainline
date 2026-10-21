#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Split a stock liuqin DTBO image into its entries as entry.N files.

build-bootimg.sh enumerates the stock overlays with `entry.[0-9]+` and
requires exactly 44, and the symbol union it derives from them must total
1781, so a wrong ROM version or a botched split aborts the build instead of
the boot. Usage:

    python3 tools/extract-stock-dtbo-entries.py <dtbo.img> <output-dir>
"""
import struct
import sys
from pathlib import Path

DTBO_MAGIC = 0xD7B7AB1E
FDT_MAGIC = 0xD00DFEED

if len(sys.argv) != 3:
    sys.exit(f'usage: {sys.argv[0]} <dtbo.img> <output-dir>')
src, out = Path(sys.argv[1]), Path(sys.argv[2])
blob = src.read_bytes()
magic, _total, _header_size, entry_size, entry_count, entries_offset, _page_size, _version = \
    struct.unpack('>8I', blob[:32])
if magic != DTBO_MAGIC:
    sys.exit(f'{src}: not a DTBO image (magic 0x{magic:08x})')
out.mkdir(parents=True, exist_ok=True)
for i in range(entry_count):
    off = entries_offset + i * entry_size
    dt_size, dt_offset, entry_id, rev, flags, *_custom = \
        struct.unpack('>9I', blob[off:off + 36])
    fdt = blob[dt_offset:dt_offset + dt_size]
    if struct.unpack('>I', fdt[:4])[0] != FDT_MAGIC:
        sys.exit(f'{src}: entry {i} at {dt_offset} does not point at an FDT')
    (out / f'entry.{i}').write_bytes(fdt)
    print(f'entry.{i}: {dt_size} bytes (id 0x{entry_id:x}, rev 0x{rev:x}, flags 0x{flags:x})')
print(f'{entry_count} entries written to {out}')
