#!/usr/bin/env python3
"""Collect the vendor display golden snapshot from a rooted stock Android.

Where to run: on the host that has `adb` in PATH and the tablet on USB
(Windows / Linux / macOS alike), from the repository root:

    python3 tools/collect-vendor-display-snapshot.py out/vendor-display

Why this pushes a script instead of running many `adb shell su -c ...` calls:
adb joins its arguments with spaces and lets the remote shell re-split them, so
quoting breaks differently on Windows and on Android. Pushing one script and
running it under a single `su` is deterministic and needs only one prompt.

Requirements on the device: stock Android booted, Magisk installed, `su`
granted (`adb shell su -c id` prints uid=0).
"""
import argparse
import os
import subprocess
import sys

REMOTE_DIR = "/data/local/tmp/dispsnap"
REMOTE_SCRIPT = "/data/local/tmp/dispsnap.sh"

DUMP = r"""
OUT=__OUT__

# debugfs is often not mounted on Android user builds
mount -t debugfs none /sys/kernel/debug 2>/dev/null

save() { # save <name> <command...>
    name="$1"; shift
    "$@" > "$OUT/$name.txt" 2>"$OUT/$name.err"
    [ -s "$OUT/$name.txt" ] || rm -f "$OUT/$name.txt"
    [ -s "$OUT/$name.err" ] || rm -f "$OUT/$name.err"
}

save cmdline        cat /proc/cmdline
save dmesg          dmesg
save interrupts     cat /proc/interrupts
save clk-summary    cat /sys/kernel/debug/clk/clk_summary
save debugfs-tree   ls -la /sys/kernel/debug
save drm            ls -la /sys/class/drm
save backlight      ls -la /sys/class/backlight
save prop-display   sh -c "getprop | grep -iE 'display|panel|dsi|drm'"

# find any node that looks like a display register dumper
find /sys/kernel/debug -maxdepth 3 \
     \( -iname '*dsi*' -o -iname '*mdss*' -o -iname '*sde*' -o -iname '*disp*' \) \
     > "$OUT/display-nodes.txt" 2>/dev/null

# common vendor dumper names; whatever exists gets dumped
for f in /sys/kernel/debug/dsi0/dsi0_dump /sys/kernel/debug/dsi1/dsi1_dump \
         /sys/kernel/debug/dsi0/dsi0_reg  /sys/kernel/debug/dsi1/dsi1_reg \
         /sys/kernel/debug/mdss/mdss_dump /sys/kernel/debug/mdss/mdss_reg \
         /sys/kernel/debug/msm_display/dump; do
    [ -r "$f" ] || continue
    name=$(echo "$f" | sed 's|/sys/kernel/debug/||; s|/|_|g')
    save "$name" cat "$f"
done
"""


def adb(args, **kw):
    return subprocess.run(["adb"] + args, capture_output=True, text=True, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir", help="local directory to write the snapshot into")
    args = ap.parse_args()

    if adb(["version"]).returncode != 0:
        sys.exit("adb not found in PATH")

    state = adb(["get-state"]).stdout.strip()
    if state != "device":
        sys.exit(f"adb state is {state!r}, expected 'device' "
                 "(unlock the tablet / authorise USB debugging)")

    probe = adb(["shell", "su", "-c", "id"])
    if "uid=0" not in probe.stdout:
        sys.exit("`adb shell su -c id` did not return uid=0 — open Magisk once on "
                 f"the device and grant the request.\nstdout={probe.stdout!r}\n"
                 f"stderr={probe.stderr!r}")

    os.makedirs(args.outdir, exist_ok=True)
    tmp = os.path.abspath(os.path.join(args.outdir, ".dump.sh"))
    with open(tmp, "w", newline="\n") as f:
        f.write("#!/system/bin/sh\nmkdir -p %s\nrm -f %s/*\n" % (REMOTE_DIR, REMOTE_DIR))
        f.write(DUMP.replace("__OUT__", REMOTE_DIR))

    for step, cmd in (
        ("clean remote dir", ["shell", "rm", "-rf", REMOTE_DIR]),
        ("push script", ["push", tmp, REMOTE_SCRIPT]),
        ("dump", ["shell", "su", "-c", "sh " + REMOTE_SCRIPT]),
        ("pull", ["pull", REMOTE_DIR, args.outdir]),
    ):
        res = adb(cmd, timeout=900)
        if res.returncode != 0:
            sys.exit(f"{step} failed: rc={res.returncode}\n{res.stdout}\n{res.stderr}")

    os.remove(tmp)
    pulled = os.path.join(args.outdir, "dispsnap")
    if os.path.isdir(pulled):
        for name in sorted(os.listdir(pulled)):
            os.replace(os.path.join(pulled, name), os.path.join(args.outdir, name))
        os.rmdir(pulled)

    names = sorted(os.listdir(args.outdir))
    print(f"{len(names)} file(s) in {args.outdir}:")
    for name in names:
        print(f"  {os.path.getsize(os.path.join(args.outdir, name)):>9}  {name}")


if __name__ == "__main__":
    main()
