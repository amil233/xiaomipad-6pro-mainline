#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""检查 device/sensors/patches/*.patch 里每个 hunk 的行数与 header 一致。

改补丁时最容易犯、又最难从日志看出来的错误：往 hunk 里插了几行却没更新
``@@ -a,b +c,d @@`` 的计数。git apply 会因此拒绝或错位应用，而错误信息通常
指向"补丁不适用"，看不出真正原因。

用法：python3 tools/verify-patches.py [目录]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIR = ROOT / "device" / "sensors" / "patches"

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
FILE_HEADER = re.compile(r"^(diff --git |--- |\+\+\+ )")


def check_patch(path: Path) -> list[str]:
    problems: list[str] = []
    lines = path.read_text().splitlines()
    i = 0
    while i < len(lines):
        match = HUNK.match(lines[i])
        if not match:
            i += 1
            continue
        want_old = int(match.group(2)) if match.group(2) is not None else 1
        want_new = int(match.group(4)) if match.group(4) is not None else 1
        j = i + 1
        old = new = 0
        while j < len(lines) and not lines[j].startswith("@@"):
            line = lines[j]
            if line.startswith("diff --git "):
                break
            if line in ("-- ", "--"):
                break  # git 的签名尾（"\n-- \n2.x.y"），不是 hunk 内容
            if line.startswith("+") and not line.startswith("+++ "):
                new += 1
            elif line.startswith("-") and not line.startswith("--- "):
                old += 1
            elif line.startswith(" "):
                old += 1
                new += 1
            else:
                break
            j += 1
        if (old, new) != (want_old, want_new):
            problems.append(
                f"{path.name}:{i + 1}: header says -{want_old}/+{want_new}, "
                f"content has -{old}/+{new}"
            )
        i = j
    return problems


def main() -> int:
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DIR
    if not directory.is_dir():
        print(f"not a directory: {directory}", file=sys.stderr)
        return 2
    patches = sorted(directory.glob("*.patch"))
    if not patches:
        print(f"no patches in {directory}", file=sys.stderr)
        return 2
    problems: list[str] = []
    for patch in patches:
        problems.extend(check_patch(patch))
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"patch hunks OK ({len(patches)} patches)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
