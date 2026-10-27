#!/system/bin/sh
# Dump the vendor DSI controller and PHY register windows on the stock ROM.
#
# Run on a rooted MIUI14 liuqin with the screen ON and unlocked:
#   adb push tools/dump-vendor-dsi-regs.sh /data/local/tmp/
#   adb shell su -c "sh /data/local/tmp/dump-vendor-dsi-regs.sh" > regs.txt
#
# The paired "<blk>_off" file takes "<offset> <count>" in hex WITHOUT a 0x
# prefix (the kernel parses it with sscanf("%5x %x")), and "<blk>_reg" then
# reads that many bytes of live MMIO starting at that offset.  The default
# window is only 0x5c bytes, which stops before the PHY timing registers
# (0xb4..0xe8) and the DSC compression control (0x2a0), hence widening it.

DEBUG=/sys/kernel/debug/dri/0/debug

if [ ! -d "$DEBUG" ]; then
	echo "no $DEBUG - is debugfs mounted and is this the stock kernel?" >&2
	exit 1
fi

cd "$DEBUG" || exit 1

# 0x400 covers the whole DSI controller register file; 0xa00 the PHY one.
for blk in dsi0_ctrl dsi1_ctrl; do
	echo "0 400" > "${blk}_off" 2>/dev/null
	echo "=== $blk (offset 0x0, 0x400 bytes) ==="
	cat "${blk}_reg" 2>/dev/null
	echo
done

for blk in dsi0_phy dsi1_phy; do
	echo "0 a00" > "${blk}_off" 2>/dev/null
	echo "=== $blk (offset 0x0, 0xa00 bytes) ==="
	cat "${blk}_reg" 2>/dev/null
	echo
done

# What mode the vendor is running right now, so mode dependent fields can be
# interpreted (the snapshot captured 900x2880@144 while the DT default is 120).
echo "=== dump_info ==="
for f in /sys/kernel/debug/*/dump_info; do
	[ -r "$f" ] && cat "$f"
done

echo "=== state_info ==="
for f in /sys/kernel/debug/*/dsi-ctrl-*/state_info; do
	[ -r "$f" ] && cat "$f"
done
