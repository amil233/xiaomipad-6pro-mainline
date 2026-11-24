#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host-side checks for tools/build-liuqin-boot.sh (no device access).

A boot image is only valid for the kernel artifact it was assembled from and
the root filesystem it will meet on the tablet.  The wrapper enforces both
links before calling the assembler; this test drives its --check path with a
synthetic artifact, so a regression in the gates is caught without dtc, a
kernel tree or a tablet.
"""
import gzip
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/build-liuqin-boot.sh"


def load_contract_module():
    spec = importlib.util.spec_from_file_location(
        "liuqin_root_contract", ROOT / "tools/lib/build-root-contract.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def newc_header(name, size, ino, mode):
    fields = (ino, mode, 0, 0, 1, 0, size, 0, 0, 0, 0, len(name) + 1, 0)
    return b"070701" + b"".join(f"{value:08x}".encode() for value in fields)


def newc_member(name, body, ino, mode):
    header = newc_header(name, len(body), ino, mode)
    data = header + name.encode() + b"\0"
    data += b"\0" * (-len(data) % 4)
    data += body + b"\0" * (-len(body) % 4)
    return data


def write_ramdisk(path, contract):
    archive = b""
    for index, (name, body, mode) in enumerate(
            (("etc", b"", 0o040755), ("etc/liuqin-native-root.contract", contract, 0o100644))):
        archive += newc_member(name, body, index + 1, mode)
    archive += newc_member("TRAILER!!!", b"", 0, 0)
    path.write_bytes(gzip.compress(archive, mtime=0))


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def write_sums(directory, names):
    rows = []
    for name in names:
        rows.append(f"{sha256((directory / name).read_bytes())}  {name}\n")
    (directory / "SHA256SUMS").write_text("".join(rows))


def run(*arguments, expect=0):
    result = subprocess.run(["sh", str(TOOL), *map(str, arguments)],
                            capture_output=True, text=True)
    if expect == 0 and result.returncode != 0:
        raise AssertionError(f"tool failed ({result.returncode}):\n{result.stdout}\n{result.stderr}")
    if expect != 0 and result.returncode == 0:
        raise AssertionError(f"tool unexpectedly succeeded: {' '.join(map(str, arguments))}")
    return result


def main():
    lock = json.loads((ROOT / "kernel/source.json").read_text())
    commit, dtb = lock["commit"], lock["dtb"]
    contract = load_contract_module()
    pinned = contract.PROFILE_PINS["native"][0]

    with tempfile.TemporaryDirectory(prefix="liuqin-boot-") as directory:
        work = Path(directory)
        artifact = work / "ci" / f"liuqin-kernel-{commit}"
        kernel, modules = artifact / "kernel", artifact / "kernel-modules"
        (kernel / f"arch/arm64/boot/dts/{dtb}").parent.mkdir(parents=True)
        modules.mkdir()
        (kernel / "build-info.json").write_text(json.dumps({"commit": commit}) + "\n")
        (kernel / "arch/arm64/boot/Image").write_bytes(b"kernel image fixture\n")
        (kernel / f"arch/arm64/boot/dts/{dtb}").write_bytes(b"dtb fixture\n")
        write_sums(kernel, ["arch/arm64/boot/Image", f"arch/arm64/boot/dts/{dtb}"])
        (modules / "kernel.release").write_text("7.3.0-fixture\n")
        write_sums(modules, ["kernel.release"])

        # A manifest that satisfies every pinned native path, then the contract
        # and the ramdisk that carries it, exactly as build-liuqin-native-root.sh
        # and build-liuqin-native-boot.sh would.
        manifest = work / "native-root.hashes"
        manifest.write_text("".join(f"{sha256(path.encode())}  {path}\n" for path in pinned))
        contract_path = work / "native.contract"
        subprocess.run([sys.executable, str(ROOT / "tools/lib/build-root-contract.py"),
                        "--profile", "native", "--device-layer-manifest", str(manifest),
                        "--output", str(contract_path)],
                       capture_output=True, check=True)
        ramdisk = work / "firstboot.cpio.gz"
        write_ramdisk(ramdisk, contract_path.read_bytes())

        # --- the happy path -------------------------------------------------
        result = run("--check", "--kernel", artifact, "--ramdisk", ramdisk,
                     "--native-hashes", manifest)
        assert "check PASS" in result.stdout, result.stdout
        assert commit[:6] in result.stdout, result.stdout
        result = run("--check", "--kernel", artifact, "--ramdisk", ramdisk,
                     "--native-hashes", manifest, "--deb")
        assert "would package" in result.stdout, result.stdout

        # A kernel-only change reuses the installed root's ramdisk; any change
        # to the root makes that ramdisk refuse it.
        changed = work / "changed.hashes"
        changed.write_text(manifest.read_text().replace(sha256(pinned[0].encode()), "0" * 64))
        result = run("--check", "--kernel", artifact, "--ramdisk", ramdisk,
                     "--native-hashes", changed, expect=1)
        assert "built for a different root filesystem" in result.stderr, result.stderr

        # --- artifact gates -------------------------------------------------
        (kernel / "arch/arm64/boot/Image").write_bytes(b"tampered kernel image\n")
        result = run("--check", "--kernel", artifact, "--ramdisk", ramdisk,
                     "--native-hashes", manifest, expect=1)
        assert "checksum failure" in result.stderr, result.stderr
        (kernel / "arch/arm64/boot/Image").write_bytes(b"kernel image fixture\n")

        (kernel / "build-info.json").write_text(json.dumps({"commit": "0" * 40}) + "\n")
        result = run("--check", "--kernel", artifact, "--ramdisk", ramdisk,
                     "--native-hashes", manifest, expect=1)
        assert "does not match kernel/source.json" in result.stderr, result.stderr
        (kernel / "build-info.json").write_text(json.dumps({"commit": commit}) + "\n")

        # A ramdisk without the contract cannot be checked, so it must not be
        # silently accepted either.
        empty_ramdisk = work / "empty.cpio.gz"
        empty_ramdisk.write_bytes(gzip.compress(
            newc_member("etc", b"", 1, 0o040755) + newc_member("TRAILER!!!", b"", 0, 0), mtime=0))
        result = run("--check", "--kernel", artifact, "--ramdisk", empty_ramdisk,
                     "--native-hashes", manifest, expect=1)
        assert "no etc/liuqin-native-root.contract" in result.stderr, result.stderr

    print("PASS: artifact identity, checksums, root-contract pairing and refusal of a stale ramdisk")


if __name__ == "__main__":
    main()
