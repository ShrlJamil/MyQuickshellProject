import QtQuick
import Quickshell.Io

// Screen magnifier toggle: drives Hyprland's built-in cursor zoom
// (cursor:zoom_factor) through the Lua eval channel. The classic
// `hyprctl keyword` route is dead on this build ("unknown request"),
// hl.config via eval is the runtime path and is read back with
// getoption.
//
// Behaviour measured live on Hyprland 0.57 (2026-11-16): at activation
// the zoom anchors by relative-position preservation (the cursor keeps
// its relative spot in the frame; the view is NOT centred on it).
// zoom_rigid is forced false on every toggle: non-rigid keeps the view
// still while the cursor roams inside it and pans just enough when the
// cursor leaves the view (edge-pan), while rigid would lock the view
// at the activation anchor for good. SUPER+Z (Hyprland config,
// modules/keybinds.lua) is the keyboard escape out of this mode.
Item {
    id: root

    property bool active: false
    property real factor: 1.0
    property real zoomFactor: 2.0

    function toggle() {
        if (setProc.running) return

        const target = root.active ? 1.0 : root.zoomFactor
        setProc.command = ["hyprctl", "eval",
            "hl.config({ cursor = { zoom_factor = " + target.toFixed(1) + ", zoom_rigid = false } })"]
        setProc.running = true
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true

        onTriggered: {
            if (!checkProc.running) checkProc.running = true
        }
    }

    Process {
        id: checkProc

        command: ["hyprctl", "getoption", "cursor:zoom_factor", "-j"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            try {
                const data = JSON.parse(checkProc.stdout.text)
                root.factor = data.float
                root.active = data.float > 1.01
            } catch (e) {
                // Unparseable reply: keep the last known state.
            }
        }
    }

    Process {
        id: setProc

        command: ["true"]

        onExited: checkProc.running = true
    }
}
