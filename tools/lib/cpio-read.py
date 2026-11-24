#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Print one member of a cpio archive (newc/crc), gzip-compressed or plain.

The initramfs is the only copy of the root-filesystem contract that a boot
image enforces, and it carries it as a single file
(etc/liuqin-native-root.contract) inside a 30 MB cpio.  Assembling a boot
image has to compare that file with the root being shipped, so it needs to
read one member without extracting the whole archive.

usage:
  cpio-read.py ARCHIVE PATH          write that member's bytes to stdout
  cpio-read.py --list ARCHIVE        print "mode size path" for every member
"""
import gzip
import sys

MAGIC = (b'070701', b'070702')


def read_members(blob):
    """Yield (name, mode, size, ino, nlink, body) in archive order."""
    offset = 0
    while True:
        if offset + 110 > len(blob):
            raise SystemExit('cpio: truncated header')
        header = blob[offset:offset + 110]
        if header[:6] not in MAGIC:
            raise SystemExit(f'cpio: bad magic at offset {offset}')
        fields = [int(header[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
        ino, mode, nlink, filesize = fields[0], fields[1], fields[4], fields[6]
        namesize = fields[11]
        # The name field includes its terminating NUL; both the name and the
        # file body start on four-byte boundaries.
        name_start = offset + 110
        name = blob[name_start:name_start + namesize - 1].decode('utf-8', 'surrogateescape')
        body_start = (name_start + namesize + 3) & ~3
        body = blob[body_start:body_start + filesize]
        if len(body) != filesize:
            raise SystemExit(f'cpio: truncated body for {name}')
        yield name, mode, filesize, ino, nlink, body
        offset = (body_start + filesize + 3) & ~3
        if name == 'TRAILER!!!':
            return


def main():
    arguments = sys.argv[1:]
    if not arguments or arguments[0] in ('-h', '--help'):
        raise SystemExit(__doc__.strip())
    listing = False
    if arguments and arguments[0] == '--list':
        listing = True
        arguments = arguments[1:]
    if not arguments or len(arguments) > (1 if listing else 2):
        raise SystemExit('cpio-read: expected ARCHIVE [PATH]')
    path = arguments[0]
    try:
        raw = gzip.open(path, 'rb').read()
    except OSError:
        raw = open(path, 'rb').read()
    members = list(read_members(raw))
    if listing:
        for name, mode, size, _ino, _nlink, _body in members:
            print(f'{mode:07o} {size} {name}')
        return
    wanted = arguments[1]
    body = None
    for name, _mode, size, ino, nlink, member in members:
        if name == wanted:
            # A hardlinked member may store its data in any one of its names;
            # report its own body when it has one, otherwise find the sibling
            # that carries it.
            body = member
            if size or nlink == 1:
                break
            for other_name, _other_mode, other_size, other_ino, _n, other in members:
                if other_ino == ino and other_size:
                    body = other
                    break
            break
    if body is None:
        raise SystemExit(f'cpio-read: no such member: {wanted}')
    sys.stdout.buffer.write(body)


if __name__ == '__main__':
    main()
