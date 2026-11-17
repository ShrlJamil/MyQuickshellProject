import QtQuick
import Quickshell.Io
import "../osd"

Item {
    id: root

    property int brightness: 0

    property int _max: 0
    property int _target: -1

    function setBrightness(v) {
        root._target = Math.max(1, Math.min(100, Math.round(v)))
        root.brightness = root._target
        OSDService.brightnessShow(root._target)
        applyTimer.restart()
    }

    Timer {
        id: applyTimer

        interval: 45
        onTriggered: {
            if (root._target < 0 || setProc.running) return
            setProc.pct = root._target
            setProc.running = true
        }
    }

    // No repeating poll (the previous build re-read `brightnessctl g`
    // every 2 s): this service's own writes are optimistic, and the
    // Control Center re-reads once via refresh() every time it opens,
    // which is the only place the value is displayed numerically.
    function refresh() {
        if (!getProc.running && root._target < 0)
            getProc.running = true
    }

    Process {
        id: maxProc

        command: ["brightnessctl", "m"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const n = parseInt(maxProc.stdout.text.trim(), 10)
            root._max = isNaN(n) ? 0 : n
            getProc.running = true
        }
    }

    Process {
        id: getProc

        command: ["brightnessctl", "g"]
        stdout: StdioCollector { waitForEnd: true }

        onExited: {
            const n = parseInt(getProc.stdout.text.trim(), 10)
            if (!isNaN(n) && root._max > 0 && root._target < 0)
                root.brightness = Math.max(1, Math.round(n * 100 / root._max))
        }
    }

    Process {
        id: setProc

        property int pct: 50

        command: ["brightnessctl", "s", setProc.pct + "%"]

        onExited: root._target = -1
    }

    Component.onCompleted: maxProc.running = true
}
