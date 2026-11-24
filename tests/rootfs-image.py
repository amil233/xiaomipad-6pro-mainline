#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host-side checks for tools/build-liuqin-rootfs-image.sh (no device access).

The deployment step turns an assembled root into the ext4 image that
`fastboot flash linux_root` writes.  Three things make that image bootable and
are asserted here: the tree sits below native-root/ (where the initramfs
bind-mounts it), the native-root marker is the one the initramfs pins, and the
kernel release in the root has its module directory.  The home partition entry
is layout, so the tool writes it into the staged copy and must never modify
the input tree.

Run as an ordinary user; root is only needed for the real rootfs.tar.gz path.
"""
import hashlib
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/build-liuqin-rootfs-image.sh"
MARKER = b"liuqin-native-root-v1\n"
HOME_LINE = b"LABEL=LIUQIN_HOME /home ext4 defaults,nofail,x-systemd.device-timeout=30s 0 2\n"


def e2fsprogs():
    found = {}
    for name in ("mke2fs", "e2fsck", "dumpe2fs", "debugfs"):
        path = shutil.which(name)
        if path is None:
            for candidate in (f"/usr/sbin/{name}", f"/sbin/{name}"):
                if Path(candidate).is_file():
                    path = candidate
                    break
        if path is None:
            raise SystemExit(f"test-liuqin-rootfs-image: {name} is required (install e2fsprogs)")
        found[name] = path
    return found


def run(*arguments, expect=0):
    result = subprocess.run(["sh", str(TOOL), *map(str, arguments)], capture_output=True, text=True)
    if expect == 0 and result.returncode != 0:
        raise AssertionError(f"tool failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
    if expect != 0 and result.returncode == 0:
        raise AssertionError(f"tool unexpectedly succeeded: {' '.join(map(str, arguments))}")
    return result


def debugfs(tools, image, request):
    return subprocess.run([tools["debugfs"], "-R", request, str(image)],
                          capture_output=True, text=True, check=True).stdout


def make_tree(root):
    for directory in ("etc", "usr/lib/systemd", "usr/lib/modules/7.3.0-fixture/kernel/drivers/x",
                      "usr/share/liuqin"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    (root / "etc/liuqin-native-root").write_bytes(MARKER)
    (root / "etc/liuqin-native-root").chmod(0o644)
    (root / "etc/fstab").write_bytes(b"UUID=fixture-root / ext4 defaults 0 1\n")
    (root / "usr/lib/systemd/systemd").write_bytes(b"#!/bin/sh\n: systemd fixture\n")
    (root / "usr/lib/systemd/systemd").chmod(0o755)
    (root / "usr/share/liuqin/kernel.release").write_bytes(b"7.3.0-fixture\n")
    (root / "usr/lib/modules/7.3.0-fixture/kernel/drivers/x/x.ko").write_bytes(b"module fixture\n")
    (root / "etc/keep").write_bytes(b"xattr must survive\n")
    (root / "etc/keep").chmod(0o640)
    (root / "sbin-init").symlink_to("/usr/lib/systemd/systemd")


def main():
    tools = e2fsprogs()
    with tempfile.TemporaryDirectory(prefix="liuqin-rootfs-image-") as directory:
        work = Path(directory)
        root, out = work / "root", work / "out"
        make_tree(root)
        os.setxattr(root / "etc/keep", "user.fixture", b"preserved")
        fstab_before = (root / "etc/fstab").read_bytes()
        fstab_hash = hashlib.sha256(fstab_before).hexdigest()

        # --- normal build ---------------------------------------------------
        run("--root", root, "--out", out, "--size", "64M", "--home-size", "32M")
        image, home = out / "rootfs.img", out / "linux_home.img"
        assert image.stat().st_size == 64 * 1024 * 1024, image.stat().st_size
        assert home.stat().st_size == 32 * 1024 * 1024, home.stat().st_size
        for path, label in ((image, "LIUQIN_ROOT"), (home, "LIUQIN_HOME")):
            subprocess.run([tools["e2fsck"], "-fn", str(path)],
                           capture_output=True, check=True)
            head = subprocess.run([tools["dumpe2fs"], "-h", str(path)],
                                  capture_output=True, text=True, check=True).stdout
            assert f"Filesystem volume name:   {label}" in head, head
        assert hashlib.sha256((root / "etc/fstab").read_bytes()).hexdigest() == fstab_hash, \
            "the input tree's fstab was modified"
        staged_fstab = debugfs(tools, image, "cat /native-root/etc/fstab")
        assert staged_fstab.encode().startswith(fstab_before), staged_fstab
        assert staged_fstab.encode().count(b"/home") == 1, staged_fstab
        assert HOME_LINE in staged_fstab.encode(), staged_fstab
        assert "Type: regular" in debugfs(tools, image, "stat /native-root/etc/liuqin-native-root")
        assert "Mode:  0644" in debugfs(tools, image, "stat /native-root/etc/liuqin-native-root")
        assert "Type: directory" in debugfs(
            tools, image, "stat /native-root/usr/lib/modules/7.3.0-fixture")
        assert 'Fast link dest: "/usr/lib/systemd/systemd"' in debugfs(
            tools, image, "stat /native-root/sbin-init")
        assert "user.fixture" in debugfs(tools, image, "ea_list /native-root/etc/keep")
        sums = dict(reversed(line.split("  ", 1))
                    for line in (out / "SHA256SUMS").read_text().splitlines())
        assert set(sums) == {"rootfs.img", "linux_home.img"}, sums
        for name, digest in sums.items():
            assert hashlib.sha256((out / name).read_bytes()).hexdigest() == digest, name

        # A rerun replaces the images and still writes exactly one /home line.
        run("--root", root, "--out", out, "--size", "64M")
        staged_fstab = debugfs(tools, image, "cat /native-root/etc/fstab")
        assert staged_fstab.encode().count(b"/home") == 1, staged_fstab
        assert not home.exists(), "a run without --home-size kept the old home image"

        # --- refusals -------------------------------------------------------
        check_out = work / "check"
        result = run("--root", root, "--out", check_out, "--check")
        assert "check PASS" in result.stdout, result.stdout
        assert not (check_out / "rootfs.img").exists(), "--check wrote an image"

        bad = work / "bad"
        shutil.copytree(root, bad)
        (bad / "etc/liuqin-native-root").write_bytes(b"not the pinned marker\n")
        result = run("--root", bad, "--out", work / "refuse", expect=1)
        assert "marker content mismatch" in result.stderr, result.stderr

        bad = work / "bad-modules"
        shutil.copytree(root, bad)
        shutil.rmtree(bad / "usr/lib/modules")
        result = run("--root", bad, "--out", work / "refuse", expect=1)
        assert "no modules" in result.stderr, result.stderr

        result = run("--root", root, "--out", work / "refuse",
                     "--kernel-release", "7.3.0-other", expect=1)
        assert "does not match" in result.stderr, result.stderr

        result = run("--root", root, "--out", work / "refuse", "--size", "16M", expect=1)
        assert "cannot hold" in result.stderr, result.stderr

        result = run("--root", root, "--out", root / "dist", expect=1)
        assert "inside the input tree" in result.stderr, result.stderr
        assert not (root / "dist").exists(), "the tool created an output directory inside the input tree"

    print("PASS: native-root layout, marker, kernel link, fstab, ownership of the input tree, "
          "home image, checksums and refusals")


if __name__ == "__main__":
    main()
