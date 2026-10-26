#!/usr/bin/env python3
"""Collect the vendor display golden snapshot from a rooted stock Android.

Runs on the host that has `adb` in PATH, with the device already booted from
the Magisk-patched stock boot image and `su` granted.

Every command's stdout goes to <outdir>/<name>.txt; failures are recorded in
<outdir>/_errors.txt instead of aborting, so one missing node does not cost the
whole session.
"""
import argparse
import os
import subprocess
import sys

# (file name, shell command run through `su -c`)
COMMANDS = [
    ("debugfs-tree", "ls -la /sys/kernel/debug/"),
    ("debugfs-display-nodes",
     "find /sys/kernel/debug -maxdepth 3 \\( -iname '*dsi*' -o -iname '*mdss*' "
     "-o -iname '*sde*' -o -iname '*disp*' \\) 2>/dev/null"),
    ("clk-summary", "cat /sys/kernel/debug/clk/clk_summary"),
    ("interrupts", "cat /proc/interrupts"),
    ("dmesg", "dmesg"),
    ("panel-nodes", "ls -la /sys/class/drm/ 2>/dev/null; ls /sys/class/backlight/ 2>/dev/null"),
    ("cmdline", "cat /proc/cmdline"),
    ("prop-display",
     "getprop | grep -iE 'display|panel|dsi|drm' 2>/dev/null"),
]

# Vendor debugfs register dumps: names differ per build, so try the common ones.
DUMP_CANDIDATES = [
    ("dsi0-dump", "/sys/kernel/debug/dsi0/dsi0_dump"),
    ("dsi1-dump", "/sys/kernel/debug/dsi1/dsi1_dump"),
    ("dsi0-reg", "/sys/kernel/debug/dsi0/dsi0_reg"),
    ("dsi1-reg", "/sys/kernel/debug/dsi1/dsi1_reg"),
    ("mdss-dump", "/sys/kernel/debug/mdss/mdss_dump"),
    ("mdss-reg", "/sys/kernel/debug/mdss/mdss_reg"),
    ("sde-dump", "/sys/kernel/debug/sde_rotator/sde_dump"),
]


def run(cmd, timeout=120):
    return subprocess.run(["adb", "shell", "su", "-c", cmd],
                          capture_output=True, text=True, timeout=timeout)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir", help="directory to write the snapshot into")
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    probe = run("id")
    if "uid=0" not in probe.stdout:
        sys.exit(f"`adb shell su -c id` did not return uid=0:\n"
                 f"stdout={probe.stdout!r}\nstderr={probe.stderr!r}")

    errors = []
    for name, cmd in COMMANDS:
        try:
            res = run(cmd)
        except subprocess.TimeoutExpired:
            errors.append(f"{name}: timeout")
            continue
        if res.returncode != 0 and not res.stdout:
            errors.append(f"{name}: rc={res.returncode} {res.stderr.strip()[:200]}")
            continue
        with open(os.path.join(args.outdir, name + ".txt"), "w") as f:
            f.write(res.stdout)
        print(f"wrote {name}.txt ({len(res.stdout)} bytes)")

    for name, path in DUMP_CANDIDATES:
        res = run(f"cat {path}")
        if res.returncode == 0 and res.stdout.strip():
            with open(os.path.join(args.outdir, name + ".txt"), "w") as f:
                f.write(res.stdout)
            print(f"wrote {name}.txt ({len(res.stdout)} bytes)")
        else:
            errors.append(f"{name}: {path} unreadable")

    with open(os.path.join(args.outdir, "_errors.txt"), "w") as f:
        f.write("\n".join(errors) + "\n")
    print(f"\n{len(errors)} item(s) not collected, see _errors.txt")


if __name__ == "__main__":
    main()
