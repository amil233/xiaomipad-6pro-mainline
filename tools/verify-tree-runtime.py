#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""检查一棵根文件系统树里的程序在启动时需要的库是否都在树里。

设备上"服务起不来"最常见的一类原因不是代码错，而是动态链接阶段就退出了：
二进制需要某个 soname，树里没有。这类失败在 CI 上完全可以离线判定——读 ELF 的
PT_INTERP 和 DT_NEEDED，顺着依赖链一路查到树的库目录里，不需要设备。

    tools/verify-tree-runtime.py TREE [PATH...]

PATH 是树内的绝对路径，可以用 shell 通配（由 shell 展开）。不给 PATH 时检查
liuqin 传感器链上会真正被执行的那几个文件。

只做静态解析，不执行目标架构的代码，所以 x86_64 主机上也能查 aarch64 的树。
"""

from __future__ import annotations

import os
import struct
import sys
from pathlib import Path

# 默认只查传感器链上"会被内核/服务管理器执行"的文件。整棵树全扫会连发行版的
# 可选插件一起报，噪声大于价值。
DEFAULT_TARGETS = [
    "/usr/bin/hexagonrpcd",
    "/usr/bin/ssccli",
    "/usr/libexec/liuqin-iio-sensor-proxy",
    "/usr/libexec/iio-sensor-proxy",
    "/usr/lib64/libssc.so*",
    "/usr/lib64/libhexagonrpc.so*",
]

# soname 在这些目录（树内的绝对路径）里找。Fedora 用 lib64，Debian 系在
# lib/<multiarch> 下，因此三个都收。
LIB_DIRS = ["/usr/lib64", "/usr/lib", "/lib64", "/lib"]

PT_LOAD, PT_DYNAMIC, PT_INTERP = 1, 2, 3
DT_NEEDED, DT_STRTAB, DT_STRSZ, DT_RPATH, DT_RUNPATH = 1, 5, 10, 15, 29
ET_EXEC, ET_DYN = 2, 3


class ElfError(Exception):
    pass


def read_elf(path: Path) -> dict | None:
    """读出解释器、NEEDED、RPATH/RUNPATH。不是 ELF 时返回 None。"""
    with open(path, "rb") as f:
        ident = f.read(16)
        if len(ident) < 16 or ident[:4] != b"\x7fELF":
            return None
        if ident[4] != 2:  # 只处理 ELF64，目标机都是 aarch64/x86_64
            raise ElfError("not ELF64")
        endian = "<" if ident[5] == 1 else ">"
        (e_type, _machine, _version, _entry, phoff, _shoff, _flags,
         _ehsize, phentsize, phnum, _shentsize, _shnum, _shstrndx) = \
            struct.unpack(endian + "HHIQQQIHHHHHH", f.read(48))

        loads, dynamic, interp = [], None, None
        for i in range(phnum):
            f.seek(phoff + i * phentsize)
            p_type, _pflags, p_offset, p_vaddr, _paddr, p_filesz, _p_memsz, _p_align = \
                struct.unpack(endian + "IIQQQQQQ", f.read(56))
            if p_type == PT_LOAD:
                loads.append((p_vaddr, p_offset, p_filesz))
            elif p_type == PT_DYNAMIC:
                dynamic = (p_offset, p_filesz)
            elif p_type == PT_INTERP:
                f.seek(p_offset)
                interp = f.read(p_filesz).split(b"\0", 1)[0].decode("utf-8", "replace")

        if dynamic is None:
            return {"interp": interp, "needed": [], "runpath": []}

        entries = []
        f.seek(dynamic[0])
        raw = f.read(dynamic[1])
        for off in range(0, len(raw) - 15, 16):
            tag, val = struct.unpack(endian + "qQ", raw[off:off + 16])
            if tag == 0:  # DT_NULL
                break
            entries.append((tag, val))

        def vaddr_to_offset(vaddr: int) -> int | None:
            for v_start, f_off, f_size in loads:
                if v_start <= vaddr < v_start + f_size:
                    return f_off + (vaddr - v_start)
            return None

        strtab = next((val for tag, val in entries if tag == DT_STRTAB), None)
        strsz = next((val for tag, val in entries if tag == DT_STRSZ), 0)
        if strtab is None:
            raise ElfError("no DT_STRTAB")
        str_off = vaddr_to_offset(strtab)
        if str_off is None:
            raise ElfError("DT_STRTAB does not map to a file offset")
        f.seek(str_off)
        strings = f.read(strsz)

        def get_str(val: int) -> str:
            return strings[val:].split(b"\0", 1)[0].decode("utf-8", "replace")

        needed = [get_str(val) for tag, val in entries if tag == DT_NEEDED]
        runpath = []
        for tag, val in entries:
            if tag in (DT_RPATH, DT_RUNPATH):
                runpath.extend(p for p in get_str(val).split(":") if p)
        # $ORIGIN 相对路径在这套件里用不到；出现就原样留着，下面按"找不到"处理。
        return {"interp": interp, "needed": needed, "runpath": runpath,
                "type": "exec" if e_type == ET_EXEC else "lib"}


def build_index(root: Path) -> dict[str, Path]:
    """树里所有库文件的 basename -> 路径。"""
    index: dict[str, Path] = {}
    for lib_dir in LIB_DIRS:
        base = root / lib_dir.lstrip("/")
        if not base.is_dir():
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            for name in filenames:
                if ".so" not in name:
                    continue
                index.setdefault(name, Path(dirpath) / name)
    return index


def resolve(name: str, runpath: list[str], root: Path, index: dict[str, Path]) -> Path | None:
    for entry in runpath:
        if entry.startswith("/"):
            candidate = root / entry.lstrip("/") / name
            if candidate.exists():
                return candidate
    found = index.get(name)
    if found is not None:
        return found
    # 没有索引命中时再看一眼 multiarch 目录名（lib/<tuple>/）。
    return None


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} TREE [PATH...]", file=sys.stderr)
        return 2
    root = Path(sys.argv[1])
    if not (root / "usr").is_dir():
        print(f"{sys.argv[0]}: not a root tree: {root}", file=sys.stderr)
        return 2

    targets: list[Path] = []
    patterns = sys.argv[2:] or DEFAULT_TARGETS
    for pattern in patterns:
        matches = sorted(root.glob(pattern.lstrip("/")))
        if not matches:
            print(f"MISSING  {pattern}  (nothing to check)", file=sys.stderr)
            return 1
        targets.extend(matches)

    index = build_index(root)
    problems: list[str] = []
    seen: set[Path] = set()
    queue: list[tuple[Path, str]] = [(t, "target") for t in targets]
    checked = 0

    while queue:
        path, why = queue.pop(0)
        real = path.resolve()
        if real in seen:
            continue
        seen.add(real)
        try:
            info = read_elf(path)
        except ElfError as exc:
            problems.append(f"{path}: cannot parse: {exc}")
            continue
        if info is None:
            problems.append(f"{path}: not an ELF file")
            continue
        checked += 1

        if info["interp"]:
            interp = root / info["interp"].lstrip("/")
            if not interp.exists():
                problems.append(f"{path}: interpreter {info['interp']} is not in the tree")

        for needed in info["needed"]:
            found = resolve(needed, info["runpath"], root, index)
            if found is None:
                problems.append(
                    f"{path}: needs {needed}, which is not in the tree's library directories")
                continue
            # 递归查这一层库自己的依赖：libssc → libqmi-glib → libqrtr-glib 这类
            # 间接依赖只有走到底才查得到。
            queue.append((found, f"needed by {path.name}"))

    if problems:
        for problem in problems:
            print(f"ERROR {problem}", file=sys.stderr)
        print(f"{len(problems)} unresolved runtime dependenc"
              f"{'y' if len(problems) == 1 else 'ies'}", file=sys.stderr)
        return 1

    print(f"runtime dependencies OK ({checked} ELF file(s) resolved inside {root})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
