#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""检查我们自己的 unit 里引用的 unit 名字是否都存在。

只针对本仓库 ``device/fedora-overlay`` 下的 unit，因为这里的名字是自己写的：
``Requires=liuqin-ssc-sample-gate.service`` 少写一个字母时，systemd 只会报
"unit not found"，不会让构建失败——那类错误只能靠静态检查抓。

允许引用系统自带的 unit（在 SYSTEM_UNITS 里），以及上游包提供的 unit
（例如 iio-sensor-proxy.service），其余必须能在 overlay 里找到。
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OVERLAY = ROOT / "device" / "fedora-overlay"

# 这些由发行版或上游包提供，不需要在 overlay 里定义。
SYSTEM_UNITS = {
    "systemd-udevd.service",
    "systemd-tmpfiles-setup.service",
    "dbus.service",
    "multi-user.target",
    "graphical.target",
    "basic.target",
    "shutdown.target",
    "iio-sensor-proxy.service",  # 上游 3.9 的单元
    "display-manager.service",   # 显示管理器的通用别名（PLM 上是 plasmalogin）
}


def unit_names() -> set[str]:
    names = set()
    for path in (OVERLAY / "etc" / "systemd").rglob("*"):
        if path.is_file() and path.suffix in {".service", ".target"}:
            names.add(path.name)
    return names


def main() -> int:
    names = unit_names()
    problems: list[str] = []
    # unit 可能在子目录里（.d drop-in、.wants 链接），统一遍历所有文件。
    for path in sorted((OVERLAY / "etc" / "systemd").rglob("*")):
        if not path.is_file() or path.suffix not in {".service", ".target"}:
            continue
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith(("#", ";")):
                continue
            for key in ("Requires=", "After=", "Before=", "Wants=", "Conflicts="):
                if not line.startswith(key):
                    continue
                for ref in line[len(key):].split():
                    if ref in names or ref in SYSTEM_UNITS:
                        continue
                    problems.append(f"{path.relative_to(ROOT)}: {key}{ref} 未定义")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"unit references OK ({len(names)} units)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
