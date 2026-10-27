#!/usr/bin/env python3
"""Collect the vendor display golden snapshot from a rooted stock Android.

Where to run: on the host with `adb` in PATH and the tablet on USB, from the
repository root:

    python3 tools/collect-vendor-display-snapshot.py out/vendor-display

The device must be booted from a Magisk-patched boot image built from *its own*
ROM version (mismatched versions leave magiskd down and `su` unavailable), with
`su` granted.

Node names come from the vendor source (CAF techpack/display):
  dsi_ctrl.c    -> <display>/dsi0/{state_info,reg_dump,cmd_dma_stats}
  dsi_display.c -> <display>/{dump_info,esd_check_mode,cmd_sched_params,misr_data}
  sde_connector.c -> <connector>/{tx_cmd,rx_cmd}   (DCS read/write from userland)
  sde_core_irq.c  -> core_irq
  sde_crtc.c      -> <crtc>/{status,state,fps,fence_status}
The exact directory names differ per build, so everything is discovered by
walking the tree rather than hard-coded.
"""
import argparse
import os
import subprocess
import sys

REMOTE_DIR = "/data/local/tmp/dispsnap"
REMOTE_SCRIPT = "/data/local/tmp/dispsnap.sh"

DUMP = r"""
OUT=__OUT__
mkdir -p "$OUT"

mount -t debugfs none /sys/kernel/debug 2>/dev/null

save() { # save <name> <command...>
    name="$1"; shift
    "$@" > "$OUT/$name.txt" 2>"$OUT/$name.err"
    [ -s "$OUT/$name.txt" ] || rm -f "$OUT/$name.txt"
    [ -s "$OUT/$name.err" ] || rm -f "$OUT/$name.err"
}

save cmdline        cat /proc/cmdline
save uname          uname -a
save dmesg          dmesg
save interrupts     cat /proc/interrupts
save clk-summary    cat /sys/kernel/debug/clk/clk_summary
save debugfs-tree   ls -la /sys/kernel/debug
save drm            ls -la /sys/class/drm
save backlight      ls -la /sys/class/backlight
save prop-display   sh -c "getprop | grep -iE 'display|panel|dsi|drm'"

# --- DSI / SDE debugfs: walk two levels and dump every small regular file ---
for d in $(find /sys/kernel/debug -maxdepth 3 -name 'reg_dump' -o -maxdepth 3 -name 'dump_info' 2>/dev/null | xargs -r -n1 dirname | sort -u); do
    base=$(echo "$d" | sed 's|/sys/kernel/debug/||; s|/|_|g')
    for f in "$d"/*; do
        [ -f "$f" ] || continue
        [ -r "$f" ] || continue
        sz=$(wc -c < "$f" 2>/dev/null || echo 0)
        [ "$sz" -gt 4000000 ] && continue
        save "${base}_$(basename "$f")" cat "$f"
    done
done

# CRTC / encoder / IRQ nodes
for f in $(find /sys/kernel/debug -maxdepth 4 \( -name 'core_irq' -o -name 'fps' \
        -o -name 'fence_status' -o -name 'state' -o -name 'status' \) 2>/dev/null); do
    [ -r "$f" ] || continue
    name=$(echo "$f" | sed 's|/sys/kernel/debug/||; s|/|_|g')
    save "$name" cat "$f"
done

# --- panel DCS readback through the connector's rx_cmd ---
# write format: "<expected_len> <dcs bytes...>"; read returns the response
for f in $(find /sys/kernel/debug/drm -name 'rx_cmd' 2>/dev/null); do
    d=$(dirname "$f")
    tag=$(echo "$d" | sed 's|/sys/kernel/debug/drm/||; s|/|_|g')
    for spec in "0x0A:power_mode" "0x0D:display_mode" "0x0B:address_mode" "0x0C:pixel_format"; do
        cmd=${spec%%:*}
        label=${spec##*:}
        printf '1 %s' "$cmd" > "$f" 2>/dev/null
        save "dcs_${tag}_${label}" cat "$f"
    done
done

# DSI register names the vendor registered with the debug framework
save sde-dbg-sets   sh -c "ls /sys/kernel/debug/sde_dbg 2>/dev/null"
for f in /sys/kernel/debug/sde_dbg/*dump*; do
    [ -r "$f" ] || continue
    save "sde_dbg_$(basename $f)" cat "$f"
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
        f.write("#!/system/bin/sh\nrm -rf %s\n" % REMOTE_DIR)
        f.write(DUMP.replace("__OUT__", REMOTE_DIR))

    for step, cmd in (
        ("push script", ["push", tmp, REMOTE_SCRIPT]),
        ("dump", ["shell", "su", "-c", "sh " + REMOTE_SCRIPT]),
        ("pull", ["pull", REMOTE_DIR, args.outdir]),
    ):
        res = adb(cmd, timeout=1800)
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
        print(f"  {os.path.getsize(os.path.join(args.outdir, name)):>10}  {name}")
    if not any(n.startswith("dcs_") for n in names):
        print("\nWARNING: no dcs_* files — the connector rx_cmd node was not "
              "found or the panel rejected the read; see *.err files.")


if __name__ == "__main__":
    main()
