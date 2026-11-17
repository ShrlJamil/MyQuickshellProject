import QtQuick
import Quickshell.Io

// Night light (hyprsunset) state is owned by this service: it is the
// only actor that starts or stops hyprsunset, so `active` flips
// optimistically in toggle() and is confirmed by ONE pgrep run after
// each toggle, plus one at startup. No repeating poll - the previous
// build ran `pgrep -x hyprsunset` every 2 s. Trade-off: if hyprsunset
// is started or killed from outside the shell, the tile does not
// notice until the next toggle or a shell restart.
Item {
    id: root

    property bool active: false
    property int temperature: 4500

    function toggle() {
        if (toggleProc.running) return

        if (root.active) {
            toggleProc.command = ["pkill", "-x", "hyprsunset"]
        } else {
            toggleProc.command = ["bash", "-c", "hyprsunset -t " + root.temperature + " >/dev/null 2>&1 &"]
        }
        root.active = !root.active
        toggleProc.running = true
    }

    Process {
        id: checkProc

        command: ["pgrep", "-x", "hyprsunset"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: root.active = checkProc.stdout.text.trim() !== ""
    }

    Process {
        id: toggleProc

        command: ["true"]

        onExited: checkProc.running = true
    }

    Component.onCompleted: checkProc.running = true
}
