#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Claim the accelerometer as soon as net.hadess.SensorProxy owns its name.

Run this on the tablet while iio-sensor-proxy is stopped, then start the
service.  It records whether the claim reaches the daemon before coldplug
discovery, which is what the g_idle startup-order change must guarantee.
"""

import time

from gi.repository import Gio, GLib

BUS = "net.hadess.SensorProxy"
PATH = "/net/hadess/SensorProxy"
IFACE = "net.hadess.SensorProxy"
TIMEOUT_SECONDS = 20

start = time.monotonic()


def log(*args):
    print(f"{time.monotonic() - start:7.3f}s", *args, flush=True)


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    loop = GLib.MainLoop()
    state = {"proxy": None, "claimed": False, "seen": False, "done": False}

    def on_properties(proxy, changed, invalidated):
        properties = changed.unpack()
        if "HasAccelerometer" in properties:
            log("HasAccelerometer", properties["HasAccelerometer"])
        if "AccelerometerOrientation" in properties:
            orientation = properties["AccelerometerOrientation"]
            log("orientation", orientation)
            if orientation == "left-up" and not state["done"]:
                state["done"] = True
                loop.quit()

    def on_name(connection, name, owner):
        if not owner or state["seen"]:
            return
        state["seen"] = True
        log("name acquired")

        proxy = Gio.DBusProxy.new_sync(
            bus,
            Gio.DBusProxyFlags.DO_NOT_AUTO_START,
            None,
            BUS,
            PATH,
            IFACE,
            None,
        )
        state["proxy"] = proxy
        proxy.connect("g-properties-changed", on_properties)

        # Claim before reading any property; the point is to reach the daemon
        # while it is still before coldplug discovery.
        try:
            proxy.call_sync(
                "ClaimAccelerometer", None, Gio.DBusCallFlags.NONE, -1, None
            )
            state["claimed"] = True
            log("ClaimAccelerometer sent")
        except Exception as error:  # noqa: BLE001 - report the D-Bus error
            log("claim failed:", error)
            loop.quit()
            return

        try:
            value = proxy.get_cached_property("HasAccelerometer")
            log(
                "HasAccelerometer after claim",
                None if value is None else value.get_boolean(),
            )
        except Exception as error:  # noqa: BLE001 - diagnostic only
            log("property read failed:", error)

    Gio.bus_watch_name(
        Gio.BusType.SYSTEM, BUS, Gio.BusNameWatcherFlags.NONE, on_name, None
    )
    GLib.timeout_add_seconds(TIMEOUT_SECONDS, lambda: (log("timeout"), loop.quit(), False)[-1])
    loop.run()

    if state["claimed"]:
        try:
            state["proxy"].call_sync(
                "ReleaseAccelerometer", None, Gio.DBusCallFlags.NONE, -1, None
            )
            log("ReleaseAccelerometer sent")
        except Exception as error:  # noqa: BLE001 - report the D-Bus error
            log("release failed:", error)


if __name__ == "__main__":
    main()
