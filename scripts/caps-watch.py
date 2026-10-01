#!/usr/bin/env python3
"""Event-driven Caps Lock watcher for the Quickshell OSD.

Reads every keyboard event node (no hardcoded /dev/input/eventX), blocks on
kernel input events, and prints exactly one `toggle` line per physical Caps
Lock press (value == 1; release/autorepeat ignored).

Stdout is the whole protocol (consumed by a Quickshell SplitParser); stdout
carries nothing else. A per-device reader that fails simply ends quietly -
sysfs polling in OSDService remains the fallback, so partial failure only
narrows coverage instead of breaking the watcher.
"""

import glob
import threading

from evdev import InputDevice, ecodes


def watch(path):
    try:
        dev = InputDevice(path)
    except OSError:
        return
    try:
        for ev in dev.read_loop():
            if (
                ev.type == ecodes.EV_KEY
                and ev.code == ecodes.KEY_CAPSLOCK
                and ev.value == 1
            ):
                print("toggle", flush=True)
    except OSError:
        return


def main():
    threads = []
    for path in sorted(glob.glob("/dev/input/by-id/*-event-kbd")):
        t = threading.Thread(target=watch, args=(path,), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
